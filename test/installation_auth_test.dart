import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simple_app_logger/service/installation_auth.dart';

class MemoryTokenStore implements InstallationTokenStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

InstallationAuthManager createManager({
  required MemoryTokenStore store,
  required http.Client client,
  bool useInstallationAuth = true,
}) => InstallationAuthManager(
  apiKey: 'bootstrap-key',
  baseUrl: 'https://example.test',
  installationId: 'installation-1',
  platform: 'android',
  appVersion: '2.4.1',
  useInstallationAuth: useInstallationAuth,
  tokenStore: store,
  client: client,
);

http.Response tokenResponse(String token, {int expiresIn = 3600}) =>
    http.Response(
      jsonEncode({
        'installation_token': token,
        'token_type': 'Installation',
        'expires_in': expiresIn,
      }),
      201,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('non-mobile mode continues using the bootstrap API key', () async {
    final manager = createManager(
      store: MemoryTokenStore(),
      client: MockClient((_) async => throw StateError('unexpected request')),
      useInstallationAuth: false,
    );

    await manager.initialize();
    final headers = await manager.headers();

    expect(headers['Authorization'], 'ApiKey bootstrap-key');
    expect(headers.containsKey('X-App-Version'), isFalse);
  });

  test('registers and uses an installation token', () async {
    final store = MemoryTokenStore();
    var requests = 0;
    final manager = createManager(
      store: store,
      client: MockClient((request) async {
        requests++;
        expect(request.url.path, '/api/installations/register');
        expect(request.headers['authorization'], 'ApiKey bootstrap-key');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['installation_id'], 'installation-1');
        expect(body['platform'], 'android');
        expect(body['app_version'], '2.4.1');
        expect(body['scopes'], contains('logs:write'));
        return tokenResponse('installation-token');
      }),
    );

    await manager.initialize();
    final headers = await manager.headers();

    expect(requests, 1);
    expect(headers['Authorization'], 'Installation installation-token');
    expect(headers['X-App-Version'], '2.4.1');
    expect(store.values.values, contains('installation-token'));
  });

  test('reuses a cached token while it is valid', () async {
    final store = MemoryTokenStore();
    store.values.addAll({
      'simple_logger_installation_token': 'cached-token',
      'simple_logger_installation_token_expiry': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String(),
      'simple_logger_installation_app_version': '2.4.1',
    });
    final manager = createManager(
      store: store,
      client: MockClient((_) async => throw StateError('unexpected request')),
    );

    await manager.initialize();
    final headers = await manager.headers();

    expect(headers['Authorization'], 'Installation cached-token');
  });

  test('refreshes a token that is close to expiration', () async {
    final store = MemoryTokenStore();
    store.values.addAll({
      'simple_logger_installation_token': 'expiring-token',
      'simple_logger_installation_token_expiry': DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 30))
          .toIso8601String(),
      'simple_logger_installation_app_version': '2.4.1',
    });
    final manager = createManager(
      store: store,
      client: MockClient((request) async {
        expect(request.url.path, '/api/installations/refresh');
        expect(request.headers['authorization'], 'Installation expiring-token');
        expect(request.headers['x-app-version'], '2.4.1');
        return tokenResponse('refreshed-token');
      }),
    );

    await manager.initialize();
    final headers = await manager.headers();

    expect(headers['Authorization'], 'Installation refreshed-token');
  });

  test('an offline registration can recover on the next attempt', () async {
    var attempts = 0;
    final manager = createManager(
      store: MemoryTokenStore(),
      client: MockClient((_) async {
        attempts++;
        if (attempts == 1) throw http.ClientException('offline');
        return tokenResponse('recovered-token');
      }),
    );
    await manager.initialize();

    await expectLater(
      manager.ensureAuthenticated(),
      throwsA(isA<http.ClientException>()),
    );
    expect(manager.state, InstallationAuthState.offline);

    final headers = await manager.headers();
    expect(headers['Authorization'], 'Installation recovered-token');
    expect(manager.state, InstallationAuthState.authenticated);
  });

  test('concurrent callers share one registration request', () async {
    final responseCompleter = Completer<http.Response>();
    var requests = 0;
    final manager = createManager(
      store: MemoryTokenStore(),
      client: MockClient((_) {
        requests++;
        return responseCompleter.future;
      }),
    );
    await manager.initialize();

    final first = manager.ensureAuthenticated();
    final second = manager.ensureAuthenticated();
    responseCompleter.complete(tokenResponse('shared-token'));
    await Future.wait([first, second]);

    expect(requests, 1);
  });

  test('revoked installations do not fall back to API-key ingestion', () async {
    var requests = 0;
    final manager = createManager(
      store: MemoryTokenStore(),
      client: MockClient((_) async {
        requests++;
        return http.Response('{"error":"Installation has been revoked"}', 409);
      }),
    );
    await manager.initialize();

    await expectLater(
      manager.ensureAuthenticated(),
      throwsA(isA<InstallationRevokedException>()),
    );
    await expectLater(
      manager.ensureAuthenticated(),
      throwsA(isA<InstallationRevokedException>()),
    );

    expect(requests, 1);
    expect(manager.state, InstallationAuthState.revoked);
  });
}
