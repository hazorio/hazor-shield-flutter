# Hazor Shield Flutter SDK

Bot defense for Flutter apps — verify users with proof-of-work, device attestation (Play Integrity / DeviceCheck), and behavioral signals.

## Install

```yaml
dependencies:
  hazor_shield: ^1.0.0
```

## Quick start

```dart
import 'package:hazor_shield/hazor_shield.dart';

final shield = HazorShield(siteKey: 'hzs_live_abc123');

// Before a sensitive action (login, signup, checkout):
try {
  final result = await shield.verify();
  // Send result.cd to your backend
  await api.login(username, password, shieldCd: result.cd);
} on ShieldException catch (e) {
  print('Shield verification failed: $e');
  // Fail closed — reject the action
}
```

## How it works

1. **Signal collection** — The Rust native core (via FFI) collects device signals: OS, hardware, network, jailbreak/root detection
2. **Challenge** — `POST /api/v1/protect/init` gets a PoW challenge from the server
3. **Proof-of-work** — The SDK solves a SHA-256 PoW challenge (native Rust or Dart fallback)
4. **Device attestation** — Requests a Play Integrity (Android) or DeviceCheck (iOS) token
5. **Verification** — Submits signals + PoW + attestation to the server
6. **Clearance decision** — Returns a `cd` token your backend validates via the server-side SDK

## API

### `HazorShield`

```dart
HazorShield({
  required String siteKey,     // From the Hazor dashboard
  String baseUrl,              // Default: https://protect.hazor.io
  Duration timeout,            // Default: 10 seconds
})
```

| Method | Returns | Description |
|--------|---------|-------------|
| `verify()` | `Future<VerifyResult>` | Full verification flow (init → PoW → attest → verify → refresh) |
| `collectSignals()` | `List<Signal>` | Raw device signals (for debugging) |
| `version` | `String` | Native core version |
| `dispose()` | `void` | Release HTTP client resources |

### `VerifyResult`

| Field | Type | Description |
|-------|------|-------------|
| `cd` | `String` | Clearance decision — pass to your backend |
| `sessionId` | `String` | Server session id (for debugging) |

## Platform setup

### Android

Add Play Integrity dependency (already included in the plugin):

```groovy
// No extra setup needed — the plugin handles this.
```

### iOS

DeviceCheck requires iOS 15+ and a real device (not simulator).

## Native binary (optional)

For maximum performance and anti-tampering, include the Rust native library from [hazor-shield-mobile-rs](https://github.com/hazorio/hazor-shield-mobile-rs):

- **Android**: Copy `.so` files to `android/src/main/jniLibs/`
- **iOS**: Link `libshield_mobile_ios.a` in your Xcode project

The SDK works without the native binary — it falls back to Dart implementations for PoW and skips native signal collection.

## License

MIT
