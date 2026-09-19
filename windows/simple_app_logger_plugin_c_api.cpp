#include "include/simple_app_logger/simple_app_logger_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "simple_app_logger_plugin.h"

void SimpleAppLoggerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  simple_app_logger::SimpleAppLoggerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
