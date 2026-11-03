import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:simple_app_logger/util/package_version.dart';

void main() {
  PackageInfo packageInfo({required String version, required String build}) =>
      PackageInfo(
        appName: 'Test app',
        packageName: 'com.example.test',
        version: version,
        buildNumber: build,
      );

  test('combines the package version and build number', () {
    expect(
      formatPackageVersion(packageInfo(version: '2.4.1', build: '38')),
      '2.4.1+38',
    );
  });

  test('keeps the package version when the build number is unavailable', () {
    expect(
      formatPackageVersion(packageInfo(version: '2.4.1', build: '')),
      '2.4.1',
    );
  });

  test('does not append a build number already present in the version', () {
    expect(
      formatPackageVersion(packageInfo(version: '2.4.1+38', build: '38')),
      '2.4.1+38',
    );
  });
}
