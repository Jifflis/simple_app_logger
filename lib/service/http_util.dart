import 'dart:convert';
import 'dart:math';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../collections/failed_request.dart';

class HttpUtil {
  static Box<FailedRequest>? _box;
  static Future<void>? _initialization;
  static bool _isResending = false;
  static const int _maxBackoffSeconds = 60; // Max exponential backoff

  static String apiKey = '';

  static Map<String, String> getHeaders() => {
    "Content-Type": "application/json",
    'Authorization': apiKey,
  };

  /// Initialize Hive
  static Future<void> init({required String apiKey}) async {
    HttpUtil.apiKey = apiKey;

    if (_box?.isOpen ?? false) return;

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
    final dir = await getApplicationDocumentsDirectory();
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FailedRequestAdapter());
    }
    _box = await Hive.openBox<FailedRequest>('failed_requests');
  }

  /// Send GET request
  ///
  static Future<http.Response?> get({required String url}) async {
    try {
      final response = await http.get(Uri.parse(url), headers: getHeaders());

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
  }) async {
    var finalHeaders = getHeaders();

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: finalHeaders,
        body: jsonEncode(body),
      );
      // 200–299: success, 400–499: client error (do not save)
      if ((response.statusCode >= 200 && response.statusCode < 300) ||
          (response.statusCode >= 400 && response.statusCode < 500)) {
        return response;
      }

      // Other errors: save request
      await _saveFailedRequest(url, finalHeaders, body);
      return null;
    } catch (e) {
      // Network or other exceptions: save request
      await _saveFailedRequest(url, finalHeaders, body);
      return null;
    }
  }

  /// Send PUT request
  static Future<http.Response?> put({
    required String url,
    required Map<String, dynamic> body,
  }) async {
    var finalHeaders = getHeaders();

    try {
      final response = await http.put(
        Uri.parse(url),
        headers: finalHeaders,
        body: jsonEncode(body),
      );

      // 200–299: success, 400–499: client error (do not save)
      if ((response.statusCode >= 200 && response.statusCode < 300) ||
          (response.statusCode >= 400 && response.statusCode < 500)) {
        return response;
      }

      // Other errors: save request
      await _saveFailedRequest(url, finalHeaders, body);
      return null;
    } catch (e) {
      // Network or other exceptions: save request
      await _saveFailedRequest(url, finalHeaders, body);
      return null;
    }
  }

  /// Save failed request to Hive
  static Future<void> _saveFailedRequest(
    String url,
    Map<String, String> headers,
    Map<String, dynamic> body,
  ) async {
    final box = _box;
    if (box == null || !box.isOpen) return;

    final request = FailedRequest(
      url: url,
      headers: headers,
      body: body,
      retryCount: 0,
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
          final response = await http.post(
            Uri.parse(request.url),
            headers: request.headers,
            body: jsonEncode(request.body),
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
          // Exponential backoff with cap
          final delaySeconds = min(
            pow(2, request.retryCount).toInt(),
            _maxBackoffSeconds,
          );
          await Future.delayed(Duration(seconds: delaySeconds));
        }
      }
    } finally {
      _isResending = false;
    }
  }
}
