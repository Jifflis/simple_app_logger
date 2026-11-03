# Collision-safe device identity

## Goal

Report a device identity that can safely group multiple installations of the
same device without merging unrelated devices.

## Behavior

- `instance_id` remains the canonical identifier for an app installation.
- Android uses `Settings.Secure.ANDROID_ID`, exposed by the `android_id`
  package. Android `Build.ID` is not a device identifier and must not be sent.
- A reported `device_id` includes a `device_id_kind` describing its source.
  Android reports `android_id`; other native platforms report their existing
  platform-specific kind.
- Web and platforms where a device identifier is unavailable send `null` for
  both fields. The SDK never substitutes shared values such as `unknown` or
  `unknown-platform`.
- Device metadata and the installation UUID continue to be sent with every
  device initialization.

## Edge and failure cases

- Empty or unavailable Android IDs produce `null` and remain separated by
  `instance_id` on the server.
- A device-information exception does not prevent logging; initialization
  proceeds without a reported device identity.
- Platform identifiers can reset according to platform policy. Such a reset
  creates a new grouping identity but does not change historical log ownership.

## Acceptance criteria

- Two Android devices sharing a firmware build are not grouped because of
  `Build.ID`.
- A missing identifier never becomes a shared placeholder.
- Android initialization sends `device_id_kind: android_id` only when an ID is
  present.
- Device identity and metadata unit tests pass.
