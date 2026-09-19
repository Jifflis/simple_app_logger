#include "simple_app_logger_plugin.h"

#include <windows.h>
#include <shlobj.h>

#include <flutter/standard_method_codec.h>

#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>

namespace {
LPTOP_LEVEL_EXCEPTION_FILTER g_previous_filter = nullptr;
bool g_installed = false;
std::wstring g_report_path;

std::wstring ReportPath() {
  PWSTR local_app_data = nullptr;
  if (SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr,
                           &local_app_data) != S_OK) {
    return L"simple_app_logger_native_crashes.bin";
  }
  std::filesystem::path directory(local_app_data);
  CoTaskMemFree(local_app_data);
  directory /= L"simple_app_logger";
  std::filesystem::create_directories(directory);
  return (directory / L"native_crashes.bin").wstring();
}

LONG WINAPI HandleNativeException(EXCEPTION_POINTERS* exception) {
  HANDLE file = CreateFileW(g_report_path.c_str(), FILE_APPEND_DATA,
                            FILE_SHARE_READ, nullptr, OPEN_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file != INVALID_HANDLE_VALUE) {
    const DWORD code = exception->ExceptionRecord->ExceptionCode;
    DWORD written = 0;
    WriteFile(file, &code, sizeof(code), &written, nullptr);
    FlushFileBuffers(file);
    CloseHandle(file);
  }
  if (g_previous_filter != nullptr) return g_previous_filter(exception);
  return EXCEPTION_CONTINUE_SEARCH;
}

flutter::EncodableList RecoverReports() {
  flutter::EncodableList reports;
  g_report_path = ReportPath();
  std::ifstream input(g_report_path, std::ios::binary);
  DWORD code = 0;
  while (input.read(reinterpret_cast<char*>(&code), sizeof(code))) {
    std::ostringstream message;
    message << "Windows native exception 0x" << std::hex << std::uppercase << code;
    reports.emplace_back(flutter::EncodableMap{
        {flutter::EncodableValue("tag"), flutter::EncodableValue("native_crash")},
        {flutter::EncodableValue("message"), flutter::EncodableValue(message.str())},
        {flutter::EncodableValue("stack_trace"), flutter::EncodableValue("")},
    });
  }
  input.close();
  return reports;
}

void ClearReports() {
  std::ofstream clear(g_report_path, std::ios::binary | std::ios::trunc);
}
}

namespace simple_app_logger {
void SimpleAppLoggerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "simple_app_logger/native_crashes",
      &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<SimpleAppLoggerPlugin>();
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });
  registrar->AddPlugin(std::move(plugin));
}

SimpleAppLoggerPlugin::SimpleAppLoggerPlugin() = default;
SimpleAppLoggerPlugin::~SimpleAppLoggerPlugin() {
  if (g_installed) SetUnhandledExceptionFilter(g_previous_filter);
}

void SimpleAppLoggerPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "acknowledge") {
    ClearReports();
    result->Success();
    return;
  }
  if (call.method_name() != "configure") {
    result->NotImplemented();
    return;
  }
  auto reports = RecoverReports();
  bool enabled = false;
  if (const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments())) {
    const auto found = arguments->find(flutter::EncodableValue("enabled"));
    if (found != arguments->end()) enabled = std::get<bool>(found->second);
  }
  if (enabled) {
    if (!g_installed) {
      g_previous_filter = SetUnhandledExceptionFilter(HandleNativeException);
      g_installed = true;
    }
  } else if (g_installed) {
    SetUnhandledExceptionFilter(g_previous_filter);
    g_previous_filter = nullptr;
    g_installed = false;
  }
  result->Success(flutter::EncodableValue(reports));
}
}
