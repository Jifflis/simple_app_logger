import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_app_logger/service/native_crash_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('simple_app_logger/native_crashes');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('configures native capture and returns pending reports', () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return [
            {'tag': 'native_crash', 'message': 'SIGSEGV', 'stack_trace': ''},
          ];
        });

    final reports = await NativeCrashBridge.configureAndRecover(enabled: true);

    expect(receivedCall?.method, 'configure');
    expect(receivedCall?.arguments, {'enabled': true});
    expect(reports.single['message'], 'SIGSEGV');
  });
}
