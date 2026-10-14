import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceHelper {
  static DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  @visibleForTesting
  static void setDeviceInfoPlugin(DeviceInfoPlugin deviceInfo) {
    _deviceInfo = deviceInfo;
  }

  /// Returns a unique device ID depending on the platform.
  static Future<String?> getDeviceId() async {
    try {
      if (kIsWeb) {
        // Browsers intentionally do not expose a stable device identifier.
        // The logger's persisted instance ID identifies this installation.
        return null;
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.identifierForVendor;
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        return macInfo.systemGUID;
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        final winInfo = await _deviceInfo.windowsInfo;
        return winInfo.deviceId;
      } else if (defaultTargetPlatform == TargetPlatform.linux) {
        final linuxInfo = await _deviceInfo.linuxInfo;
        return linuxInfo.machineId;
      } else {
        return 'unknown-platform';
      }
    } catch (e) {
      debugPrint('Error getting device ID: $e');
      return null;
    }
  }

  static Future<String> getDeviceName() async {
    if (kIsWeb) {
      final info = await _deviceInfo.webBrowserInfo;
      return info.browserName.name;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final info = await _deviceInfo.androidInfo;
      return '${info.manufacturer} ${info.name}';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final info = await _deviceInfo.iosInfo;
      return info.name;
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      final info = await _deviceInfo.macOsInfo;
      return info.computerName;
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      final info = await _deviceInfo.windowsInfo;
      return info.computerName;
    } else {
      return 'Unknown Device';
    }
  }

  static Future<String> getDeviceModel() async {
    if (kIsWeb) {
      final info = await _deviceInfo.webBrowserInfo;
      return info.platform ?? info.userAgent ?? 'Unknown Browser';
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final info = await _deviceInfo.androidInfo;
      return info.model;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final info = await _deviceInfo.iosInfo;
      return info.utsname.machine;
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      final info = await _deviceInfo.macOsInfo;
      return info.model;
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      final info = await _deviceInfo.windowsInfo;
      return info.computerName;
    } else if (defaultTargetPlatform == TargetPlatform.linux) {
      final info = await _deviceInfo.linuxInfo;
      return info.prettyName;
    } else {
      return 'Unknown Device';
    }
  }

  /// Returns a user-facing operating system or browser version.
  static Future<String?> getDeviceVersion() async {
    try {
      if (kIsWeb) {
        final info = await _deviceInfo.webBrowserInfo;
        return _nonEmpty(info.appVersion) ?? _nonEmpty(info.userAgent);
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        final info = await _deviceInfo.androidInfo;
        return _withPlatform('Android', info.version.release);
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final info = await _deviceInfo.iosInfo;
        return _withPlatform('iOS', info.systemVersion);
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        final info = await _deviceInfo.macOsInfo;
        return 'macOS ${info.majorVersion}.${info.minorVersion}.${info.patchVersion}';
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        final info = await _deviceInfo.windowsInfo;
        final productName = _nonEmpty(info.productName);
        final displayVersion = _nonEmpty(info.displayVersion);
        if (productName != null && displayVersion != null) {
          return '$productName $displayVersion';
        }
        return productName ??
            displayVersion ??
            'Windows ${info.majorVersion}.${info.minorVersion}.${info.buildNumber}';
      } else if (defaultTargetPlatform == TargetPlatform.linux) {
        final info = await _deviceInfo.linuxInfo;
        return _nonEmpty(info.prettyName) ??
            _withPlatform(info.name, info.versionId ?? info.version);
      }

      return null;
    } catch (error) {
      debugPrint('Error getting device version: $error');
      return null;
    }
  }

  static String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String? _withPlatform(String platform, String? version) {
    final normalizedPlatform = _nonEmpty(platform);
    final normalizedVersion = _nonEmpty(version);
    if (normalizedPlatform == null) return normalizedVersion;
    if (normalizedVersion == null) return normalizedPlatform;
    return '$normalizedPlatform $normalizedVersion';
  }
}
