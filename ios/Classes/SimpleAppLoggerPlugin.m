#import "SimpleAppLoggerPlugin.h"

#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>

static const int SALSignals[] = {SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP};
static struct sigaction SALPreviousActions[6];
static int SALSignalFD = -1;
static NSUncaughtExceptionHandler *SALPreviousExceptionHandler = nil;

static NSString *SALDirectory(void) {
  NSString *directory = NSSearchPathForDirectoriesInDomains(
      NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
  directory = [directory stringByAppendingPathComponent:@"simple_app_logger"];
  [[NSFileManager defaultManager] createDirectoryAtPath:directory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
  return directory;
}

static NSString *SALSignalPath(void) {
  return [SALDirectory() stringByAppendingPathComponent:@"native_signals.bin"];
}

static NSString *SALExceptionPath(void) {
  return [SALDirectory() stringByAppendingPathComponent:@"native_exceptions.jsonl"];
}

static void SALHandleSignal(int signalNumber, siginfo_t *info, void *context) {
  if (SALSignalFD >= 0) {
    int savedErrno = errno;
    write(SALSignalFD, &signalNumber, sizeof(signalNumber));
    fsync(SALSignalFD);
    errno = savedErrno;
  }
  for (NSUInteger index = 0; index < 6; index++) {
    if (SALSignals[index] != signalNumber) continue;
    struct sigaction previous = SALPreviousActions[index];
    sigaction(signalNumber, &previous, NULL);
    if ((previous.sa_flags & SA_SIGINFO) && previous.sa_sigaction != NULL) {
      previous.sa_sigaction(signalNumber, info, context);
      return;
    }
    if (previous.sa_handler != SIG_DFL && previous.sa_handler != SIG_IGN &&
        previous.sa_handler != NULL) {
      previous.sa_handler(signalNumber);
      return;
    }
    raise(signalNumber);
    return;
  }
}

static void SALHandleException(NSException *exception) {
  NSDictionary *report = @{
    @"tag": @"native_crash",
    @"message": [NSString stringWithFormat:@"Apple uncaught exception %@: %@",
                  exception.name, exception.reason ?: @""],
    @"stack_trace": [exception.callStackSymbols componentsJoinedByString:@"\n"]
  };
  NSData *data = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
  if (data != nil) {
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:SALExceptionPath()];
    if (handle == nil) {
      [[NSFileManager defaultManager] createFileAtPath:SALExceptionPath()
                                               contents:nil attributes:nil];
      handle = [NSFileHandle fileHandleForWritingAtPath:SALExceptionPath()];
    }
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [handle synchronizeFile];
    [handle closeFile];
  }
  if (SALPreviousExceptionHandler != nil) SALPreviousExceptionHandler(exception);
}

@implementation SimpleAppLoggerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel = [FlutterMethodChannel
      methodChannelWithName:@"simple_app_logger/native_crashes"
            binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:[[SimpleAppLoggerPlugin alloc] init]
                             channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"acknowledge"]) {
    [@"" writeToFile:SALExceptionPath() atomically:YES
             encoding:NSUTF8StringEncoding error:nil];
    [[NSData data] writeToFile:SALSignalPath() atomically:YES];
    result(nil);
    return;
  }
  if (![call.method isEqualToString:@"configure"]) {
    result(FlutterMethodNotImplemented);
    return;
  }
  NSArray *reports = [self recoverReports];
  BOOL enabled = [call.arguments[@"enabled"] boolValue];
  if (enabled) [self installHandlers]; else [self uninstallHandlers];
  result(reports);
}

- (NSArray *)recoverReports {
  NSMutableArray *reports = [NSMutableArray array];
  NSString *exceptionPath = SALExceptionPath();
  NSString *contents = [NSString stringWithContentsOfFile:exceptionPath
                                                  encoding:NSUTF8StringEncoding error:nil];
  for (NSString *line in [contents componentsSeparatedByString:@"\n"]) {
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length == 0) continue;
    NSDictionary *report = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([report isKindOfClass:[NSDictionary class]]) [reports addObject:report];
  }

  NSData *signals = [NSData dataWithContentsOfFile:SALSignalPath()];
  const int *values = signals.bytes;
  for (NSUInteger index = 0; index < signals.length / sizeof(int); index++) {
    [reports addObject:@{@"tag": @"native_crash",
                         @"message": [NSString stringWithFormat:@"Apple native signal %d", values[index]],
                         @"stack_trace": @""}];
  }
  return reports;
}

- (void)installHandlers {
  if (SALSignalFD >= 0) return;
  SALPreviousExceptionHandler = NSGetUncaughtExceptionHandler();
  NSSetUncaughtExceptionHandler(&SALHandleException);
  SALSignalFD = open(SALSignalPath().fileSystemRepresentation,
                     O_CREAT | O_WRONLY | O_APPEND, 0600);
  struct sigaction action = {0};
  sigemptyset(&action.sa_mask);
  action.sa_sigaction = SALHandleSignal;
  action.sa_flags = SA_SIGINFO | SA_RESETHAND;
  for (NSUInteger index = 0; index < 6; index++) {
    sigaction(SALSignals[index], &action, &SALPreviousActions[index]);
  }
}

- (void)uninstallHandlers {
  if (SALSignalFD < 0) return;
  NSSetUncaughtExceptionHandler(SALPreviousExceptionHandler);
  SALPreviousExceptionHandler = nil;
  for (NSUInteger index = 0; index < 6; index++) {
    sigaction(SALSignals[index], &SALPreviousActions[index], NULL);
  }
  close(SALSignalFD);
  SALSignalFD = -1;
}
@end
