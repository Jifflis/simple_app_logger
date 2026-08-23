# Simple App Logger example

This application demonstrates installation authentication, all log levels,
tags, offline queueing, manual flushing, device updates, custom fields, push
tokens, review-status checks, and lifecycle-triggered delivery.

Run it from this directory with a project API key:

```bash
flutter run --dart-define=APP_LOGGER_API_KEY=your-project-api-key
```

The sample uses a batch size of 10, a 10-second flush interval, and a maximum
queue of 1,000 logs. The key must have the scopes documented in the package
README.

On macOS, the example includes Keychain Sharing and outbound-network
entitlements in both debug and release configurations.
