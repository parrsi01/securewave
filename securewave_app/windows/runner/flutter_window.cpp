#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <iphlpapi.h>
#include <netioapi.h>
#include <optional>
#include <vector>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <shlobj.h>
#include <ws2tcpip.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
const wchar_t* kTunnelName = L"SecureWave";
const char* kVpnChannelName = "securewave/vpn";
const char* kTrafficChannelName = "securewave/traffic_stats";
const char* kTunnelStatusChannelName = "securewave/tunnel_status";

struct TunnelAdapterInfo {
  std::wstring name;
  NET_LUID luid{};
  ULONG interface_index = 0;
  bool oper_up = false;
  unsigned long long rx_bytes = 0;
  unsigned long long tx_bytes = 0;
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

bool RunWireGuardCommand(const std::wstring& exe_path,
                         const std::wstring& args,
                         std::string* error) {
  std::wstring command = L"\"" + exe_path + L"\" " + args;
  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info{};
  std::wstring mutable_command = command;
  if (!CreateProcessW(nullptr, mutable_command.data(), nullptr, nullptr, FALSE, 0,
                      nullptr, nullptr, &startup_info, &process_info)) {
    if (error) {
      *error = "Failed to launch WireGuard. Ensure the app has required privileges.";
    }
    return false;
  }
  WaitForSingleObject(process_info.hProcess, INFINITE);
  DWORD exit_code = 0;
  GetExitCodeProcess(process_info.hProcess, &exit_code);
  CloseHandle(process_info.hProcess);
  CloseHandle(process_info.hThread);
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

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  int size_needed = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                        static_cast<int>(value.size()), nullptr, 0,
                                        nullptr, nullptr);
  std::string result(size_needed, 0);
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
                      result.data(), size_needed, nullptr, nullptr);
  return result;
}

bool IsTunnelAdapterName(const std::wstring& name) {
  return name.find(L"WireGuard") != std::wstring::npos ||
         name.find(L"Wintun") != std::wstring::npos ||
         name.find(L"SecureWave") != std::wstring::npos;
}

std::optional<TunnelAdapterInfo> GetTunnelAdapterInfo() {
  ULONG buffer_length = 15 * 1024;
  std::vector<unsigned char> buffer(buffer_length);
  IP_ADAPTER_ADDRESSES* addresses =
      reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());

  ULONG flags = GAA_FLAG_INCLUDE_ALL_INTERFACES;
  ULONG result = GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, addresses, &buffer_length);
  if (result == ERROR_BUFFER_OVERFLOW) {
    buffer.resize(buffer_length);
    addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
    result = GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, addresses, &buffer_length);
  }
  if (result != NO_ERROR) {
    return std::nullopt;
  }

  for (auto* current = addresses; current != nullptr; current = current->Next) {
    std::wstring friendly_name = current->FriendlyName ? current->FriendlyName : L"";
    if (!IsTunnelAdapterName(friendly_name)) {
      continue;
    }
    MIB_IF_ROW2 row{};
    row.InterfaceLuid = current->Luid;
    if (GetIfEntry2(&row) != NO_ERROR) {
      continue;
    }
    TunnelAdapterInfo info;
    info.name = friendly_name;
    info.luid = current->Luid;
    info.interface_index = row.InterfaceIndex;
    info.oper_up = row.OperStatus == IfOperStatusUp;
    info.rx_bytes = row.InOctets;
    info.tx_bytes = row.OutOctets;
    return info;
  }

  return std::nullopt;
}

bool IsTunnelBestRoute(const TunnelAdapterInfo& adapter) {
  SOCKADDR_INET destination{};
  destination.si_family = AF_INET;
  inet_pton(AF_INET, "1.1.1.1", &destination.Ipv4.sin_addr);

  MIB_IPFORWARD_ROW2 best_route{};
  SOCKADDR_INET best_source{};
  if (GetBestRoute2(nullptr, 0, nullptr, reinterpret_cast<SOCKADDR*>(&destination),
                    0, &best_route, reinterpret_cast<SOCKADDR*>(&best_source)) != NO_ERROR) {
    return false;
  }
  return best_route.InterfaceLuid.Value == adapter.luid.Value;
}

flutter::EncodableValue BuildTrafficPayload() {
  flutter::EncodableMap payload;
  const auto adapter = GetTunnelAdapterInfo();
  payload[flutter::EncodableValue("rxBytes")] =
      flutter::EncodableValue(static_cast<int64_t>(adapter ? adapter->rx_bytes : 0));
  payload[flutter::EncodableValue("txBytes")] =
      flutter::EncodableValue(static_cast<int64_t>(adapter ? adapter->tx_bytes : 0));
  payload[flutter::EncodableValue("interfaceName")] =
      flutter::EncodableValue(adapter ? WideToUtf8(adapter->name) : std::string());
  return flutter::EncodableValue(payload);
}

flutter::EncodableValue BuildTunnelStatusPayload() {
  flutter::EncodableMap payload;
  const auto adapter = GetTunnelAdapterInfo();
  const bool interface_ok = adapter.has_value();
  const bool routing_ok = adapter.has_value() && IsTunnelBestRoute(*adapter);
  std::string status = "DISCONNECTED";
  if (adapter.has_value() && adapter->oper_up) {
    status = "CONNECTED";
  } else if (adapter.has_value()) {
    status = "ERROR";
  }

  payload[flutter::EncodableValue("status")] = flutter::EncodableValue(status);
  payload[flutter::EncodableValue("interfaceName")] = flutter::EncodableValue(
      adapter ? WideToUtf8(adapter->name) : std::string());
  payload[flutter::EncodableValue("interfaceOk")] =
      flutter::EncodableValue(interface_ok);
  payload[flutter::EncodableValue("routingOk")] =
      flutter::EncodableValue(routing_ok);
  payload[flutter::EncodableValue("details")] = flutter::EncodableValue(
      interface_ok ? "Detected WireGuard/Wintun adapter."
                   : "No WireGuard/Wintun adapter detected.");
  return flutter::EncodableValue(payload);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  auto vpn_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), kVpnChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  auto traffic_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kTrafficChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  auto tunnel_status_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kTunnelStatusChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  vpn_channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "isAvailable") {
          result->Success(flutter::EncodableValue(GetWireGuardPath().has_value()));
          return;
        }
        if (call.method_name() == "connect") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          std::optional<std::string> config;
          if (args) {
            const auto config_it = args->find(flutter::EncodableValue("config"));
            if (config_it != args->end()) {
              config = GetStringArg(&config_it->second);
            }
          }
          if (!config || config->empty()) {
            result->Error("invalid_config", "Missing WireGuard configuration.", nullptr);
            return;
          }
          const auto wireguard_path = GetWireGuardPath();
          if (!wireguard_path.has_value()) {
            result->Error(
                "vpn_unavailable",
                "WireGuard for Windows not found. Install WireGuard and retry.",
                flutter::EncodableValue(flutter::EncodableMap{
                    {flutter::EncodableValue("platform"),
                     flutter::EncodableValue("windows")},
                    {flutter::EncodableValue("configured"),
                     flutter::EncodableValue(false)}}));
            return;
          }
          const std::wstring config_path = GetConfigPath();
          std::string error;
          if (!WriteConfigFile(config_path, *config, &error)) {
            result->Error("vpn_config_write_failed", error, nullptr);
            return;
          }
          if (!RunWireGuardCommand(*wireguard_path,
                                   L"/installtunnelservice \"" + config_path + L"\"",
                                   &error)) {
            result->Error("vpn_connect_failed", error, nullptr);
            return;
          }
          result->Success(flutter::EncodableValue());
          return;
        }
        if (call.method_name() == "disconnect") {
          const auto wireguard_path = GetWireGuardPath();
          if (!wireguard_path.has_value()) {
            result->Error(
                "vpn_unavailable",
                "WireGuard for Windows not found. Install WireGuard and retry.",
                flutter::EncodableValue(flutter::EncodableMap{
                    {flutter::EncodableValue("platform"),
                     flutter::EncodableValue("windows")},
                    {flutter::EncodableValue("configured"),
                     flutter::EncodableValue(false)}}));
            return;
          }
          std::string error;
          if (!RunWireGuardCommand(*wireguard_path,
                                   std::wstring(L"/uninstalltunnelservice ") + kTunnelName,
                                   &error)) {
            result->Error("vpn_disconnect_failed", error, nullptr);
            return;
          }
          result->Success(flutter::EncodableValue());
          return;
        }
        result->NotImplemented();
      });

  traffic_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getTrafficStats") {
          result->Success(BuildTrafficPayload());
          return;
        }
        result->NotImplemented();
      });

  tunnel_status_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getTunnelStatus") {
          result->Success(BuildTunnelStatusPayload());
          return;
        }
        result->NotImplemented();
      });

  vpn_channel_ = std::move(vpn_channel);
  traffic_channel_ = std::move(traffic_channel);
  tunnel_status_channel_ = std::move(tunnel_status_channel);

  flutter_controller_->engine()->SetNextFrameCallback([&]() { this->Show(); });
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  vpn_channel_.reset();
  traffic_channel_.reset();
  tunnel_status_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
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
