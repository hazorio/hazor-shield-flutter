# Changelog

## 1.0.0

Initial public release.

### feat
- `HazorShield` client with `verify`, `getCd`, `invalidate`
- `ShieldHttpClient` — drop-in `http.Client` wrapper that injects
  `X-Hazor-Shield-CD` and auto-retries on 401
- `ShieldDioInterceptor` — Dio 5-compatible interceptor
- iOS App Attest (iOS 14+) with DeviceCheck fallback
- Android Play Integrity Standard API (warm token) with Classic
  fallback; reads `cloudProjectNumber` from manifest meta-data
- Challenge Token cache backed by `flutter_secure_storage`
- Server-issued signed attestation nonce (Fase 6 contract)
- `InMemoryCtStore` for tests
- Example app under `example/`

### fix
- PoW now hashes `SHA-256(challenge || nonce)` without separator
  (matches server contract; the prior `:` separator caused silent
  `hash_mismatch` rejections when the native core wasn't linked)
- PoW counts leading **hex zeros**, not bits (server counts hex chars)
- Correct CD propagation header constant: `X-Hazor-Shield-CD`
  (docstring previously said `CT`)

### docs
- README with platform setup, troubleshooting, error matrix
- `INTEGRATION_CONTRACT.md` documenting the full server contract
- Dartdoc on the public API surface
