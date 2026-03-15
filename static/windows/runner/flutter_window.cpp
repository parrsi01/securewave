#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <atomic>
#include <cassert>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <optional>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string_view>
#include <thread>
#include <shlobj.h>
#include <shellapi.h>
#include <winsvc.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
const wchar_t* kWireGuardTunnelName = L"SecureWave";
const wchar_t* kIkev2ConnectionName = L"SecureWave-IKEv2";
constexpr UINT kVpnOpCompleteMessage = WM_APP + 42;
constexpr DWORD kWireGuardCommandTimeoutMs = 30000;
constexpr DWORD kOpenVpnInitTimeoutMs = 30000;
constexpr size_t kMaxPendingVpnOps = 8;

enum class VpnOpType { kConnect, kDisconnect };

enum class TunnelState { kUnknown, kConnected, kDisconnected, kConnecting, kDisconnecting };

enum class ActiveProtocol { kNone, kWireGuard, kOpenVpn, kIkev2 };

struct VpnOpPending {
  VpnOpType type = VpnOpType::kDisconnect;
  ActiveProtocol protocol = ActiveProtocol::kNone;
  std::string wireguard_config;
  std::string openvpn_config;
  std::string username;
  std::string password;
  std::string server;
  std::string remote_id;
  std::string auth_method;
  std::string client_pkcs12_base64;
  std::string client_pkcs12_password;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
  bool ok = false;
  std::string error_code;
  std::string error_message;
};

std::wstring GetEnvVar(const wchar_t* name) {
  wchar_t buffer[32767];
  DWORD size = GetEnvironmentVariableW(
      name, buffer, static_cast<DWORD>(sizeof(buffer) / sizeof(buffer[0])));
  if (size == 0 || size >= (sizeof(buffer) / sizeof(buffer[0]))) {
    return L"";
  }
  return std::wstring(buffer, size);
}

bool FileExists(const std::wstring& path) {
  DWORD attrs = GetFileAttributesW(path.c_str());
  return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::optional<std::wstring> GetWireGuardPath() {
  std::wstring env_override = GetEnvVar(L"SECUREWAVE_WIREGUARD_PATH");
  if (!env_override.empty() && FileExists(env_override)) {
    return env_override;
  }
  std::wstring program_files = GetEnvVar(L"ProgramFiles");
  if (!program_files.empty()) {
    std::wstring candidate = program_files + L"\\WireGuard\\wireguard.exe";
    if (FileExists(candidate)) {
      return candidate;
    }
  }
  std::wstring program_files_x86 = GetEnvVar(L"ProgramFiles(x86)");
  if (!program_files_x86.empty()) {
    std::wstring candidate = program_files_x86 + L"\\WireGuard\\wireguard.exe";
    if (FileExists(candidate)) {
      return candidate;
    }
  }
  if (FileExists(L"C:\\Program Files\\WireGuard\\wireguard.exe")) {
    return std::wstring(L"C:\\Program Files\\WireGuard\\wireguard.exe");
  }
  if (FileExists(L"C:\\Program Files (x86)\\WireGuard\\wireguard.exe")) {
    return std::wstring(L"C:\\Program Files (x86)\\WireGuard\\wireguard.exe");
  }
  return std::nullopt;
}

std::optional<std::wstring> GetOpenVpnPath() {
  std::wstring env_override = GetEnvVar(L"SECUREWAVE_OPENVPN_PATH");
  if (!env_override.empty() && FileExists(env_override)) {
    return env_override;
  }
  std::wstring program_files = GetEnvVar(L"ProgramFiles");
  if (!program_files.empty()) {
    std::wstring candidate = program_files + L"\\OpenVPN\\bin\\openvpn.exe";
    if (FileExists(candidate)) {
      return candidate;
    }
  }
  std::wstring program_files_x86 = GetEnvVar(L"ProgramFiles(x86)");
  if (!program_files_x86.empty()) {
    std::wstring candidate = program_files_x86 + L"\\OpenVPN\\bin\\openvpn.exe";
    if (FileExists(candidate)) {
      return candidate;
    }
  }
  if (FileExists(L"C:\\Program Files\\OpenVPN\\bin\\openvpn.exe")) {
    return std::wstring(L"C:\\Program Files\\OpenVPN\\bin\\openvpn.exe");
  }
  if (FileExists(L"C:\\Program Files (x86)\\OpenVPN\\bin\\openvpn.exe")) {
    return std::wstring(L"C:\\Program Files (x86)\\OpenVPN\\bin\\openvpn.exe");
  }
  return std::nullopt;
}

bool SystemToolExists(const wchar_t* relative_path) {
  wchar_t system_dir[MAX_PATH];
  const UINT length = GetSystemDirectoryW(system_dir, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return false;
  }
  std::filesystem::path full_path(system_dir);
  full_path /= relative_path;
  return FileExists(full_path.wstring());
}

bool HasWindowsIkev2Runtime() {
  return SystemToolExists(L"rasdial.exe") &&
         SystemToolExists(L"WindowsPowerShell\\v1.0\\powershell.exe");
}

std::wstring GetRuntimePath(const wchar_t* file_name) {
  if (!file_name || *file_name == L'\0') {
    return L"";
  }
  PWSTR app_data = nullptr;
  std::wstring config_path;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &app_data))) {
    std::filesystem::path base(app_data);
    CoTaskMemFree(app_data);
    std::filesystem::path dir = base / L"SecureWave";
    std::error_code error;
    std::filesystem::create_directories(dir, error);
    config_path = (dir / std::wstring(file_name)).wstring();
  }
  return config_path;
}

std::wstring QuoteArg(const std::wstring& value) {
  std::wstring escaped = value;
  size_t position = 0;
  while ((position = escaped.find(L"\"", position)) != std::wstring::npos) {
    escaped.replace(position, 1, L"\\\"");
    position += 2;
  }
  return L"\"" + escaped + L"\"";
}

bool WriteTextFile(const std::wstring& path, const std::string& content, std::string* error) {
  if (path.empty()) {
    if (error) {
      *error = "Unable to resolve config path.";
    }
    return false;
  }
  std::ofstream output(std::filesystem::path(path), std::ios::binary | std::ios::trunc);
  if (!output.is_open()) {
    if (error) {
      *error = "Unable to write runtime config file.";
    }
    return false;
  }
  output.write(content.data(), static_cast<std::streamsize>(content.size()));
  return true;
}

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) {
    return L"";
  }
  const int size = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, text.c_str(), static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) {
    return L"";
  }
  std::wstring wide(static_cast<size_t>(size), L'\0');
  if (MultiByteToWideChar(
          CP_UTF8,
          MB_ERR_INVALID_CHARS,
          text.c_str(),
          static_cast<int>(text.size()),
          wide.data(),
          size) <= 0) {
    return L"";
  }
  return wide;
}

std::string WideToUtf8(const std::wstring& text) {
  if (text.empty()) {
    return "";
  }
  const int size = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, text.c_str(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  if (size <= 0) {
    return "";
  }
  std::string utf8(static_cast<size_t>(size), '\0');
  if (WideCharToMultiByte(
          CP_UTF8,
          WC_ERR_INVALID_CHARS,
          text.c_str(),
          static_cast<int>(text.size()),
          utf8.data(),
          size,
          nullptr,
          nullptr) <= 0) {
    return "";
  }
  return utf8;
}

bool RunWireGuardCommand(
    const std::wstring& exe_path,
    const std::wstring& args,
    std::string* error,
    bool* permission_required) {
  if (permission_required) {
    *permission_required = false;
  }
  // WireGuard tunnel service operations require elevation. Launch via ShellExecuteEx
  // with verb "runas" so the user receives an explicit UAC prompt instead of a
  // confusing failure.
  SHELLEXECUTEINFOW sei{};
  sei.cbSize = sizeof(sei);
  sei.fMask = SEE_MASK_NOCLOSEPROCESS;
  sei.hwnd = nullptr;
  sei.lpVerb = L"runas";
  sei.lpFile = exe_path.c_str();
  sei.lpParameters = args.c_str();
  sei.lpDirectory = nullptr;
  sei.nShow = SW_HIDE;

  if (!ShellExecuteExW(&sei)) {
    DWORD last_error = GetLastError();
    if (error) {
      if (last_error == ERROR_CANCELLED) {
        if (permission_required) {
          *permission_required = true;
        }
        *error = "Administrator permission is required to start/stop the VPN tunnel.";
      } else {
        *error = "Failed to launch WireGuard (error " + std::to_string(last_error) +
                 "). Ensure WireGuard is installed and retry.";
      }
    }
    return false;
  }

  if (sei.hProcess == nullptr) {
    if (error) {
      *error = "Failed to launch WireGuard (no process handle).";
    }
    return false;
  }

  DWORD wait_result = WaitForSingleObject(sei.hProcess, kWireGuardCommandTimeoutMs);
  if (wait_result == WAIT_TIMEOUT) {
    TerminateProcess(sei.hProcess, 1);
    CloseHandle(sei.hProcess);
    if (error) {
      *error = "WireGuard command timed out. Please retry.";
    }
    return false;
  }
  if (wait_result == WAIT_FAILED) {
    DWORD last_error = GetLastError();
    CloseHandle(sei.hProcess);
    if (error) {
      *error = "WireGuard wait failed (error " + std::to_string(last_error) + ").";
    }
    return false;
  }

  DWORD exit_code = 0;
  GetExitCodeProcess(sei.hProcess, &exit_code);
  CloseHandle(sei.hProcess);
  if (exit_code != 0) {
    if (error) {
      *error = "WireGuard exited with code " + std::to_string(exit_code) + ".";
    }
    return false;
  }
  return true;
}

bool LaunchElevatedProcess(
    const std::wstring& exe_path,
    const std::wstring& args,
    HANDLE* process_out,
    DWORD* pid_out,
    std::string* error,
    bool* permission_required) {
  if (permission_required) {
    *permission_required = false;
  }
  if (process_out) {
    *process_out = nullptr;
  }
  if (pid_out) {
    *pid_out = 0;
  }

  SHELLEXECUTEINFOW sei{};
  sei.cbSize = sizeof(sei);
  sei.fMask = SEE_MASK_NOCLOSEPROCESS;
  sei.hwnd = nullptr;
  sei.lpVerb = L"runas";
  sei.lpFile = exe_path.c_str();
  sei.lpParameters = args.c_str();
  sei.lpDirectory = nullptr;
  sei.nShow = SW_HIDE;

  if (!ShellExecuteExW(&sei)) {
    DWORD last_error = GetLastError();
    if (error) {
      if (last_error == ERROR_CANCELLED) {
        if (permission_required) {
          *permission_required = true;
        }
        *error = "Administrator permission is required to start the OpenVPN tunnel.";
      } else {
        *error = "Failed to launch OpenVPN (error " + std::to_string(last_error) + ").";
      }
    }
    return false;
  }
  if (sei.hProcess == nullptr) {
    if (error) {
      *error = "Failed to launch OpenVPN (no process handle).";
    }
    return false;
  }
  if (process_out) {
    *process_out = sei.hProcess;
  } else {
    CloseHandle(sei.hProcess);
  }
  if (pid_out) {
    *pid_out = GetProcessId(sei.hProcess);
  }
  return true;
}

bool RunCommandLineWait(
    const std::wstring& command_line,
    DWORD timeout_ms,
    DWORD* exit_code,
    std::string* error) {
  if (exit_code) {
    *exit_code = 1;
  }
  std::wstring mutable_command = command_line;
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process_info{};
  if (!CreateProcessW(
          nullptr,
          mutable_command.data(),
          nullptr,
          nullptr,
          FALSE,
          CREATE_NO_WINDOW,
          nullptr,
          nullptr,
          &startup,
          &process_info)) {
    if (error) {
      *error = "Failed to launch command (error " + std::to_string(GetLastError()) + ").";
    }
    return false;
  }

  DWORD wait_result = WaitForSingleObject(process_info.hProcess, timeout_ms);
  if (wait_result == WAIT_TIMEOUT) {
    TerminateProcess(process_info.hProcess, 1);
    if (error) {
      *error = "Command timed out.";
    }
    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
    return false;
  }
  if (wait_result == WAIT_FAILED) {
    if (error) {
      *error = "Command wait failed (error " + std::to_string(GetLastError()) + ").";
    }
    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
    return false;
  }

  DWORD process_exit_code = 1;
  if (!GetExitCodeProcess(process_info.hProcess, &process_exit_code)) {
    process_exit_code = 1;
  }
  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  if (exit_code) {
    *exit_code = process_exit_code;
  }
  return true;
}

std::wstring BuildPowerShellScriptPath() {
  return GetRuntimePath(L"securewave_ikev2.ps1");
}

bool RunPowerShellScript(
    const std::wstring& script_body,
    DWORD timeout_ms,
    std::string* error) {
  const std::wstring script_path = BuildPowerShellScriptPath();
  if (script_path.empty()) {
    if (error) {
      *error = "Unable to resolve PowerShell script path.";
    }
    return false;
  }
  const std::string utf8_script = WideToUtf8(script_body);
  if (utf8_script.empty()) {
    if (error) {
      *error = "Failed to encode PowerShell script.";
    }
    return false;
  }
  if (!WriteTextFile(script_path, utf8_script, error)) {
    return false;
  }

  const std::wstring command =
      L"powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " +
      QuoteArg(script_path);
  DWORD exit_code = 1;
  if (!RunCommandLineWait(command, timeout_ms, &exit_code, error)) {
    return false;
  }
  if (exit_code != 0) {
    if (error) {
      *error = "PowerShell script exited with code " + std::to_string(exit_code) + ".";
    }
    return false;
  }
  return true;
}

std::string ReadFileUtf8(const std::wstring& path) {
  std::ifstream input(std::filesystem::path(path), std::ios::binary);
  if (!input.is_open()) {
    return "";
  }
  std::ostringstream buffer;
  buffer << input.rdbuf();
  return buffer.str();
}

bool ContainsCaseInsensitive(std::string_view haystack, std::string_view needle) {
  if (needle.empty() || haystack.size() < needle.size()) {
    return false;
  }
  auto to_lower = [](char c) -> char {
    if (c >= 'A' && c <= 'Z') {
      return static_cast<char>(c - 'A' + 'a');
    }
    return c;
  };
  for (size_t i = 0; i + needle.size() <= haystack.size(); i += 1) {
    bool match = true;
    for (size_t j = 0; j < needle.size(); j += 1) {
      if (to_lower(haystack[i + j]) != to_lower(needle[j])) {
        match = false;
        break;
      }
    }
    if (match) {
      return true;
    }
  }
  return false;
}

std::optional<std::string> GetStringArg(const flutter::EncodableValue* value) {
  if (!value) {
    return std::nullopt;
  }
  if (auto string_value = std::get_if<std::string>(value)) {
    return *string_value;
  }
  return std::nullopt;
}

const flutter::EncodableMap* GetMapArg(const flutter::EncodableValue* value) {
  if (!value) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableMap>(value);
}

std::optional<std::string> GetMapString(
    const flutter::EncodableMap* map,
    const char* key) {
  if (!map || !key) {
    return std::nullopt;
  }
  auto it = map->find(flutter::EncodableValue(std::string(key)));
  if (it == map->end()) {
    return std::nullopt;
  }
  return GetStringArg(&it->second);
}

bool ServiceExists(const std::wstring& name) {
  SC_HANDLE manager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (manager == nullptr) {
    return false;
  }
  SC_HANDLE svc = OpenServiceW(manager, name.c_str(), SERVICE_QUERY_STATUS);
  if (svc != nullptr) {
    CloseServiceHandle(svc);
    CloseServiceHandle(manager);
    return true;
  }
  CloseServiceHandle(manager);
  return false;
}

bool TunnelServiceInstalled() {
  // WireGuard for Windows typically uses the service name:
  //   WireGuardTunnel$<tunnelName>
  // where tunnelName is derived from the config filename (SecureWave.conf -> SecureWave).
  if (ServiceExists(std::wstring(L"WireGuardTunnel$") + kWireGuardTunnelName)) {
    return true;
  }
  // Fallback: some builds may expose the tunnel name as the service name.
  return ServiceExists(std::wstring(kWireGuardTunnelName));
}

}  // namespace

struct FlutterWindow::VpnWorker {
  explicit VpnWorker(HWND hwnd) : hwnd_(hwnd) {}

  void Start() {
    std::lock_guard<std::mutex> lock(mu_);
    if (running_) {
      return;
    }
    // Sync initial state to the system tunnel state so connect/disconnect are
    // idempotent across app restarts.
    const bool wg_connected = TunnelServiceInstalled();
    state_ = wg_connected ? TunnelState::kConnected : TunnelState::kDisconnected;
    active_protocol_ = wg_connected ? ActiveProtocol::kWireGuard : ActiveProtocol::kNone;
    stop_ = false;
    running_ = true;
    worker_ = std::thread([this]() { this->Run(); });
  }

  void Stop() {
    std::deque<std::unique_ptr<VpnOpPending>> pending;
    std::deque<std::unique_ptr<VpnOpPending>> completed;
    {
      std::lock_guard<std::mutex> lock(mu_);
      stop_ = true;
      pending.swap(queue_);
      completed.swap(completed_);
    }
    cv_.notify_all();
    if (worker_.joinable()) {
      worker_.join();
    }
    running_ = false;
    CleanupOpenVpnProcess(/*terminate=*/true);

    // Drain anything completed after we took the first snapshot but before the
    // worker thread exited.
    std::deque<std::unique_ptr<VpnOpPending>> completed_after_join;
    {
      std::lock_guard<std::mutex> lock(mu_);
      completed_after_join.swap(completed_);
    }

    // Respond to any operations that were never processed.
    for (auto& op : pending) {
      if (op && op->result) {
        op->result->Error(
            "vpn_shutdown",
            "VPN operation cancelled (app shutting down).",
            nullptr);
      }
    }

    // Flush any completed ops synchronously on the UI thread.
    for (auto& op : completed) {
      if (!op || !op->result) {
        continue;
      }
      if (op->ok) {
        op->result->Success(flutter::EncodableValue());
      } else {
        op->result->Error(op->error_code, op->error_message, nullptr);
      }
    }

    for (auto& op : completed_after_join) {
      if (!op || !op->result) {
        continue;
      }
      if (op->ok) {
        op->result->Success(flutter::EncodableValue());
      } else {
        op->result->Error(op->error_code, op->error_message, nullptr);
      }
    }
  }

  void Enqueue(std::unique_ptr<VpnOpPending> op) {
    assert(op && op->result);
    {
      std::lock_guard<std::mutex> lock(mu_);
      if (stop_) {
        op->result->Error(
            "vpn_shutdown",
            "VPN operation rejected (app shutting down).",
            nullptr);
        return;
      }
      // Defensive: bound queue to avoid runaway memory growth on repeated toggles.
      if (queue_.size() >= kMaxPendingVpnOps) {
        op->result->Error(
            "vpn_busy",
            "VPN operation already in progress. Please wait and retry.",
            nullptr);
        return;
      }
      queue_.push_back(std::move(op));
    }
    cv_.notify_one();
  }

  void DrainCompleted() {
    std::deque<std::unique_ptr<VpnOpPending>> batch;
    {
      std::lock_guard<std::mutex> lock(mu_);
      batch.swap(completed_);
    }
    for (auto& op : batch) {
      if (!op || !op->result) {
        continue;
      }
      if (op->ok) {
        op->result->Success(flutter::EncodableValue());
      } else {
        op->result->Error(op->error_code, op->error_message, nullptr);
      }
    }
  }

  bool IsAvailable() const {
    return GetWireGuardPath().has_value() || GetOpenVpnPath().has_value() ||
           HasWindowsIkev2Runtime();
  }

  std::string CurrentStatus() {
    std::lock_guard<std::mutex> lock(mu_);
    return state_ == TunnelState::kConnected ? "connected" : "disconnected";
  }

 private:
  void Run() {
    while (true) {
      std::unique_ptr<VpnOpPending> op;
      {
        std::unique_lock<std::mutex> lock(mu_);
        cv_.wait(lock, [this]() { return stop_ || !queue_.empty(); });
        if (stop_ && queue_.empty()) {
          return;
        }
        op = std::move(queue_.front());
        queue_.pop_front();
      }

      assert(op && op->result);

      // Tunnel state assertions: operations are processed serially.
      if (op->type == VpnOpType::kConnect) {
        assert(state_ != TunnelState::kConnecting);
        assert(state_ != TunnelState::kDisconnecting);
      } else {
        assert(state_ != TunnelState::kDisconnecting);
        assert(state_ != TunnelState::kConnecting);
      }

      ProcessOperation(*op);

      {
        std::lock_guard<std::mutex> lock(mu_);
        completed_.push_back(std::move(op));
      }

      if (hwnd_ != nullptr) {
        PostMessage(hwnd_, kVpnOpCompleteMessage, 0, 0);
      }
    }
  }

  void ProcessOperation(VpnOpPending& op) {
    if (op.type == VpnOpType::kConnect) {
      if (op.protocol == ActiveProtocol::kNone) {
        SetError(
            op,
            "protocol_unavailable",
            "Requested VPN protocol is not supported on Windows.");
        state_ = TunnelState::kDisconnected;
        return;
      }
      const bool was_connected = (state_ == TunnelState::kConnected);
      if (was_connected && active_protocol_ == op.protocol) {
        op.ok = true;
        return;
      }
      state_ = TunnelState::kConnecting;
      if (was_connected && active_protocol_ != ActiveProtocol::kNone &&
          active_protocol_ != op.protocol) {
        if (!DisconnectActive(op, /*keep_errors=*/true)) {
          state_ = TunnelState::kUnknown;
          return;
        }
      }

      bool connected = false;
      switch (op.protocol) {
        case ActiveProtocol::kWireGuard:
          connected = ConnectWireGuard(op);
          break;
        case ActiveProtocol::kOpenVpn:
          connected = ConnectOpenVpn(op);
          break;
        case ActiveProtocol::kIkev2:
          connected = ConnectIkev2(op);
          break;
        case ActiveProtocol::kNone:
          connected = false;
          break;
      }
      op.ok = connected;
      if (!op.ok) {
        state_ = TunnelState::kDisconnected;
        return;
      }
      active_protocol_ = op.protocol;
      state_ = TunnelState::kConnected;
      return;
    }

    if (state_ == TunnelState::kDisconnected || active_protocol_ == ActiveProtocol::kNone) {
      op.ok = true;
      return;
    }
    state_ = TunnelState::kDisconnecting;
    op.ok = DisconnectActive(op, /*keep_errors=*/false);
    if (!op.ok) {
      state_ = TunnelState::kUnknown;
      return;
    }
    active_protocol_ = ActiveProtocol::kNone;
    state_ = TunnelState::kDisconnected;
  }

  bool ConnectWireGuard(VpnOpPending& op) {
    if (!wireguard_path_.has_value()) {
      wireguard_path_ = GetWireGuardPath();
    }
    if (!wireguard_path_.has_value()) {
      SetError(
          op,
          "vpn_unavailable",
          "WireGuard for Windows not found. Install WireGuard and retry.");
      return false;
    }
    if (wireguard_config_path_.empty()) {
      wireguard_config_path_ = GetRuntimePath(L"SecureWave.conf");
    }
    std::string write_error;
    if (!WriteTextFile(wireguard_config_path_, op.wireguard_config, &write_error)) {
      SetError(op, "vpn_config_write_failed", write_error);
      return false;
    }

    std::string err;
    bool permission_required = false;
    const bool ok = RunWireGuardCommand(
        *wireguard_path_,
        L"/installtunnelservice " + QuoteArg(wireguard_config_path_),
        &err,
        &permission_required);
    if (!ok) {
      SetError(
          op,
          permission_required ? "vpn_permission_required" : "vpn_connect_failed",
          err);
      return false;
    }
    return true;
  }

  bool DisconnectWireGuard(VpnOpPending& op) {
    if (!wireguard_path_.has_value()) {
      wireguard_path_ = GetWireGuardPath();
    }
    if (!wireguard_path_.has_value()) {
      return true;
    }
    if (!TunnelServiceInstalled()) {
      return true;
    }

    std::string err;
    bool permission_required = false;
    const bool ok = RunWireGuardCommand(
        *wireguard_path_,
        std::wstring(L"/uninstalltunnelservice ") + kWireGuardTunnelName,
        &err,
        &permission_required);
    if (!ok) {
      SetError(
          op,
          permission_required ? "vpn_permission_required" : "vpn_disconnect_failed",
          err);
      return false;
    }
    return true;
  }

  bool ConnectOpenVpn(VpnOpPending& op) {
    if (!openvpn_path_.has_value()) {
      openvpn_path_ = GetOpenVpnPath();
    }
    if (!openvpn_path_.has_value()) {
      SetError(
          op,
          "vpn_unavailable",
          "OpenVPN client not found. Install OpenVPN and retry.");
      return false;
    }
    if (openvpn_config_path_.empty()) {
      openvpn_config_path_ = GetRuntimePath(L"SecureWave-openvpn.ovpn");
      openvpn_auth_path_ = GetRuntimePath(L"SecureWave-openvpn.auth");
      openvpn_log_path_ = GetRuntimePath(L"SecureWave-openvpn.log");
      openvpn_pid_path_ = GetRuntimePath(L"SecureWave-openvpn.pid");
    }
    if (openvpn_config_path_.empty() || openvpn_auth_path_.empty() ||
        openvpn_log_path_.empty() || openvpn_pid_path_.empty()) {
      SetError(
          op,
          "vpn_config_write_failed",
          "Unable to prepare OpenVPN runtime files.");
      return false;
    }

    std::string write_error;
    if (!WriteTextFile(openvpn_config_path_, op.openvpn_config, &write_error)) {
      SetError(op, "vpn_config_write_failed", write_error);
      return false;
    }
    const bool has_username = !op.username.empty();
    const bool has_password = !op.password.empty();
    if (has_username != has_password) {
      SetError(
          op,
          "invalid_profile",
          "OpenVPN profile must include both username and password, or neither.");
      return false;
    }
    if (has_username) {
      if (!WriteTextFile(
              openvpn_auth_path_,
              op.username + "\n" + op.password + "\n",
              &write_error)) {
        SetError(op, "vpn_config_write_failed", write_error);
        return false;
      }
    }

    DeleteFileW(openvpn_log_path_.c_str());
    DeleteFileW(openvpn_pid_path_.c_str());
    CleanupOpenVpnProcess(/*terminate=*/true);

    std::wstring args =
        L"--config " + QuoteArg(openvpn_config_path_) + L" --writepid " +
        QuoteArg(openvpn_pid_path_) + L" --log " + QuoteArg(openvpn_log_path_) +
        L" --verb 3";
    if (has_username) {
      args += L" --auth-user-pass " + QuoteArg(openvpn_auth_path_);
    }

    std::string err;
    bool permission_required = false;
    HANDLE process = nullptr;
    DWORD pid = 0;
    if (!LaunchElevatedProcess(
            *openvpn_path_,
            args,
            &process,
            &pid,
            &err,
            &permission_required)) {
      SetError(
          op,
          permission_required ? "vpn_permission_required" : "vpn_connect_failed",
          err);
      return false;
    }

    openvpn_process_ = process;
    openvpn_pid_ = pid;
    const auto started = std::chrono::steady_clock::now();
    while (true) {
      DWORD wait_result = WaitForSingleObject(openvpn_process_, 250);
      if (wait_result == WAIT_OBJECT_0) {
        DWORD exit_code = 1;
        GetExitCodeProcess(openvpn_process_, &exit_code);
        std::string log_tail = ReadFileUtf8(openvpn_log_path_);
        CleanupOpenVpnProcess(/*terminate=*/false);
        SetError(
            op,
            "vpn_connect_failed",
            "OpenVPN exited before initialization (code " +
                std::to_string(exit_code) + "). " +
                (log_tail.empty() ? "" : log_tail));
        return false;
      }

      const std::string log = ReadFileUtf8(openvpn_log_path_);
      if (ContainsCaseInsensitive(log, "Initialization Sequence Completed")) {
        return true;
      }
      if (ContainsCaseInsensitive(log, "AUTH_FAILED") ||
          ContainsCaseInsensitive(log, "Exiting due to fatal error")) {
        CleanupOpenVpnProcess(/*terminate=*/true);
        SetError(op, "vpn_connect_failed", "OpenVPN authentication failed.");
        return false;
      }

      const auto elapsed = std::chrono::steady_clock::now() - started;
      if (elapsed >= std::chrono::milliseconds(kOpenVpnInitTimeoutMs)) {
        CleanupOpenVpnProcess(/*terminate=*/true);
        SetError(
            op,
            "vpn_timeout",
            "OpenVPN timed out before tunnel initialization completed.");
        return false;
      }
    }
  }

  bool DisconnectOpenVpn(VpnOpPending& op) {
    bool disconnected = true;
    if (openvpn_process_ != nullptr) {
      if (!TerminateProcess(openvpn_process_, 0)) {
        disconnected = false;
      }
      WaitForSingleObject(openvpn_process_, 5000);
      CleanupOpenVpnProcess(/*terminate=*/false);
    } else if (!openvpn_pid_path_.empty()) {
      const std::string pid_text = ReadFileUtf8(openvpn_pid_path_);
      int pid = 0;
      if (!pid_text.empty()) {
        try {
          pid = std::stoi(pid_text);
        } catch (...) {
          pid = 0;
        }
      }
      if (pid > 0) {
        std::wstring command =
            L"taskkill /PID " + std::to_wstring(pid) + L" /T /F";
        DWORD exit_code = 1;
        std::string err;
        if (RunCommandLineWait(command, 10000, &exit_code, &err)) {
          disconnected = (exit_code == 0 || exit_code == 128 || exit_code == 255);
        } else {
          disconnected = false;
        }
      }
    }
    DeleteFileW(openvpn_pid_path_.c_str());
    if (!disconnected) {
      SetError(op, "vpn_disconnect_failed", "Failed to stop OpenVPN tunnel.");
      return false;
    }
    return true;
  }

  bool ConnectIkev2(VpnOpPending& op) {
    if (op.server.empty()) {
      SetError(op, "invalid_profile", "IKEv2 profile is missing server.");
      return false;
    }
    const std::string auth_mode =
        op.auth_method.empty() ? "eap-mschapv2" : op.auth_method;
    if (auth_mode != "eap-mschapv2") {
      SetError(
          op,
          "protocol_unavailable",
          "Windows IKEv2 automation currently supports EAP-MSCHAPv2 only. "
          "Set backend SECUREWAVE_IKEV2_AUTH_MODE=eap-mschapv2.");
      return false;
    }
    if (op.username.empty() || op.password.empty()) {
      SetError(
          op,
          "invalid_profile",
          "IKEv2 profile requires username/password for EAP-MSCHAPv2.");
      return false;
    }

    std::wstring escaped_server = Utf8ToWide(op.server);
    size_t pos = 0;
    while ((pos = escaped_server.find(L"'", pos)) != std::wstring::npos) {
      escaped_server.replace(pos, 1, L"''");
      pos += 2;
    }
    std::wstring script =
        L"$ErrorActionPreference='Stop'\n"
        L"$name='" +
        std::wstring(kIkev2ConnectionName) + L"'\n"
                                           L"$existing=Get-VpnConnection -Name $name -ErrorAction SilentlyContinue\n"
                                           L"if ($existing) { Remove-VpnConnection -Name $name -Force -PassThru | Out-Null }\n"
                                           L"Add-VpnConnection -Name $name -ServerAddress '" +
        escaped_server +
        L"' -TunnelType IKEv2 -AuthenticationMethod MSChapv2 -EncryptionLevel Required -RememberCredential -Force | Out-Null\n";
    std::string script_error;
    if (!RunPowerShellScript(script, 30000, &script_error)) {
      SetError(
          op,
          "vpn_setup_failed",
          "Failed to configure Windows IKEv2 profile. " + script_error);
      return false;
    }

    std::wstring rasdial_cmd =
        L"rasdial " + QuoteArg(kIkev2ConnectionName) + L" " +
        QuoteArg(Utf8ToWide(op.username)) + L" " +
        QuoteArg(Utf8ToWide(op.password));
    DWORD exit_code = 1;
    std::string rasdial_error;
    if (!RunCommandLineWait(rasdial_cmd, 30000, &exit_code, &rasdial_error)) {
      SetError(
          op,
          "vpn_connect_failed",
          "Failed to run rasdial for IKEv2 connection. " + rasdial_error);
      return false;
    }
    if (exit_code != 0) {
      SetError(
          op,
          "vpn_connect_failed",
          "Windows IKEv2 connection failed (rasdial exit code " +
              std::to_string(exit_code) + ").");
      return false;
    }
    return true;
  }

  bool DisconnectIkev2(VpnOpPending& op) {
    std::wstring command = L"rasdial " + QuoteArg(kIkev2ConnectionName) + L" /disconnect";
    DWORD exit_code = 0;
    std::string error;
    if (!RunCommandLineWait(command, 15000, &exit_code, &error)) {
      SetError(op, "vpn_disconnect_failed", "Failed to disconnect IKEv2 tunnel. " + error);
      return false;
    }
    // rasdial returns non-zero when no connection exists; treat as idempotent.
    return true;
  }

  bool DisconnectActive(VpnOpPending& op, bool keep_errors) {
    bool ok = true;
    switch (active_protocol_) {
      case ActiveProtocol::kWireGuard:
        ok = DisconnectWireGuard(op);
        break;
      case ActiveProtocol::kOpenVpn:
        ok = DisconnectOpenVpn(op);
        break;
      case ActiveProtocol::kIkev2:
        ok = DisconnectIkev2(op);
        break;
      case ActiveProtocol::kNone:
        ok = true;
        break;
    }
    if (ok) {
      active_protocol_ = ActiveProtocol::kNone;
      return true;
    }
    if (!keep_errors) {
      return false;
    }
    return false;
  }

  void CleanupOpenVpnProcess(bool terminate) {
    if (openvpn_process_ != nullptr) {
      if (terminate) {
        TerminateProcess(openvpn_process_, 0);
        WaitForSingleObject(openvpn_process_, 5000);
      }
      CloseHandle(openvpn_process_);
      openvpn_process_ = nullptr;
    }
    openvpn_pid_ = 0;
  }

  void SetError(VpnOpPending& op, const std::string& code, const std::string& message) {
    op.ok = false;
    op.error_code = code;
    op.error_message = message;
  }

  HWND hwnd_ = nullptr;
  std::mutex mu_;
  std::condition_variable cv_;
  std::deque<std::unique_ptr<VpnOpPending>> queue_;
  std::deque<std::unique_ptr<VpnOpPending>> completed_;
  std::thread worker_;
  bool stop_ = false;
  bool running_ = false;

  TunnelState state_ = TunnelState::kUnknown;
  ActiveProtocol active_protocol_ = ActiveProtocol::kNone;
  std::optional<std::wstring> wireguard_path_;
  std::optional<std::wstring> openvpn_path_;
  std::wstring wireguard_config_path_;
  std::wstring openvpn_config_path_;
  std::wstring openvpn_auth_path_;
  std::wstring openvpn_log_path_;
  std::wstring openvpn_pid_path_;
  HANDLE openvpn_process_ = nullptr;
  DWORD openvpn_pid_ = 0;
};

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  vpn_worker_ = std::make_unique<VpnWorker>(GetHandle());
  vpn_worker_->Start();

  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "securewave/vpn",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "isAvailable") {
          const bool available =
              vpn_worker_ ? vpn_worker_->IsAvailable() : HasWindowsIkev2Runtime();
          result->Success(flutter::EncodableValue(available));
          return;
        }
        if (call.method_name() == "getCapabilities") {
          const bool wireguard = GetWireGuardPath().has_value();
          const bool openvpn = GetOpenVpnPath().has_value();
          const bool ikev2 = HasWindowsIkev2Runtime();
          flutter::EncodableMap capabilities;
          capabilities[flutter::EncodableValue("wireguard")] = flutter::EncodableValue(wireguard);
          capabilities[flutter::EncodableValue("openvpn")] = flutter::EncodableValue(openvpn);
          capabilities[flutter::EncodableValue("ikev2")] = flutter::EncodableValue(ikev2);
          capabilities[flutter::EncodableValue("windows_thread_safe")] =
              flutter::EncodableValue(true);
          capabilities[flutter::EncodableValue("android_vpnservice_based")] =
              flutter::EncodableValue(false);
          capabilities[flutter::EncodableValue("macos_entitlements_ready")] =
              flutter::EncodableValue(true);
          if (!wireguard) {
            capabilities[flutter::EncodableValue("wireguard_install_hint")] =
                flutter::EncodableValue(
                    "WireGuard for Windows is not installed. Install WireGuard and retry.");
          }
          if (!openvpn) {
            capabilities[flutter::EncodableValue("openvpn_install_hint")] =
                flutter::EncodableValue(
                    "OpenVPN client is not installed. Install OpenVPN and retry.");
          }
          if (ikev2) {
            capabilities[flutter::EncodableValue("ikev2_install_hint")] =
                flutter::EncodableValue(
                    "Windows IKEv2 runtime supports EAP-MSCHAPv2 automation. "
                    "EAP-TLS requires manual certificate profile handling.");
          }
          result->Success(flutter::EncodableValue(capabilities));
          return;
        }
        if (call.method_name() == "getStatus") {
          const std::string status =
              vpn_worker_ ? vpn_worker_->CurrentStatus() : "disconnected";
          result->Success(flutter::EncodableValue(status));
          return;
        }
        if (call.method_name() == "connect") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          std::string protocol = "wireguard";
          std::optional<std::string> config;
          const flutter::EncodableMap* profile = nullptr;
          if (args) {
            const auto protocol_it = args->find(flutter::EncodableValue("protocol"));
            if (protocol_it != args->end()) {
              protocol = GetStringArg(&protocol_it->second).value_or("wireguard");
            }
            const auto config_it = args->find(flutter::EncodableValue("config"));
            if (config_it != args->end()) {
              config = GetStringArg(&config_it->second);
            }
            const auto profile_it = args->find(flutter::EncodableValue("profile"));
            if (profile_it != args->end()) {
              profile = GetMapArg(&profile_it->second);
            }
          }

          auto op = std::make_unique<VpnOpPending>();
          op->type = VpnOpType::kConnect;
          if (protocol == "wireguard" || protocol == "wg" || protocol == "auto") {
            op->protocol = ActiveProtocol::kWireGuard;
            if ((!config || config->empty()) && profile != nullptr) {
              config = GetMapString(profile, "wireguard_config");
            }
            if (!config || config->empty()) {
              result->Error("invalid_config", "Missing WireGuard configuration.", nullptr);
              return;
            }
            op->wireguard_config = *config;
          } else if (protocol == "openvpn") {
            op->protocol = ActiveProtocol::kOpenVpn;
            op->openvpn_config = GetMapString(profile, "ovpn_config").value_or("");
            op->username = GetMapString(profile, "username").value_or("");
            op->password = GetMapString(profile, "password").value_or("");
            if (op.openvpn_config.empty()) {
              result->Error("invalid_profile", "OpenVPN profile is missing ovpn_config.", nullptr);
              return;
            }
          } else if (protocol == "ikev2" || protocol == "ipsec") {
            op->protocol = ActiveProtocol::kIkev2;
            op->server = GetMapString(profile, "server").value_or("");
            op->remote_id = GetMapString(profile, "remote_id").value_or("");
            op->username = GetMapString(profile, "username").value_or("");
            op->password = GetMapString(profile, "password").value_or("");
            op->auth_method = GetMapString(profile, "auth_method").value_or("");
            op->client_pkcs12_base64 =
                GetMapString(profile, "client_pkcs12_base64").value_or("");
            op->client_pkcs12_password =
                GetMapString(profile, "client_pkcs12_password").value_or("");
            if (op.server.empty()) {
              result->Error("invalid_profile", "IKEv2 profile is missing server.", nullptr);
              return;
            }
          } else {
            result->Error(
                "protocol_unavailable",
                "Requested protocol is not supported on Windows.",
                nullptr);
            return;
          }
          op->result = std::move(result);
          vpn_worker_->Enqueue(std::move(op));
          return;
        } else if (call.method_name() == "disconnect") {
          auto op = std::make_unique<VpnOpPending>();
          op->type = VpnOpType::kDisconnect;
          op->result = std::move(result);
          vpn_worker_->Enqueue(std::move(op));
          return;
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (vpn_worker_) {
    vpn_worker_->Stop();
    vpn_worker_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kVpnOpCompleteMessage) {
    if (vpn_worker_) {
      vpn_worker_->DrainCompleted();
    }
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
