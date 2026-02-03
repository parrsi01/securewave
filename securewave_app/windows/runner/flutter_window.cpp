#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <optional>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <shlobj.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
const wchar_t* kTunnelName = L"SecureWave";

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
    std::string* error) {
  std::wstring command = L"\"" + exe_path + L"\" " + args;
  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info{};
  std::wstring mutable_command = command;
  if (!CreateProcessW(
          nullptr, mutable_command.data(), nullptr, nullptr, FALSE, 0, nullptr,
          nullptr, &startup_info, &process_info)) {
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

}  // namespace

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
            result->Error("vpn_unavailable",
                          "WireGuard for Windows not found. Install WireGuard and retry.",
                          flutter::EncodableValue(flutter::EncodableMap{
                              {flutter::EncodableValue("platform"), flutter::EncodableValue("windows")},
                              {flutter::EncodableValue("configured"), flutter::EncodableValue(false)}
                          }));
            return;
          }
          const std::wstring config_path = GetConfigPath();
          std::string error;
          if (!WriteConfigFile(config_path, *config, &error)) {
            result->Error("vpn_config_write_failed", error, nullptr);
            return;
          }
          if (!RunWireGuardCommand(
                  *wireguard_path,
                  L"/installtunnelservice \"" + config_path + L"\"",
                  &error)) {
            result->Error("vpn_connect_failed", error, nullptr);
            return;
          }
          result->Success(flutter::EncodableValue());
        } else if (call.method_name() == "disconnect") {
          const auto wireguard_path = GetWireGuardPath();
          if (!wireguard_path.has_value()) {
            result->Error("vpn_unavailable",
                          "WireGuard for Windows not found. Install WireGuard and retry.",
                          flutter::EncodableValue(flutter::EncodableMap{
                              {flutter::EncodableValue("platform"), flutter::EncodableValue("windows")},
                              {flutter::EncodableValue("configured"), flutter::EncodableValue(false)}
                          }));
            return;
          }
          std::string error;
          if (!RunWireGuardCommand(
                  *wireguard_path,
                  std::wstring(L"/uninstalltunnelservice ") + kTunnelName,
                  &error)) {
            result->Error("vpn_disconnect_failed", error, nullptr);
            return;
          }
          result->Success(flutter::EncodableValue());
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
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
