#include <jni.h>
#include <cerrno>
#include <cstddef>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

#include <array>

namespace {
constexpr std::array<int, 6> kSignals = {SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP};
std::array<struct sigaction, kSignals.size()> g_previous{};
int g_fd = -1;

void HandleSignal(int signal_number, siginfo_t* info, void* context) {
  if (g_fd >= 0) {
    const int saved_errno = errno;
    write(g_fd, &signal_number, sizeof(signal_number));
    fsync(g_fd);
    errno = saved_errno;
  }
  for (size_t i = 0; i < kSignals.size(); ++i) {
    if (kSignals[i] != signal_number) continue;
    const auto& previous = g_previous[i];
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
}

extern "C" JNIEXPORT void JNICALL
Java_com_idmakers_simple_1app_1logger_SimpleAppLoggerPlugin_installSignalHandler(
    JNIEnv* env, jobject, jstring path) {
  const char* native_path = env->GetStringUTFChars(path, nullptr);
  if (g_fd >= 0) close(g_fd);
  g_fd = open(native_path, O_CREAT | O_WRONLY | O_APPEND, 0600);
  env->ReleaseStringUTFChars(path, native_path);
  struct sigaction action{};
  sigemptyset(&action.sa_mask);
  action.sa_sigaction = HandleSignal;
  action.sa_flags = SA_SIGINFO | SA_RESETHAND;
  for (size_t i = 0; i < kSignals.size(); ++i) {
    sigaction(kSignals[i], &action, &g_previous[i]);
  }
}

extern "C" JNIEXPORT void JNICALL
Java_com_idmakers_simple_1app_1logger_SimpleAppLoggerPlugin_uninstallSignalHandler(
    JNIEnv*, jobject) {
  for (size_t i = 0; i < kSignals.size(); ++i) {
    sigaction(kSignals[i], &g_previous[i], nullptr);
  }
  if (g_fd >= 0) close(g_fd);
  g_fd = -1;
}
