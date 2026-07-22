import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';

class DeviceHelper {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Returns a unique device ID depending on the platform.
  static Future<String?> getDeviceId() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.id; // Or: androidInfo.androidId (deprecated on some devices)
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.identifierForVendor;
      } else if (Platform.isMacOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        return macInfo.systemGUID; // unique to each Mac system
      } else if (Platform.isWindows) {
        final winInfo = await _deviceInfo.windowsInfo;
        return winInfo.deviceId; // stable Windows device identifier
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfo.linuxInfo;
        return linuxInfo.machineId; // may be null if restricted
      } else {
        return 'unknown-platform';
      }
    } catch (e) {
      debugPrint('Error getting device ID: $e');
      return null;
    }
  }

  static Future<String> getDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      return "${info.manufacturer} ${info.name}";
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      return info.name;
    } else if (Platform.isMacOS) {
      final info = await deviceInfo.macOsInfo;
      return info.computerName;
    } else if (Platform.isWindows) {
      final info = await deviceInfo.windowsInfo;
      return info.computerName ;
    } else {
      return "Unknown Device";
    }
  }

  static Future<String> getDeviceModel() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      return info.model ;
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      return info.utsname.machine;
    } else if (Platform.isMacOS) {
      final info = await deviceInfo.macOsInfo;
      return info.model;
    } else if (Platform.isWindows) {
      final info = await deviceInfo.windowsInfo;
      return info.computerName;
    } else if (Platform.isLinux) {
      final info = await deviceInfo.linuxInfo;
      return info.prettyName;
    } else {
      return "Unknown Device";
    }
  }
}