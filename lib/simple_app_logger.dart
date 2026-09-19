import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:simple_app_logger/service/installation_auth.dart';
import 'package:simple_app_logger/service/crash_journal.dart';
import 'package:simple_app_logger/service/native_crash_bridge.dart';
import 'package:simple_app_logger/service/http_util.dart';
import 'package:simple_app_logger/util/date_util.dart';
import 'package:simple_app_logger/util/device_info.dart';
import 'package:simple_app_logger/util/prefs.dart';
import 'package:simple_app_logger/util/uuid_util.dart';

class SimpleAppLogger {
  SimpleAppLogger._();

  static const String _apiBaseUrl =
      'http://127.0.0.1:5001'; //token alk_d78415cc_frnGe72CsJH_Ww5NFwPtQUmoYsWDxCUtPzjfdGwybOE

  static late String apiKey;

  static bool isInit = false;
  static StreamSubscription<List<ConnectivityResult>>?
  _connectivitySubscription;
  static Future<void>? _recovery;
  static bool _deviceInitialized = false;
  static String _appVersion = '';
  static FlutterExceptionHandler? _previousFlutterErrorHandler;
  static bool Function(Object error, StackTrace stack)?
  _previousPlatformErrorHandler;
  static bool _capturesUnhandledErrors = false;
  static CrashJournal? _crashJournal;

  static String _endpoint(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$_apiBaseUrl$normalizedPath';
  }

  static String _getPlatform() {
    if (kIsWeb) return 'Web';

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => 'Fuchsia',
    };
  }

  static Future<void> init({
    required String key,
    int batchSize = 25,
    Duration flushInterval = const Duration(seconds: 5),
    int maxQueuedLogs = 1000,
    String? appVersion,
    bool useInstallationAuth = true,
    bool captureUnhandledError = false,
    bool captureNativeCrashes = false,
    void Function(String message)? apiLog,
  }) async {
    await PrefsUtil.init();
    try {
      _crashJournal = await CrashJournal.create();
    } catch (_) {
      _crashJournal = null;
    }
    apiKey = key;

    final resolvedAppVersion =
        appVersion ?? (await PackageInfo.fromPlatform()).version;
    _appVersion = resolvedAppVersion;
    final platform = _getPlatform().toLowerCase();
    final supportsInstallationAuth =
        useInstallationAuth &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows);
    final authManager = InstallationAuthManager(
      apiKey: apiKey,
      baseUrl: _apiBaseUrl,
      installationId: getInstanceId(),
      platform: platform,
      appVersion: resolvedAppVersion,
      useInstallationAuth: supportsInstallationAuth,
      apiLog: apiLog,
    );
    await authManager.initialize();

    await HttpUtil.init(
      authManager: authManager,
      logBatchSize: batchSize,
      logFlushInterval: flushInterval,
      maxQueuedLogs: maxQueuedLogs,
      logBatchUrl: _endpoint('/api/logs/batch'),
      beforeLogFlush: _ensureDeliveryReady,
      onLogDeviceMissing: () => _deviceInitialized = false,
      apiLog: apiLog,
    );
    await _recoverCrashJournal();
    await _recoverNativeCrashes(captureNativeCrashes);
    isInit = true;
    _deviceInitialized = false;
    _configureUnhandledErrorCapture(captureUnhandledError);

    await _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        unawaited(_recoverAndFlush());
      }
    });
    unawaited(_recoverAndFlush());
  }

  static String getInstanceId() {
    String instanceId =
        PrefsUtil.prefs.getString('simple_logger_instanceId') ??
        UUIDGenerator.instance.generate();

    PrefsUtil.prefs.setString('simple_logger_instanceId', instanceId);

    return instanceId;
  }

  static Future<bool> _ensureDeliveryReady() async {
    if (!isInit) return false;
    try {
      await HttpUtil.ensureAuthenticated();
      if (_deviceInitialized) return true;

      String deviceId = await DeviceHelper.getDeviceId() ?? 'unknown';
      String instanceId = getInstanceId();

      String deviceName = await DeviceHelper.getDeviceName();
      String deviceModel = await DeviceHelper.getDeviceModel();
      String actualDate = DateUtil.getDateNowInUTC();
      String platform = _getPlatform();

      final response = await HttpUtil.post(
        url: _endpoint('/api/devices/init'),
        body: {
          'instance_id': instanceId,
          'actual_log_time': actualDate,
          'name': deviceName,
          'model': deviceModel,
          'platform': platform,
          'device_id': deviceId,
          'app_version': _appVersion,
        },
        queueOnFailure: false,
      );
      _deviceInitialized =
          response != null &&
          response.statusCode >= 200 &&
          response.statusCode < 300;
      return _deviceInitialized;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _recoverAndFlush() {
    final inProgress = _recovery;
    if (inProgress != null) return inProgress;
    final recovery = _performRecovery();
    _recovery = recovery;
    return recovery.whenComplete(() => _recovery = null);
  }

  static Future<void> _performRecovery() async {
    if (!await _ensureDeliveryReady()) return;
    await HttpUtil.retryFailedRequests();
    await HttpUtil.flushLogs();
  }

  static Future<void> _log(
    String level,
    String message, {
    String tag = '',
  }) async {
    if (!isInit) return;

    var url = _endpoint('/api/logs/batch');

    var body = {
      'id': UUIDGenerator.instance.generate(),
      'instance_id': getInstanceId(),
      'actual_log_time': DateUtil.getDateNowInUTC(),
      'message': message,
      'level': level,
      'tag': tag,
    };

    await HttpUtil.enqueueLog(url: url, body: body);
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

  /// Records an error caught by an application-owned error zone.
  static Future<void> recordUnhandledError(
    Object error,
    StackTrace stack, {
    String tag = 'zone_crash',
  }) {
    final record = {
      'id': UUIDGenerator.instance.generate(),
      'actual_log_time': DateUtil.getDateNowInUTC(),
      'message': '$error\n$stack',
      'level': 'error',
      'tag': tag,
    };
    _crashJournal?.writeSync(record);
    return _enqueuePreparedLog(record);
  }

  static Future<void> warning(String message, {String tag = ''}) =>
      _log('warning', message, tag: tag);

  /// Immediately sends any logs waiting in the local batch queue.
  static Future<void> flush() async {
    if (!isInit) return;
    await _recoverAndFlush();
  }

  /// Flushes queued logs and stops the batching timer.
  static Future<void> dispose() async {
    if (!isInit) return;
    _removeUnhandledErrorCapture();
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    await HttpUtil.dispose();
    _crashJournal = null;
    isInit = false;
  }

  static Future<void> _recoverCrashJournal() async {
    final journal = _crashJournal;
    if (journal == null) return;
    final records = await journal.read();
    if (records.isEmpty) return;

    for (final record in records) {
      await _enqueuePreparedLog(record, allowBeforeInitialization: true);
    }
    await journal.clear();
  }

  static Future<void> _recoverNativeCrashes(bool enabled) async {
    final reports = await NativeCrashBridge.configureAndRecover(
      enabled: enabled,
    );
    final journal = _crashJournal;
    if (reports.isEmpty || journal == null) return;
    var persistedAll = true;
    for (var index = 0; index < reports.length; index++) {
      final report = reports[index];
      final message = report['message']?.toString() ?? 'Native process crash';
      final stack = report['stack_trace']?.toString();
      final record = {
        'id': report['id']?.toString() ?? _nativeReportId(report, index),
        'actual_log_time':
            report['actual_log_time']?.toString() ?? DateUtil.getDateNowInUTC(),
        'message': stack == null || stack.isEmpty
            ? message
            : '$message\n$stack',
        'level': 'error',
        'tag': report['tag']?.toString() ?? 'native_crash',
      };
      persistedAll = journal.writeSync(record) && persistedAll;
    }
    if (!persistedAll) return;
    await NativeCrashBridge.acknowledgeRecovered();
    await _recoverCrashJournal();
  }

  static String _nativeReportId(Map<String, dynamic> report, int index) {
    final value =
        '${report['tag']}|${report['message']}|'
        '${report['stack_trace']}|$index';
    var hash = 0xcbf29ce484222325;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return 'native-${hash.toRadixString(16)}';
  }

  static Future<void> _enqueuePreparedLog(
    Map<String, dynamic> record, {
    bool allowBeforeInitialization = false,
  }) async {
    if (!isInit && !allowBeforeInitialization) return;
    final body = Map<String, dynamic>.from(record);
    body['instance_id'] = getInstanceId();
    await HttpUtil.enqueueLog(url: _endpoint('/api/logs/batch'), body: body);
  }

  static void _configureUnhandledErrorCapture(bool enabled) {
    _removeUnhandledErrorCapture();
    if (!enabled) return;

    _capturesUnhandledErrors = true;
    _previousFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(
        recordUnhandledError(
          details.exception,
          details.stack ?? StackTrace.current,
          tag: 'unhandled_error',
        ),
      );
      final previousHandler = _previousFlutterErrorHandler;
      if (previousHandler != null) {
        previousHandler(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final dispatcher = PlatformDispatcher.instance;
    _previousPlatformErrorHandler = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      unawaited(recordUnhandledError(error, stack, tag: 'uncaught_crash'));
      return _previousPlatformErrorHandler?.call(error, stack) ?? false;
    };
  }

  static void _removeUnhandledErrorCapture() {
    if (!_capturesUnhandledErrors) return;
    FlutterError.onError = _previousFlutterErrorHandler;
    PlatformDispatcher.instance.onError = _previousPlatformErrorHandler;
    _previousFlutterErrorHandler = null;
    _previousPlatformErrorHandler = null;
    _capturesUnhandledErrors = false;
  }
}
