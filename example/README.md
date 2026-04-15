# hazor_shield_example

Minimal Flutter app exercising the Hazor Shield SDK.

## Run

```bash
flutter run \
  --dart-define=SITE_KEY=hzs_live_your_key \
  --dart-define=BACKEND_URL=https://api.your-app.com
```

Without `SITE_KEY` the app shows a placeholder screen.

## Buttons

- **Full verify** — forces `shield.verify()` (init + PoW + attestation
  + verify + refresh).
- **getCd** — reuses the cached CT when valid; only re-verifies when
  the CT is near expiry. Observe that successive taps return quickly.
- **GET /me via ShieldHttpClient** — calls your backend with
  `X-Hazor-Shield-CD` injected automatically. Handles 401 retry if the
  server emits `WWW-Authenticate: Hazor-Shield`.
- **Invalidate cache** — drops the stored CT. Next getCd re-runs the
  full flow.

## Platform setup

### Android

In `android/app/src/main/AndroidManifest.xml`, declare the Google Cloud
project number associated with your Play Integrity config:

```xml
<meta-data
    android:name="io.hazor.shield.cloudProjectNumber"
    android:value="123456789012" />
```

Without it the SDK falls back to Classic Play Integrity (slower but
functional).

### iOS

Enable the **App Attest** capability on your app target in Xcode.
Runtime requirements: iOS 14+ real device. Simulator falls back to
DeviceCheck (legacy).

## Native core

If you want the full signal collector (jailbreak/root detection,
hardware signals), install the Rust native core:

```bash
cd ../../hazor-shield-mobile-rs
make flutter-install-android    # populates android/src/main/jniLibs
make flutter-install-ios        # produces ios/Frameworks/ShieldMobile.xcframework
```

The SDK works without it — `collectSignals()` just returns `[]` and
the PoW runs in pure Dart.
