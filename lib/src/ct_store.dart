import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'types.dart';

/// Persisted storage for the Challenge Token.
///
/// The CT is reusable within its ~1h TTL: every request that needs a
/// fresh single-use CD calls `/protect/refresh` with the cached CT, no
/// PoW required. Only when the CT expires does the SDK run the full
/// `init → PoW → verify` round-trip again.
///
/// Abstract so tests can plug in an in-memory implementation.
abstract class CtStore {
  Future<CachedCt?> read(String siteKey);
  Future<void> write(String siteKey, CachedCt value);
  Future<void> clear(String siteKey);
}

/// Default implementation backed by `flutter_secure_storage` (Keychain
/// on iOS, EncryptedSharedPreferences on Android). Safe for release —
/// the CT is a bearer token so losing it to another app on the device
/// would let an attacker request CDs.
class SecureCtStore implements CtStore {
  final FlutterSecureStorage _storage;
  final String _prefix;

  SecureCtStore({
    FlutterSecureStorage? storage,
    String prefix = 'io.hazor.shield.ct',
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            ),
        _prefix = prefix;

  String _key(String siteKey) => '$_prefix.$siteKey';

  @override
  Future<CachedCt?> read(String siteKey) async {
    final raw = await _storage.read(key: _key(siteKey));
    if (raw == null || raw.isEmpty) return null;
    try {
      return CachedCt.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupted entry — drop it silently.
      await _storage.delete(key: _key(siteKey));
      return null;
    }
  }

  @override
  Future<void> write(String siteKey, CachedCt value) =>
      _storage.write(key: _key(siteKey), value: jsonEncode(value.toJson()));

  @override
  Future<void> clear(String siteKey) => _storage.delete(key: _key(siteKey));
}

/// In-memory CT store. Useful for tests and for apps that deliberately
/// want no persistence (e.g. privacy-focused apps re-verifying per
/// launch).
class InMemoryCtStore implements CtStore {
  final Map<String, CachedCt> _cache = {};

  @override
  Future<CachedCt?> read(String siteKey) async => _cache[siteKey];

  @override
  Future<void> write(String siteKey, CachedCt value) async {
    _cache[siteKey] = value;
  }

  @override
  Future<void> clear(String siteKey) async {
    _cache.remove(siteKey);
  }
}
