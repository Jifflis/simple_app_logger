#include "include/simple_app_logger/simple_app_logger_plugin.h"

#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <cstring>
#include <fstream>
#include <string>

#define SIMPLE_APP_LOGGER_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), simple_app_logger_plugin_get_type(), \
                              SimpleAppLoggerPlugin))

struct _SimpleAppLoggerPlugin { GObject parent_instance; };
G_DEFINE_TYPE(SimpleAppLoggerPlugin, simple_app_logger_plugin, g_object_get_type())

namespace {
constexpr std::array<int, 6> kSignals = {SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP};
std::array<struct sigaction, kSignals.size()> g_previous{};
int g_fd = -1;

std::string SignalPath() {
  const gchar* data_dir = g_get_user_data_dir();
  std::string directory = std::string(data_dir) + "/simple_app_logger";
  g_mkdir_with_parents(directory.c_str(), 0700);
  return directory + "/native_signals.bin";
}

void HandleSignal(int signal_number, siginfo_t* info, void* context) {
  if (g_fd >= 0) {
    const int saved_errno = errno;
    write(g_fd, &signal_number, sizeof(signal_number));
    fsync(g_fd);
    errno = saved_errno;
  }
  for (size_t i = 0; i < kSignals.size(); ++i) {
    if (kSignals[i] != signal_number) continue;
    const auto previous = g_previous[i];
    sigaction(signal_number, &previous, nullptr);
    if ((previous.sa_flags & SA_SIGINFO) && previous.sa_sigaction != nullptr) {
      previous.sa_sigaction(signal_number, info, context);
      return;
    }
    if (previous.sa_handler != SIG_DFL && previous.sa_handler != SIG_IGN &&
        previous.sa_handler != nullptr) {
      previous.sa_handler(signal_number);
      return;
    }
    raise(signal_number);
    return;
  }
}

void InstallHandlers() {
  if (g_fd >= 0) return;
  g_fd = open(SignalPath().c_str(), O_CREAT | O_WRONLY | O_APPEND, 0600);
  struct sigaction action{};
  sigemptyset(&action.sa_mask);
  action.sa_sigaction = HandleSignal;
  action.sa_flags = SA_SIGINFO | SA_RESETHAND;
  for (size_t i = 0; i < kSignals.size(); ++i) {
    sigaction(kSignals[i], &action, &g_previous[i]);
  }
}

void UninstallHandlers() {
  if (g_fd < 0) return;
  for (size_t i = 0; i < kSignals.size(); ++i) {
    sigaction(kSignals[i], &g_previous[i], nullptr);
  }
  close(g_fd);
  g_fd = -1;
}

FlValue* RecoverReports() {
  FlValue* reports = fl_value_new_list();
  std::ifstream input(SignalPath(), std::ios::binary);
  int signal_number = 0;
  while (input.read(reinterpret_cast<char*>(&signal_number), sizeof(signal_number))) {
    FlValue* report = fl_value_new_map();
    fl_value_set_string_take(report, "tag", fl_value_new_string("native_crash"));
    const std::string message = "Linux native signal " + std::to_string(signal_number);
    fl_value_set_string_take(report, "message", fl_value_new_string(message.c_str()));
    fl_value_set_string_take(report, "stack_trace", fl_value_new_string(""));
    fl_value_append_take(reports, report);
  }
  input.close();
  return reports;
}

void ClearReports() {
  std::ofstream clear(SignalPath(), std::ios::binary | std::ios::trunc);
}
}

static void HandleMethodCall(SimpleAppLoggerPlugin*, FlMethodCall* call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(call), "acknowledge") == 0) {
    ClearReports();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(fl_method_call_get_name(call), "configure") != 0) {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  } else {
    FlValue* args = fl_method_call_get_args(call);
    FlValue* enabled_value = fl_value_lookup_string(args, "enabled");
    const bool enabled = enabled_value && fl_value_get_bool(enabled_value);
    FlValue* reports = RecoverReports();
    if (enabled) InstallHandlers(); else UninstallHandlers();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(reports));
  }
  fl_method_call_respond(call, response, nullptr);
}

static void MethodCallCallback(FlMethodChannel*, FlMethodCall* call,
                               gpointer user_data) {
  HandleMethodCall(SIMPLE_APP_LOGGER_PLUGIN(user_data), call);
}

static void simple_app_logger_plugin_dispose(GObject* object) {
  UninstallHandlers();
  G_OBJECT_CLASS(simple_app_logger_plugin_parent_class)->dispose(object);
}

static void simple_app_logger_plugin_class_init(SimpleAppLoggerPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = simple_app_logger_plugin_dispose;
}
static void simple_app_logger_plugin_init(SimpleAppLoggerPlugin*) {}

void simple_app_logger_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  SimpleAppLoggerPlugin* plugin = SIMPLE_APP_LOGGER_PLUGIN(
      g_object_new(simple_app_logger_plugin_get_type(), nullptr));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "simple_app_logger/native_crashes", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, MethodCallCallback,
                                            g_object_ref(plugin), g_object_unref);
  g_object_unref(plugin);
}
