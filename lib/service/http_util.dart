import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../collections/failed_request.dart';
import 'api_diagnostics.dart';
import 'installation_auth.dart';

class HttpUtil {
  static Box<FailedRequest>? _box;
  static Box<dynamic>? _pendingLogsBox;
  static Future<void>? _initialization;
  static bool _isResending = false;
  static Future<void>? _logFlush;
  static Timer? _logFlushTimer;
  static String? _logBatchUrl;
  static int _logBatchSize = 25;
  static int _maxQueuedLogs = 1000;
  static Duration _logFlushInterval = const Duration(seconds: 5);
  static int _logFlushFailureCount = 0;
  static bool _logSchedulingEnabled = true;
  static InstallationAuthManager? _authManager;
  static Future<bool> Function()? _beforeLogFlush;
  static void Function()? _onLogDeviceMissing;
  static void Function(String message)? _apiLog;
  static const int _maxBackoffSeconds = 60; // Max exponential backoff
  static const int _maxSupportedLogBatchSize = 50;
  static const Duration _requestTimeout = Duration(seconds: 15);

  static Future<Map<String, String>> getHeaders() async {
    final authManager = _authManager;
    if (authManager == null) {
      throw StateError('HttpUtil has not been initialized.');
    }
    return authManager.headers();
  }

  static Future<void> ensureAuthenticated() async {
    final authManager = _authManager;
    if (authManager == null) {
      throw StateError('HttpUtil has not been initialized.');
    }
    await authManager.ensureAuthenticated();
  }

  /// Initialize Hive
  static Future<void> init({
    required InstallationAuthManager authManager,
    int logBatchSize = 25,
    Duration logFlushInterval = const Duration(seconds: 5),
    int maxQueuedLogs = 1000,
    String? logBatchUrl,
    Future<bool> Function()? beforeLogFlush,
    void Function()? onLogDeviceMissing,
    void Function(String message)? apiLog,
  }) async {
    if (logBatchSize <= 0) {
      throw ArgumentError.value(
        logBatchSize,
        'logBatchSize',
        'must be positive',
      );
    }
    if (logBatchSize > _maxSupportedLogBatchSize) {
      throw ArgumentError.value(
        logBatchSize,
        'logBatchSize',
        'must not exceed $_maxSupportedLogBatchSize',
      );
    }
    if (logFlushInterval <= Duration.zero) {
      throw ArgumentError.value(
        logFlushInterval,
        'logFlushInterval',
        'must be positive',
      );
    }
    if (maxQueuedLogs < logBatchSize) {
      throw ArgumentError.value(
        maxQueuedLogs,
        'maxQueuedLogs',
        'must be at least logBatchSize',
      );
    }

    _authManager = authManager;
    _beforeLogFlush = beforeLogFlush;
    _onLogDeviceMissing = onLogDeviceMissing;
    _apiLog = apiLog;
    _logBatchSize = logBatchSize;
    _logFlushInterval = logFlushInterval;
    _maxQueuedLogs = maxQueuedLogs;
    _logBatchUrl = logBatchUrl ?? _logBatchUrl;
    _logSchedulingEnabled = true;

    if ((_box?.isOpen ?? false) && (_pendingLogsBox?.isOpen ?? false)) {
      _scheduleLogFlush();
      return;
    }

    final initializationInProgress = _initialization;
    if (initializationInProgress != null) {
      await initializationInProgress;
      return;
    }

    final initialization = _initializeHive();
    _initialization = initialization;
    try {
      await initialization;
    } finally {
      _initialization = null;
    }
  }

  static Future<void> _initializeHive() async {
    if (kIsWeb) {
      // Hive uses IndexedDB when no filesystem path is supplied in a browser.
      Hive.init(null);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      Hive.init(dir.path);
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FailedRequestAdapter());
    }
    _box = await Hive.openBox<FailedRequest>('failed_requests');
    _pendingLogsBox = await Hive.openBox<dynamic>('pending_logs');
    _scheduleLogFlush();
  }

  /// Persist a log and schedule it for batched delivery.
  static Future<void> enqueueLog({
    required String url,
    required Map<String, dynamic> body,
  }) async {
    final box = _pendingLogsBox;
    if (box == null || !box.isOpen) return;

    _logBatchUrl = url;
    while (box.length >= _maxQueuedLogs && box.isNotEmpty) {
      await box.delete(box.keys.first);
    }
    await box.add(Map<String, dynamic>.from(body));

    if (box.length >= _logBatchSize) {
      unawaited(flushLogs());
    } else {
      _scheduleLogFlush();
    }
  }

  static void _scheduleLogFlush([Duration? delay]) {
    final box = _pendingLogsBox;
    if (!_logSchedulingEnabled ||
        box == null ||
        !box.isOpen ||
        box.isEmpty ||
        _logFlushTimer != null) {
      return;
    }

    _logFlushTimer = Timer(delay ?? _logFlushInterval, () {
      _logFlushTimer = null;
      unawaited(flushLogs());
    });
  }

  /// Immediately send all queued logs, one batch at a time.
  static Future<void> flushLogs() {
    final inProgress = _logFlush;
    if (inProgress != null) return inProgress;

    final flush = _flushLogs();
    _logFlush = flush;
    return flush.whenComplete(() {
      _logFlush = null;
    });
  }

  static Future<void> _flushLogs() async {
    _logFlushTimer?.cancel();
    _logFlushTimer = null;

    final box = _pendingLogsBox;
    final url = _logBatchUrl;
    if (box == null || !box.isOpen || box.isEmpty || url == null) return;

    final beforeFlush = _beforeLogFlush;
    if (beforeFlush != null) {
      try {
        if (!await beforeFlush()) {
          _scheduleLogRetry();
          return;
        }
      } catch (_) {
        _scheduleLogRetry();
        return;
      }
    }

    while (box.isNotEmpty) {
      final keys = box.keys.take(_logBatchSize).toList(growable: false);
      final logs = <Map<String, dynamic>>[];
      for (final key in keys) {
        final value = box.get(key);
        if (value is Map) {
          logs.add(Map<String, dynamic>.from(value));
        }
      }

      if (logs.isEmpty) {
        await box.deleteAll(keys);
        continue;
      }

      try {
        final response = await _sendRequest(
          method: 'POST',
          url: url,
          body: {'logs': logs},
        );
        if (response.statusCode == 404) {
          _onLogDeviceMissing?.call();
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          _scheduleLogRetry();
          return;
        }
      } catch (_) {
        _scheduleLogRetry();
        return;
      }

      _logFlushFailureCount = 0;
      await box.deleteAll(keys);
    }
  }

  static void _scheduleLogRetry() {
    _logFlushFailureCount += 1;
    final exponent = min(_logFlushFailureCount - 1, 6);
    final seconds = min(
      _logFlushInterval.inSeconds * pow(2, exponent).toInt(),
      _maxBackoffSeconds,
    );
    _scheduleLogFlush(Duration(seconds: max(1, seconds)));
  }

  static Future<void> dispose() async {
    _logSchedulingEnabled = false;
    _logFlushTimer?.cancel();
    _logFlushTimer = null;
    await flushLogs();
    _authManager?.dispose();
  }

  static Future<http.Response> _sendRequest({
    required String method,
    required String url,
    Map<String, dynamic>? body,
  }) async {
    final authManager = _authManager;
    if (authManager == null) {
      throw StateError('HttpUtil has not been initialized.');
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      final headers = await authManager.headers();
      final uri = Uri.parse(url);
      final encodedBody = body == null ? null : jsonEncode(body);
      _emitApiLog(
        formatApiRequest(
          method: method,
          url: url,
          headers: headers,
          payload: body,
        ),
      );
      late final http.Response response;
      try {
        response = switch (method) {
          'GET' =>
            await http.get(uri, headers: headers).timeout(_requestTimeout),
          'PUT' =>
            await http
                .put(uri, headers: headers, body: encodedBody)
                .timeout(_requestTimeout),
          _ =>
            await http
                .post(uri, headers: headers, body: encodedBody)
                .timeout(_requestTimeout),
        };
        _emitApiLog(
          formatApiResponse(
            method: method,
            url: url,
            statusCode: response.statusCode,
            body: response.body,
          ),
        );
      } catch (error) {
        _emitApiLog('[API] $method $url -> failed: $error');
        rethrow;
      }
      if (response.statusCode != 401 ||
          !authManager.usesInstallationToken ||
          attempt > 0) {
        return response;
      }
      await authManager.recoverFromUnauthorized();
    }
    throw StateError('Authentication retry did not produce a response.');
  }

  /// Send GET request
  ///
  static Future<http.Response?> get({required String url}) async {
    try {
      final response = await _sendRequest(method: 'GET', url: url);

      // 200–299: success, 400–499: client error (do not save)
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Send POST request
  static Future<http.Response?> post({
    required String url,
    required Map<String, dynamic> body,
    bool queueOnFailure = true,
  }) async {
    try {
      final response = await _sendRequest(method: 'POST', url: url, body: body);
      // 200–299: success, 400–499: client error (do not save)
      if ((response.statusCode >= 200 && response.statusCode < 300) ||
          (response.statusCode >= 400 && response.statusCode < 500)) {
        return response;
      }

      // Other errors: save request
      if (queueOnFailure) {
        await _saveFailedRequest(url, body, method: 'POST');
      }
      return null;
    } catch (e) {
      // Network or other exceptions: save request
      if (queueOnFailure) {
        await _saveFailedRequest(url, body, method: 'POST');
      }
      return null;
    }
  }

  /// Send PUT request
  static Future<http.Response?> put({
    required String url,
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _sendRequest(method: 'PUT', url: url, body: body);

      // 200–299: success, 400–499: client error (do not save)
      if ((response.statusCode >= 200 && response.statusCode < 300) ||
          (response.statusCode >= 400 && response.statusCode < 500)) {
        return response;
      }

      // Other errors: save request
      await _saveFailedRequest(url, body, method: 'PUT');
      return null;
    } catch (e) {
      // Network or other exceptions: save request
      await _saveFailedRequest(url, body, method: 'PUT');
      return null;
    }
  }

  /// Save failed request to Hive
  static Future<void> _saveFailedRequest(
    String url,
    Map<String, dynamic> body, {
    required String method,
  }) async {
    final box = _box;
    if (box == null || !box.isOpen) return;

    final request = FailedRequest(
      url: url,
      headers: const {},
      body: body,
      retryCount: 0,
      method: method,
    );
    await box.add(request);
  }

  /// Retry all failed requests with exponential backoff
  static Future<void> retryFailedRequests() async {
    final box = _box;
    if (box == null || !box.isOpen) return;
    if (_isResending) return;

    _isResending = true;
    try {
      for (var key in box.keys.toList()) {
        final request = box.get(key);
        if (request == null) continue;

        try {
          final response = await _sendRequest(
            method: request.method,
            url: request.url,
            body: request.body,
          );

          if (response.statusCode >= 200 && response.statusCode < 300) {
            await request.delete(); // Remove if successful
          } else {
            request.retryCount += 1;
            await request.save();
          }
        } catch (e) {
          request.retryCount += 1;
          await request.save();
        } finally {
          final delaySeconds = min(
            pow(2, request.retryCount).toInt(),
            _maxBackoffSeconds,
          );
          if (request.retryCount > 0) {
            await Future.delayed(Duration(seconds: delaySeconds));
          }
        }
      }
    } finally {
      _isResending = false;
    }
  }

  static void _emitApiLog(String message) {
    try {
      _apiLog?.call(message);
    } catch (_) {
      // Diagnostics must never affect request delivery.
    }
  }
}
