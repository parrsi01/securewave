#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <atomic>
#include <cassert>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <optional>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <thread>
#include <shlobj.h>
#include <shellapi.h>
#include <winsvc.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
const wchar_t* kTunnelName = L"SecureWave";
constexpr UINT kVpnOpCompleteMessage = WM_APP + 42;
constexpr DWORD kWireGuardCommandTimeoutMs = 30000;
constexpr size_t kMaxPendingVpnOps = 8;

enum class VpnOpType { kConnect, kDisconnect };

enum class TunnelState { kUnknown, kConnected, kDisconnected, kConnecting, kDisconnecting };

struct VpnOpPending {
  VpnOpType type = VpnOpType::kDisconnect;
  std::string config;  // only used for connect
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

std::wstring GetConfigPath() {
  PWSTR app_data = nullptr;
  std::wstring config_path;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &app_data))) {
    std::filesystem::path base(app_data);
    CoTaskMemFree(app_data);
    std::filesystem::path dir = base / L"SecureWave";
    std::error_code error;
    std::filesystem::create_directories(dir, error);
    config_path = (dir / L"SecureWave.conf").wstring();
  }
  return config_path;
}

bool WriteConfigFile(const std::wstring& path, const std::string& config, std::string* error) {
  if (path.empty()) {
    if (error) {
      *error = "Unable to resolve config path.";
    }
    return false;
  }
  std::ofstream output(path, std::ios::binary | std::ios::trunc);
  if (!output.is_open()) {
    if (error) {
      *error = "Unable to write WireGuard config file.";
    }
    return false;
  }
  output.write(config.data(), static_cast<std::streamsize>(config.size()));
  return true;
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

std::optional<std::string> GetStringArg(const flutter::EncodableValue* value) {
  if (!value) {
    return std::nullopt;
  }
  if (auto string_value = std::get_if<std::string>(value)) {
    return *string_value;
  }
  return std::nullopt;
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
  if (ServiceExists(std::wstring(L"WireGuardTunnel$") + kTunnelName)) {
    return true;
  }
  // Fallback: some builds may expose the tunnel name as the service name.
  return ServiceExists(std::wstring(kTunnelName));
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
    state_ = TunnelServiceInstalled() ? TunnelState::kConnected : TunnelState::kDisconnected;
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
    // Resolve WireGuard executable lazily.
    if (!wireguard_path_.has_value()) {
      wireguard_path_ = GetWireGuardPath();
    }
    if (!wireguard_path_.has_value()) {
      op.ok = false;
      op.error_code = "vpn_unavailable";
      op.error_message =
          "WireGuard for Windows not found. Install WireGuard and retry.";
      return;
    }
    if (config_path_.empty()) {
      config_path_ = GetConfigPath();
    }

    if (op.type == VpnOpType::kConnect) {
      if (state_ == TunnelState::kConnected) {
        op.ok = true;  // idempotent
        return;
      }

      state_ = TunnelState::kConnecting;

      std::string write_error;
      if (!WriteConfigFile(config_path_, op.config, &write_error)) {
        state_ = TunnelState::kDisconnected;
        op.ok = false;
        op.error_code = "vpn_config_write_failed";
        op.error_message = write_error;
        return;
      }

      std::string err;
      bool permission_required = false;
      op.ok = RunWireGuardCommand(
          *wireguard_path_,
          L"/installtunnelservice \"" + config_path_ + L"\"",
          &err,
          &permission_required);
      if (!op.ok) {
        state_ = TunnelState::kDisconnected;
        op.error_code = permission_required ? "vpn_permission_required" : "vpn_connect_failed";
        op.error_message = err;
        return;
      }
      state_ = TunnelState::kConnected;
      return;
    }

    // Disconnect
    if (state_ == TunnelState::kDisconnected) {
      op.ok = true;  // idempotent
      return;
    }

    // If the tunnel service isn't installed, treat disconnect as a no-op.
    if (!TunnelServiceInstalled()) {
      state_ = TunnelState::kDisconnected;
      op.ok = true;
      return;
    }

    state_ = TunnelState::kDisconnecting;

    std::string err;
    bool permission_required = false;
    op.ok = RunWireGuardCommand(
        *wireguard_path_,
        std::wstring(L"/uninstalltunnelservice ") + kTunnelName,
        &err,
        &permission_required);
    if (!op.ok) {
      // Keep state unknown; we couldn't deterministically stop it.
      state_ = TunnelState::kUnknown;
      op.error_code = permission_required ? "vpn_permission_required" : "vpn_disconnect_failed";
      op.error_message = err;
      return;
    }
    state_ = TunnelState::kDisconnected;
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
  std::optional<std::wstring> wireguard_path_;
  std::wstring config_path_;
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
          const bool available = GetWireGuardPath().has_value();
          result->Success(flutter::EncodableValue(available));
          return;
        }
        if (call.method_name() == "getCapabilities") {
          flutter::EncodableMap capabilities;
          capabilities[flutter::EncodableValue("wireguard")] =
              flutter::EncodableValue(GetWireGuardPath().has_value());
          capabilities[flutter::EncodableValue("openvpn")] = flutter::EncodableValue(false);
          capabilities[flutter::EncodableValue("ikev2")] = flutter::EncodableValue(false);
          capabilities[flutter::EncodableValue("l2tp")] = flutter::EncodableValue(false);
          capabilities[flutter::EncodableValue("shadowsocks")] = flutter::EncodableValue(false);
          capabilities[flutter::EncodableValue("tcp_fallback")] = flutter::EncodableValue(false);
          capabilities[flutter::EncodableValue("quic")] = flutter::EncodableValue(false);
          capabilities[flutter::EncodableValue("windows_thread_safe")] =
              flutter::EncodableValue(true);
          capabilities[flutter::EncodableValue("android_vpnservice_based")] =
              flutter::EncodableValue(false);
          capabilities[flutter::EncodableValue("macos_entitlements_ready")] =
              flutter::EncodableValue(true);
          result->Success(flutter::EncodableValue(capabilities));
          return;
        }
        if (call.method_name() == "getStatus") {
          // Best-effort status for boot-time UI sync.
          const bool connected = TunnelServiceInstalled();
          result->Success(flutter::EncodableValue(connected ? "connected" : "disconnected"));
          return;
        }
        if (call.method_name() == "connect") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          std::optional<std::string> protocol;
          std::optional<std::string> config;
          if (args) {
            const auto protocol_it = args->find(flutter::EncodableValue("protocol"));
            if (protocol_it != args->end()) {
              protocol = GetStringArg(&protocol_it->second);
            }
            const auto config_it = args->find(flutter::EncodableValue("config"));
            if (config_it != args->end()) {
              config = GetStringArg(&config_it->second);
            }
          }
          if (protocol.has_value()) {
            if (*protocol != "wireguard" && *protocol != "wg") {
              result->Error(
                  "protocol_unavailable",
                  "Windows runtime currently supports WireGuard only.",
                  nullptr);
              return;
            }
          }
          if (!config || config->empty()) {
            result->Error("invalid_config", "Missing WireGuard configuration.", nullptr);
            return;
          }
          auto op = std::make_unique<VpnOpPending>();
          op->type = VpnOpType::kConnect;
          op->config = *config;
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
