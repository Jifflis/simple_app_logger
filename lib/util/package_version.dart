import 'package:package_info_plus/package_info_plus.dart';

String formatPackageVersion(PackageInfo packageInfo) {
  final version = packageInfo.version.trim();
  final buildNumber = packageInfo.buildNumber.trim();

  if (buildNumber.isEmpty || version.endsWith('+$buildNumber')) return version;
  if (version.isEmpty) return buildNumber;
  return '$version+$buildNumber';
}
