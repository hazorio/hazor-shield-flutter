# Changelog

## [1.0.0] - 2026-04-10

### Added
- Initial release
- Full verify() flow: init → PoW → attestation → verify → refresh → cd
- Native FFI bridge to Rust core (dart:ffi)
- Pure-Dart PoW fallback
- Platform channels for Play Integrity (Android) and DeviceCheck (iOS)
- Unit tests for PoW solver and types
- CI workflow (flutter analyze + flutter test)
- MIT LICENSE
