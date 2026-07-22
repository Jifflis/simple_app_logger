import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:simple_app_logger/service/http_util.dart';
import 'package:simple_app_logger/util/date_util.dart';
import 'package:simple_app_logger/util/device_info.dart';
import 'package:simple_app_logger/util/prefs.dart';
import 'package:simple_app_logger/util/uuid_util.dart';

class SimpleAppLogger {
  SimpleAppLogger._();

  static const String _apiBaseUrl = 'https://api.id-makers.com';

  static late String apiKey;

  static bool isInit = false;

  static String _endpoint(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$_apiBaseUrl$normalizedPath';
  }

  static String _getPlatform() {
    return Platform.isAndroid
        ? 'Android'
        : Platform.isIOS
        ? 'iOS'
        : Platform.isMacOS
        ? 'macOS'
        : Platform.isWindows
        ? 'Windows'
        : Platform.isLinux
        ? 'Linux'
        : 'Unknown';
  }

  static Future<void> init({required String key}) async {
    apiKey = key;

    isInit = true;
    await HttpUtil.init(apiKey: apiKey);

    _postInitialVariables();
  }

  static String getInstanceId() {
    String instanceId =
        PrefsUtil.prefs.getString('simple_logger_instanceId') ??
        UUIDGenerator.instance.generate();

    PrefsUtil.prefs.setString('simple_logger_instanceId', instanceId);

    return instanceId;
  }

  static Future<void> _postInitialVariables() async {
    String deviceId = await DeviceHelper.getDeviceId() ?? 'unknown';
    String instanceId = getInstanceId();

    String deviceName = await DeviceHelper.getDeviceName();
    String deviceModel = await DeviceHelper.getDeviceModel();
    String actualDate = DateUtil.getDateNowInUTC();
    String platform = _getPlatform();

    await HttpUtil.post(
      url: _endpoint('/api/devices/init'),
      body: {
        'instance_id': instanceId,
        'actual_log_time': actualDate,
        'name': deviceName,
        'model': deviceModel,
        'platform': platform,
        'device_id': deviceId,
      },
    );

    // Listen to connectivity changes
    Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        HttpUtil.retryFailedRequests();
      }
    });
  }

  static Future<void> _log(
    String level,
    String message, {
    String tag = '',
  }) async {
    if (!isInit) return;

    var url = _endpoint('/api/logs');

    var body = {
      'instance_id': getInstanceId(),
      'actual_log_time': DateUtil.getDateNowInUTC(),
      'message': message,
      'level': level,
      'tag': tag,
    };

    await HttpUtil.post(url: url, body: body);
  }

  static Future<void> updateDevice(Map<String, dynamic> body) async {
    if (!isInit) return;

    await HttpUtil.put(
      url: _endpoint('/api/devices/${getInstanceId()}'),
      body: body,
    );
  }

  static Future<void> upsertPushToken({required String token}) async {
    if (!isInit) return;

    await HttpUtil.post(
      url: _endpoint('/api/pushTokens'),
      body: {
        'instance_id': getInstanceId(),
        'token': token,
        'platform': _getPlatform(),
      },
    );
  }

  static Future<void> setCustomField({
    required String fieldName,
    required String value,
    String type = 'text',
  }) async {
    if (!isInit) return;

    await HttpUtil.post(
      url: _endpoint('/api/custom-field'),
      body: {
        'instance_id': getInstanceId(),
        'name': fieldName,
        'value': value,
        'field_type': type,
      },
    );
  }

  static Future<bool> shouldReview() async {
    if (!isInit) return false;

    try {
      var result = await HttpUtil.get(
        url: _endpoint('/api/instances/${getInstanceId()}'),
      );

      if (result == null) {
        return false;
      }

      var body = jsonDecode(result.body);

      return body['message'] == 'Record found';
    } catch (_) {
      return false;
    }
  }

  static Future<void> info(String message, {String tag = ''}) =>
      _log('info', message, tag: tag);

  static Future<void> error(String message, {String tag = ''}) =>
      _log('error', message, tag: tag);

  static Future<void> warning(String message, {String tag = ''}) =>
      _log('warning', message, tag: tag);
}
