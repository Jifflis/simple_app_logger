import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_app_logger/util/device_info.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    DeviceHelper.setDeviceInfoPlugin(DeviceInfoPlugin());
  });

  test('reports the Android model and OS version', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    DeviceHelper.setDeviceInfoPlugin(
      DeviceInfoPlugin.setMockInitialValues(
        androidDeviceInfo: AndroidDeviceInfo.fromMap({
          'id': 'build-id',
          'host': 'host',
          'tags': 'release-keys',
          'type': 'user',
          'model': 'Pixel 9 Pro',
          'board': 'board',
          'brand': 'Google',
          'device': 'device',
          'product': 'product',
          'name': 'My Pixel',
          'display': 'display',
          'hardware': 'hardware',
          'isPhysicalDevice': true,
          'freeDiskSize': 1024,
          'totalDiskSize': 2048,
          'bootloader': 'bootloader',
          'fingerprint': 'fingerprint',
          'manufacturer': 'Google',
          'supportedAbis': <String>['arm64-v8a'],
          'systemFeatures': <String>[],
          'version': <String, dynamic>{
            'sdkInt': 35,
            'baseOS': '',
            'previewSdkInt': 0,
            'release': '15',
            'codename': 'REL',
            'incremental': '1',
            'securityPatch': '2026-10-01',
          },
          'supported64BitAbis': <String>['arm64-v8a'],
          'supported32BitAbis': <String>[],
          'serialNumber': 'unknown',
          'isLowRamDevice': false,
          'physicalRamSize': 8192,
          'availableRamSize': 4096,
        }),
      ),
    );

    expect(await DeviceHelper.getDeviceModel(), 'Pixel 9 Pro');
    expect(await DeviceHelper.getDeviceVersion(), 'Android 15');
  });

  test('reports the iOS hardware identifier and OS version', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    DeviceHelper.setDeviceInfoPlugin(
      DeviceInfoPlugin.setMockInitialValues(
        iosDeviceInfo: IosDeviceInfo.fromMap({
          'name': 'Ada’s iPhone',
          'model': 'iPhone',
          'modelName': 'iPhone 15',
          'utsname': <String, dynamic>{
            'release': 'release',
            'version': 'version',
            'machine': 'iPhone15,4',
            'sysname': 'Darwin',
            'nodename': 'iphone',
          },
          'systemName': 'iOS',
          'isPhysicalDevice': true,
          'isiOSAppOnMac': false,
          'physicalRamSize': 8192,
          'availableRamSize': 4096,
          'systemVersion': '18.0',
          'localizedModel': 'iPhone',
          'identifierForVendor': 'device-id',
          'freeDiskSize': 4096,
          'totalDiskSize': 8192,
        }),
      ),
    );

    expect(await DeviceHelper.getDeviceModel(), 'iPhone15,4');
    expect(await DeviceHelper.getDeviceVersion(), 'iOS 18.0');
  });
}
