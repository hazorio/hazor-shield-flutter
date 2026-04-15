import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Platform-specific device attestation.
///
/// - Android: Google Play Integrity (Classic API for now; Standard API
///   in Fase 5).
/// - iOS 14+: Apple App Attest (`DCAppAttestService`).
/// - iOS <14 or unsupported device: DeviceCheck fallback (legacy).
///
/// The return value is a base64-encoded JSON string with a platform-
/// specific payload. The server treats the whole thing as an opaque
/// `device_token` field in /verify — the verifier on the server side
/// decodes by platform based on header metadata or heuristics.
///
/// Returns an empty string if attestation is unavailable (simulator,
/// emulator, sideloaded, old OS). The server scores this as
/// "no attestation" instead of hard-blocking.
class Attestation {
  static const _channel = MethodChannel('io.hazor.shield/attestation');

  /// Request a device attestation token bound to [nonce].
  ///
  /// On iOS, [nonce] becomes the App Attest `clientDataHash` (after
  /// SHA-256). On Android, it's passed as the Play Integrity nonce.
  static Future<String> requestToken(String nonce) async {
    try {
      if (Platform.isAndroid) {
        return await _requestAndroid(nonce);
      } else if (Platform.isIOS) {
        return await _requestIos(nonce);
      }
    } on PlatformException {
      // Attestation unavailable — degrade gracefully.
    } on MissingPluginException {
      // Plugin not registered (happens in unit tests and unsupported
      // embedding modes).
    }
    return '';
  }

  /// Whether App Attest is supported on this device. Always false on
  /// Android and on iOS versions below 14.
  static Future<bool> isAppAttestSupported() async {
    if (!Platform.isIOS) return false;
    try {
      final supported =
          await _channel.invokeMethod<bool>('isAppAttestSupported');
      return supported ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<String> _requestAndroid(String nonce) async {
    final token = await _channel
            .invokeMethod<String>('requestPlayIntegrity', {'nonce': nonce}) ??
        '';
    if (token.isEmpty) return '';
    return _wrap('android_play_integrity', {'token': token});
  }

  static Future<String> _requestIos(String nonce) async {
    // Prefer App Attest; fall back to DeviceCheck on unsupported
    // devices (older hardware, simulator).
    if (await isAppAttestSupported()) {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'requestAppAttest',
        {'nonce': nonce},
      );
      if (result == null) return '';
      return _wrap('ios_app_attest', {
        'keyId': result['keyId'],
        'attestation': result['attestation'],
        'assertion': result['assertion'],
      });
    }
    final token =
        await _channel.invokeMethod<String>('requestDeviceCheck') ?? '';
    if (token.isEmpty) return '';
    return _wrap('ios_device_check', {'token': token});
  }

  /// Envelope format: base64(JSON({platform, payload})). The server-side
  /// attestation verifier picks the right verifier by inspecting
  /// `platform`.
  static String _wrap(String platform, Map<String, dynamic> payload) {
    final json = jsonEncode({'platform': platform, 'payload': payload});
    return base64Encode(utf8.encode(json));
  }
}
