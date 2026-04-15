# Hazor Shield — Flutter SDK

Bot defense for Flutter apps. Verifies users with proof-of-work, device
attestation (Play Integrity on Android, App Attest on iOS) and
behavioral signals collected by a Rust native core.

- iOS 14+ App Attest with DeviceCheck fallback
- Android Play Integrity **Standard API** (warm token) with Classic
  fallback
- Persistent Challenge Token cache (~1h, Keychain / EncryptedSharedPreferences)
- Drop-in `http.Client` wrapper and Dio interceptor
- Server-issued signed attestation nonce
- Graceful degradation when the native core isn't linked

## Install

```yaml
dependencies:
  hazor_shield: ^1.0.0
```

## Quick start

```dart
import 'package:hazor_shield/hazor_shield.dart';
import 'package:http/http.dart' as http;

final shield = HazorShield(siteKey: 'hzs_live_...');
final client = ShieldHttpClient(inner: http.Client(), shield: shield);

final resp = await client.post(
  Uri.parse('https://api.example.com/login'),
  body: {'user': 'alice'},
);
```

Manual flow:

```dart
final result = await shield.getCd();
final resp = await http.post(url, headers: {kShieldCdHeader: result.cd});
```

## How it works

1. **`init`** → server returns session id, PoW challenge, and a signed
   attestation nonce.
2. **Proof-of-work** → SDK finds a nonce whose
   `SHA-256(challenge || nonce)` has N leading hex zeros. Rust native
   core if linked; pure Dart fallback otherwise.
3. **Attestation** → Play Integrity (Android) or App Attest (iOS),
   bound to the server nonce.
4. **`verify`** → returns a Challenge Token (CT). Cached ~1h in
   Keychain / EncryptedSharedPreferences.
5. **`refresh`** → exchanges the CT for a single-use, 30-second
   Clearance Decision. Every backend call gets a fresh one.

## Platform setup

### Android

In `android/app/src/main/AndroidManifest.xml`:

```xml
<application>
    <meta-data
        android:name="io.hazor.shield.cloudProjectNumber"
        android:value="YOUR_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER" />
</application>
```

Without it, Play Integrity falls back to Classic API (higher latency
per token, no warm-token optimization).

### iOS

Enable the **App Attest** capability on your target in Xcode. Minimum
deployment target: iOS 15. Real devices only — simulator uses the
DeviceCheck legacy path.

## Native core (optional, recommended)

```bash
git clone https://github.com/hazorio/hazor-shield-mobile-rs
cd hazor-shield-mobile-rs
make flutter-install-android   # populates android/src/main/jniLibs
make flutter-install-ios       # produces ios/Frameworks/ShieldMobile.xcframework
```

Prebuilt artifacts are attached to every tagged release of
`hazor-shield-mobile-rs`.

## API

| Method | Description |
|---|---|
| `HazorShield({required siteKey, baseUrl, timeout, httpClient, ctStore})` | Construct |
| `Future<VerifyResult> getCd()` | Fresh CD, reuses cached CT when possible |
| `Future<VerifyResult> verify()` | Force full round-trip, overwrite cache |
| `Future<void> invalidate()` | Drop cached CT |
| `List<Signal> collectSignals()` | Raw signals from native core |
| `String get version` | Native core version or `'unknown'` |
| `void dispose()` | Release HTTP client |

`VerifyResult` — `cd`, `sessionId`, `expiresAt`.

`ShieldHttpClient({required inner, required shield, skipHosts, skip})` —
injects `X-Hazor-Shield-CD`, retries once on `401 WWW-Authenticate:
Hazor-Shield`, skips `protect.hazor.io` and `/api/v1/protect/*`
automatically.

## Errors

All failures throw `ShieldException` (`message`, optional `code`,
`statusCode`). Common server codes:

| code | meaning |
|---|---|
| `invalid_site_key` | Site not provisioned or disabled |
| `rate_limited` | Too many /init calls from the IP |
| `hash_mismatch` | PoW solution incorrect |
| `difficulty_not_met` | PoW didn't satisfy difficulty |
| `invalid_attestation_nonce` | Tampered/expired server nonce |
| `invalid_ct` | CT signature failed or site secret rotated |

## Troubleshooting

- **`collectSignals()` returns `[]`** — native core isn't linked.
  Install from `hazor-shield-mobile-rs`.
- **Play Integrity errors on emulator** — expected. Server scores
  empty tokens as "no attestation".
- **App Attest fails in simulator** — expected; uses DeviceCheck
  fallback. Real device for full security.
- **401 with `Hazor-Shield` realm** — cached CT was invalidated
  server-side. `ShieldHttpClient` retries automatically; manual users
  call `invalidate()` + `getCd()`.

## License

MIT
