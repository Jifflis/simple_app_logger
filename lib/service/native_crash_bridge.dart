import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeCrashBridge {
  NativeCrashBridge._();

  static const _channel = MethodChannel('simple_app_logger/native_crashes');

  static Future<List<Map<String, dynamic>>> configureAndRecover({
    required bool enabled,
  }) async {
    if (kIsWeb) return const [];
    try {
      final reports = await _channel.invokeListMethod<dynamic>('configure', {
        'enabled': enabled,
      });
      if (reports == null) return const [];
      return reports
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  static Future<void> acknowledgeRecovered() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('acknowledge');
    } on MissingPluginException {
      // Native crash capture is optional for older host scaffolding.
    } on PlatformException {
      // Retain native reports so recovery can retry next launch.
    }
  }
}
