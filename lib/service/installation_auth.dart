import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

enum InstallationAuthState {
  uninitialized,
  authenticating,
  authenticated,
  offline,
  revoked,
}

class InstallationRevokedException implements Exception {
  const InstallationRevokedException();

  @override
  String toString() => 'The logger installation has been revoked.';
}

abstract interface class InstallationTokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureInstallationTokenStore implements InstallationTokenStore {
  SecureInstallationTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class InstallationAuthManager {
  InstallationAuthManager({
    required this.apiKey,
    required this.baseUrl,
    required this.installationId,
    required this.platform,
    required this.appVersion,
    required this.useInstallationAuth,
    InstallationTokenStore? tokenStore,
    http.Client? client,
  }) : _storage = tokenStore ?? SecureInstallationTokenStore(),
       _client = client ?? http.Client();

  static const _tokenKey = 'simple_logger_installation_token';
  static const _expiryKey = 'simple_logger_installation_token_expiry';
  static const _versionKey = 'simple_logger_installation_app_version';
  static const _refreshSkew = Duration(minutes: 1);
  static const _requestTimeout = Duration(seconds: 15);
  static const _scopes = <String>[
    'custom_fields:write',
    'devices:write',
    'instances:write',
    'logs:write',
    'push_tokens:write',
  ];

  final String apiKey;
  final String baseUrl;
  final String installationId;
  final String platform;
  final String appVersion;
  final bool useInstallationAuth;
  final InstallationTokenStore _storage;
  final http.Client _client;

  String? _token;
  DateTime? _expiresAt;
  Future<void>? _authentication;
  InstallationAuthState state = InstallationAuthState.uninitialized;

  bool get usesInstallationToken => useInstallationAuth;

  Future<void> initialize() async {
    if (!useInstallationAuth) {
      state = InstallationAuthState.authenticated;
      return;
    }

    List<String?> values;
    try {
      values = await Future.wait([
        _storage.read(_tokenKey),
        _storage.read(_expiryKey),
        _storage.read(_versionKey),
      ]);
    } catch (_) {
      state = InstallationAuthState.uninitialized;
      return;
    }
    if (values[2] == appVersion) {
      _token = values[0];
      _expiresAt = DateTime.tryParse(values[1] ?? '')?.toUtc();
    } else {
      await _clearToken();
    }
    state = _hasUsableToken
        ? InstallationAuthState.authenticated
        : InstallationAuthState.uninitialized;
  }

  bool get _hasUsableToken {
    final expiresAt = _expiresAt;
    return _token != null &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now().toUtc().add(_refreshSkew));
  }

  bool get _hasUnexpiredToken {
    final expiresAt = _expiresAt;
    return _token != null &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now().toUtc());
  }

  Future<Map<String, String>> headers() async {
    if (!useInstallationAuth) {
      return _apiKeyHeaders;
    }
    await ensureAuthenticated();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Installation $_token',
      'X-App-Version': appVersion,
    };
  }

  Map<String, String> get _apiKeyHeaders => {
    'Content-Type': 'application/json',
    'Authorization': 'ApiKey $apiKey',
  };

  Future<void> ensureAuthenticated() {
    if (!useInstallationAuth || _hasUsableToken) {
      state = InstallationAuthState.authenticated;
      return Future.value();
    }
    if (state == InstallationAuthState.revoked) {
      return Future.error(const InstallationRevokedException());
    }
    final inProgress = _authentication;
    if (inProgress != null) return inProgress;

    final authentication = _authenticate();
    _authentication = authentication;
    return authentication.whenComplete(() => _authentication = null);
  }

  Future<void> _authenticate() async {
    state = InstallationAuthState.authenticating;
    try {
      if (_hasUnexpiredToken && await _refresh()) return;
      await _register();
    } on InstallationRevokedException {
      state = InstallationAuthState.revoked;
      rethrow;
    } catch (_) {
      state = InstallationAuthState.offline;
      rethrow;
    }
  }

  Future<bool> _refresh() async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/installations/refresh'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Installation $_token',
              'X-App-Version': appVersion,
            },
          )
          .timeout(_requestTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _saveTokenResponse(response);
        return true;
      }
      if (response.statusCode == 401) await _clearToken();
      return false;
    } catch (_) {
      if (_hasUnexpiredToken) {
        state = InstallationAuthState.authenticated;
        return true;
      }
      rethrow;
    }
  }

  Future<void> _register() async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/installations/register'),
          headers: _apiKeyHeaders,
          body: jsonEncode({
            'installation_id': installationId,
            'platform': platform,
            'app_version': appVersion,
            'scopes': _scopes,
          }),
        )
        .timeout(_requestTimeout);
    if (response.statusCode == 409) {
      await _clearToken();
      throw const InstallationRevokedException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Installation registration failed (${response.statusCode}).',
      );
    }
    await _saveTokenResponse(response);
  }

  Future<void> _saveTokenResponse(http.Response response) async {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['installation_token'];
    final expiresIn = data['expires_in'];
    if (token is! String || token.isEmpty || expiresIn is! num) {
      throw const FormatException('Invalid installation token response.');
    }
    _token = token;
    _expiresAt = DateTime.now().toUtc().add(
      Duration(seconds: expiresIn.toInt()),
    );
    try {
      await Future.wait([
        _storage.write(_tokenKey, _token!),
        _storage.write(_expiryKey, _expiresAt!.toIso8601String()),
        _storage.write(_versionKey, appVersion),
      ]);
    } catch (_) {
      // The in-memory token remains usable for this process.
    }
    state = InstallationAuthState.authenticated;
  }

  Future<void> recoverFromUnauthorized() async {
    if (!useInstallationAuth) return;
    await _clearToken();
    state = InstallationAuthState.uninitialized;
    await ensureAuthenticated();
  }

  Future<void> _clearToken() async {
    _token = null;
    _expiresAt = null;
    try {
      await Future.wait([
        _storage.delete(_tokenKey),
        _storage.delete(_expiryKey),
        _storage.delete(_versionKey),
      ]);
    } catch (_) {
      // Clearing in-memory state is sufficient to prevent token reuse now.
    }
  }

  void dispose() => _client.close();
}
