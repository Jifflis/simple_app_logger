# Simple App Logger

`simple_app_logger` sends application logs and device metadata to the App
Logger API. It supports durable offline logging, configurable batching,
automatic retries, and short-lived installation authentication.

## Features

- Information, warning, and error logs with optional tags.
- Durable log queue backed by Hive.
- Size-based and time-based batch delivery.
- Automatic retry after network and server failures.
- Automatic recovery when connectivity returns.
- Short-lived installation tokens on Android, iOS, macOS, and Windows.
- Secure installation-token storage.
- Device registration, metadata updates, push tokens, and custom fields.
- Android, iOS, macOS, Windows, Linux, and web support.

## Installation

Add the package to your Flutter project:

```bash
flutter pub add simple_app_logger
```

Then import it:

```dart
import 'package:simple_app_logger/simple_app_logger.dart';
```

## Backend requirements

This package sends data to the App Logger API at
`https://api.id-makers.com`. Before initializing the package, create a project
API key in the App Logger dashboard.

For access to every SDK feature, the bootstrap API key needs these scopes:

- `installations:issue`
- `devices:write`
- `instances:write`
- `logs:write`
- `custom_fields:write`
- `push_tokens:write`

Use the smallest scope set that covers the methods your application calls.
Basic device initialization and logging require `installations:issue`,
`devices:write`, and `logs:write` on platforms using installation
authentication.

> An API key bundled with a distributed application can be extracted. Use a
> restricted bootstrap key, configure backend rate limits, and revoke a key if
> it is exposed. Supported platforms use short-lived installation tokens after
> bootstrap.

## Basic setup

Initialize Flutter bindings and the logger before using it:

```dart
import 'package:flutter/widgets.dart';
import 'package:simple_app_logger/simple_app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SimpleAppLogger.init(
    key: 'your-project-api-key',
  );

  await SimpleAppLogger.info('Application started');
  runApp(const MyApp());
}
```

Initialization prepares local storage first. Authentication and delivery
continue in the background, so an offline application can begin capturing logs
immediately. Calls made before `SimpleAppLogger.init()` completes are safely
ignored.

## Example application

A complete cross-platform sample is available in the [`example`](example/)
directory. Run it with:

```bash
cd example
flutter run --dart-define=APP_LOGGER_API_KEY=your-project-api-key
```

The sample provides controls for every public SDK operation and can be used to
observe batching and offline recovery interactively.

## Configuration

```dart
await SimpleAppLogger.init(
  key: 'your-project-api-key',
  batchSize: 25,
  flushInterval: const Duration(seconds: 5),
  maxQueuedLogs: 1000,
  appVersion: '2.4.1',
  useInstallationAuth: true,
  captureUnhandledError: true,
  captureNativeCrashes: true,
);
```

| Option | Default | Description |
| --- | --- | --- |
| `key` | Required | Project API key used for bootstrap or direct authentication. |
| `batchSize` | `25` | Logs per request. Must be between 1 and 50. |
| `flushInterval` | 5 seconds | Maximum delay before a non-empty log queue is flushed. |
| `maxQueuedLogs` | `1000` | Maximum locally queued logs. Must be at least `batchSize`. |
| `appVersion` | Detected automatically | Version used for installation registration and `X-App-Version`. |
| `useInstallationAuth` | `true` | Enables installation tokens on supported platforms. |
| `captureUnhandledError` | `false` | Captures unhandled Flutter and root-isolate errors. |
| `captureNativeCrashes` | `false` | Installs native exception and fatal-signal handlers on supported native platforms. |

Set `appVersion` explicitly when tests, custom build systems, or the backend
version allowlist require a specific value. Valid backend versions contain
letters, numbers, `.`, `_`, `+`, or `-` and are at most 50 characters.

## Logging

```dart
await SimpleAppLogger.info('Checkout screen opened');

await SimpleAppLogger.warning(
  'Checkout response was slow',
  tag: 'checkout',
);

await SimpleAppLogger.error(
  'Payment request failed',
  tag: 'payments',
);
```

Every log contains a unique event ID, the persistent application instance ID,
the UTC event time, message, level, and optional tag.

Awaiting a logging method confirms that the entry has been handled by the local
logger. It does not mean the backend has already received it. Use `flush()`
when delivery must be attempted immediately.

### Unhandled errors

Enable automatic capture for Flutter framework errors and uncaught root-isolate
errors:

```dart
await SimpleAppLogger.init(
  key: 'your-project-api-key',
  captureUnhandledError: true,
);
```

Automatically captured events use the normalized tags `unhandled_error` and
`uncaught_crash`. Error zones must wrap `main()`, so forward zone errors to the
logger explicitly with the `zone_crash` tag:

```dart
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await SimpleAppLogger.init(
      key: 'your-project-api-key',
      captureUnhandledError: true,
    );
    runApp(const MyApp());
  }, (error, stack) {
    SimpleAppLogger.recordUnhandledError(error, stack);
  });
}
```

The SDK forwards errors to handlers that were installed before initialization.
Before normal asynchronous queuing, it also writes a minimal record to a
bounded synchronous emergency journal on filesystem platforms. On the next
launch, journal records are moved into the persistent batch queue with their
original event IDs and uploaded after authentication. Partial records from an
interrupted write are ignored safely.

This journal improves delivery for abrupt Dart and Flutter failures. Native
capture can be enabled separately:

```dart
await SimpleAppLogger.init(
  key: 'your-project-api-key',
  captureUnhandledError: true,
  captureNativeCrashes: true,
);
```

Native reports are written by platform handlers, recovered on the next launch,
and uploaded with the `native_crash` tag through the normal authenticated batch
pipeline. Android captures JVM exceptions and common NDK fatal signals. Apple
platforms capture uncaught Objective-C exceptions and common fatal signals.
Linux captures common fatal signals, and Windows captures unhandled structured
exceptions. Previous handlers are restored or forwarded where the platform
allows it.

No in-process SDK can reliably report out-of-memory kills, power loss, or an OS
force-kill. The native handlers intentionally collect minimal metadata; native
symbolication and minidump attachment upload require a separate backend symbol
and artifact pipeline.

## Batching and offline behavior

Logs are written to a persistent Hive queue and sent to
`POST /api/logs/batch` when:

- The queue reaches `batchSize`.
- `flushInterval` elapses.
- Connectivity returns.
- `SimpleAppLogger.flush()` is called.

Delivery follows this order:

1. Obtain or refresh an installation credential.
2. Initialize or verify the device record.
3. Retry queued non-log requests.
4. Send queued logs in batches.
5. Delete only batches acknowledged with a successful response.

Network exceptions, timeouts, and unsuccessful batch responses leave logs in
the queue. Retries use capped exponential backoff.

If `maxQueuedLogs` is reached, the oldest logs are permanently removed before
newer logs are added. This keeps storage bounded and favors recent events.
Increase the limit if the application may remain offline for long periods.

The batch endpoint receives:

```json
{
  "logs": [
    {
      "id": "unique-event-id",
      "instance_id": "installation-instance-id",
      "actual_log_time": "2026-08-23T01:02:03.000Z",
      "message": "Application started",
      "level": "info",
      "tag": "lifecycle"
    }
  ]
}
```

The backend treats `id` as a project-scoped idempotency key, so retrying an
acknowledged event does not create a duplicate log.

## Authentication

### Installation authentication

Android, iOS, macOS, and Windows use installation authentication by default:

1. The API key registers the installation through
   `POST /api/installations/register`.
2. The backend returns a short-lived installation token.
3. The token is stored using platform secure storage.
4. Ingestion uses `Authorization: Installation <token>` and `X-App-Version`.
5. The package refreshes the token before expiration.

Only one registration or refresh runs at a time, even when several events
trigger delivery concurrently. If authentication fails while offline, queued
logs stay on the device and authentication is attempted later. A revoked
installation does not fall back to the API key because that would bypass
revocation.

### Direct API-key authentication

Linux and web currently use `Authorization: ApiKey <project-api-key>`.
Installation authentication can be disabled explicitly on any platform:

```dart
await SimpleAppLogger.init(
  key: 'your-project-api-key',
  useInstallationAuth: false,
);
```

## Platform setup

### Android

Secure token storage requires Android API level 18 or later. Avoid restoring
secure-storage shared preferences from Android backup because restored values
may not match the device KeyStore key. Follow the `flutter_secure_storage`
Android backup guidance in the host application.

### iOS

Installation tokens use the iOS Keychain. No additional package-specific setup
is required.

### macOS

No Keychain Sharing entitlement is required with the default configuration.
Installation credentials are stored in the app's private Keychain. Only enable
Keychain Sharing when your application explicitly configures a shared Keychain
access group; doing so requires signing with an Apple development or
distribution certificate.

If Keychain persistence is unavailable at runtime, the current process can use
an in-memory token, but it may register again after restart.

### Windows

No additional configuration is required for the secure-storage `read`,
`write`, and `delete` operations used by this package.

### Linux

Linux currently uses direct API-key authentication. Hive uses the application
documents directory for durable queues.

### Web

Web currently uses direct API-key authentication and stores queues in IndexedDB.
Browser credentials are accessible to the user and can be exposed by
cross-site scripting, so use a tightly scoped key and strict backend limits.

## Device and application metadata

The package automatically registers the persistent `instance_id`, reported
device identifier when available, device name and model, platform, application
version, and UTC initialization time.

Retrieve the current instance ID with:

```dart
final instanceId = SimpleAppLogger.getInstanceId();
```

## Update device metadata

```dart
await SimpleAppLogger.updateDevice({
  'name': 'Jeffrey’s MacBook',
  'language': 'en',
  'app_version': '2.4.1',
});
```

Supported backend fields include `device_id`, `name`, `model`, `platform`,
`language`, and `app_version`.

## Push tokens

```dart
await SimpleAppLogger.upsertPushToken(
  token: 'push-provider-token',
);
```

Call this again whenever the push provider rotates the token.

## Custom fields

```dart
await SimpleAppLogger.setCustomField(
  fieldName: 'subscription_plan',
  value: 'premium',
);

await SimpleAppLogger.setCustomField(
  fieldName: 'account_age',
  value: '120',
  type: 'number',
);
```

Supported types depend on the backend. Current values include `text`,
`number`, `date`, `email`, and `boolean`.

## Review status

```dart
final shouldPromptForReview = await SimpleAppLogger.shouldReview();

if (shouldPromptForReview) {
  // Show the application's review prompt.
}
```

This returns `false` when the logger is not initialized, the backend has no
matching record, authentication fails, or the request cannot complete.

## Flush and lifecycle handling

Call `flush()` when entering a lifecycle state where the application may soon
stop receiving execution time:

```dart
class LoggerLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      SimpleAppLogger.flush();
    }
  }
}
```

`flush()` attempts authentication, device initialization, failed-request
delivery, and log delivery. If the device is offline, data remains persisted.

Call `dispose()` only when the logger will no longer be used in the process:

```dart
await SimpleAppLogger.dispose();
```

Disposal cancels connectivity monitoring, attempts a final flush, stops batch
timers, and closes the authentication HTTP client. Calls after disposal are
ignored until the package is initialized again.

## Failure behavior

| Condition | Behavior |
| --- | --- |
| Application starts offline | Local logging works; authentication and delivery wait. |
| Installation token is near expiration | The token is refreshed before sending. |
| Installation request returns `401` | Authentication is renewed and the request is retried once. |
| Installation is revoked | Delivery stops without API-key fallback; logs remain local. |
| Device is missing on the backend | Device initialization runs before the next log flush. |
| Network timeout or server error | Data stays queued and retries with backoff. |
| Queue reaches `maxQueuedLogs` | Oldest logs are discarded as new logs arrive. |
| Invalid logger configuration | `init()` throws an `ArgumentError`. |

## Recommended production configuration

```dart
await SimpleAppLogger.init(
  key: const String.fromEnvironment('APP_LOGGER_API_KEY'),
  batchSize: 25,
  flushInterval: const Duration(seconds: 5),
  maxQueuedLogs: 5000,
  useInstallationAuth: true,
);
```

Configure the backend to restrict bootstrap-key scopes, enforce rate limits,
optionally allowlist application versions, monitor rejected ingestion, and
revoke compromised keys or installations promptly.

## Troubleshooting

### Logs remain queued

Confirm that:

- The API key is active and has the required scopes.
- The backend supports the current platform and application version.
- Device initialization succeeds.
- `POST /api/logs/batch` is deployed and its migration is applied.
- The application can reach `https://api.id-makers.com`.

### Installation registration returns `403`

The bootstrap key is missing `installations:issue` or one of the requested
ingestion scopes.

### Installation registration returns `409`

The installation was revoked. Restore or replace it through backend
administration; the SDK intentionally does not bypass revocation.

### macOS repeatedly registers after restart

Verify that Keychain access is available to the application and that the app's
bundle identifier has not changed. If the application explicitly uses a shared
Keychain access group, verify its signing certificate and Keychain Sharing
entitlement, then rebuild the host application.

### Batches are rejected

Keep `batchSize` at or below 50 and verify that the backend expects the
`{"logs": [...]}` request shape documented above.
