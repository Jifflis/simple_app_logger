#ifndef FLUTTER_PLUGIN_SIMPLE_APP_LOGGER_PLUGIN_H_
#define FLUTTER_PLUGIN_SIMPLE_APP_LOGGER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace simple_app_logger {
class SimpleAppLoggerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);
  SimpleAppLoggerPlugin();
  ~SimpleAppLoggerPlugin() override;
  SimpleAppLoggerPlugin(const SimpleAppLoggerPlugin&) = delete;
  SimpleAppLoggerPlugin& operator=(const SimpleAppLoggerPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};
}
#endif
