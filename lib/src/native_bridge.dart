import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'types.dart';

// C function typedefs matching shield-mobile-ios-c exports.
typedef _ShieldVersionC = Pointer<Utf8> Function();
typedef _ShieldVersionDart = Pointer<Utf8> Function();

typedef _ShieldCollectAllC = Pointer<Utf8> Function();
typedef _ShieldCollectAllDart = Pointer<Utf8> Function();

typedef _ShieldStringFreeC = Void Function(Pointer<Utf8>);
typedef _ShieldStringFreeDart = void Function(Pointer<Utf8>);

/// FFI bridge to the Rust native binary (libshield_mobile.so on Android,
/// libshield_mobile_ios.a on iOS).
///
/// All functions gracefully return fallback values if the native library
/// is not available (e.g. during development or on unsupported platforms).
class NativeBridge {
  static DynamicLibrary? _lib;
  static bool _loaded = false;
  static bool _available = false;

  static _ShieldVersionDart? _version;
  static _ShieldCollectAllDart? _collectAll;
  static _ShieldStringFreeDart? _stringFree;

  /// Try to load the native library. Call once at app startup.
  /// Returns true if the native binary was found and loaded.
  static bool load() {
    if (_loaded) return _available;
    _loaded = true;

    try {
      if (Platform.isAndroid) {
        _lib = DynamicLibrary.open('libshield_mobile.so');
      } else if (Platform.isIOS) {
        // On iOS the static library is linked into the app binary.
        _lib = DynamicLibrary.process();
      } else {
        // Desktop / web — no native binary.
        return false;
      }

      _version = _lib!
          .lookupFunction<_ShieldVersionC, _ShieldVersionDart>('shield_version');
      _collectAll = _lib!.lookupFunction<_ShieldCollectAllC,
          _ShieldCollectAllDart>('shield_collect_all_signals');
      _stringFree = _lib!.lookupFunction<_ShieldStringFreeC,
          _ShieldStringFreeDart>('shield_string_free');

      _available = true;
    } catch (_) {
      _available = false;
    }
    return _available;
  }

  /// Whether the native binary is loaded and available.
  static bool get isAvailable {
    if (!_loaded) load();
    return _available;
  }

  /// SDK version from the native Rust core, or 'unknown' if not linked.
  static String version() {
    if (!isAvailable) return 'unknown';
    final ptr = _version!();
    if (ptr == nullptr) return 'unknown';
    final result = ptr.toDartString();
    _stringFree!(ptr);
    return result;
  }

  /// Collect all signals from the native core.
  /// Returns an empty list if the native binary is not available.
  static List<Signal> collectAllSignals() {
    if (!isAvailable) return [];
    final ptr = _collectAll!();
    if (ptr == nullptr) return [];
    final json = ptr.toDartString();
    _stringFree!(ptr);

    try {
      final list = jsonDecode(json) as List;
      return list
          .map((e) => Signal.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
