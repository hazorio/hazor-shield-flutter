import 'dart:io';

import 'package:flutter/services.dart';

/// Platform-specific device attestation.
///
/// On Android: calls Google Play Integrity API via a method channel.
/// On iOS: calls Apple DeviceCheck API via a method channel.
///
/// The actual platform code lives in:
///   - android/src/main/kotlin/.../HazorShieldPlugin.kt
///   - ios/Classes/HazorShieldPlugin.swift
///
/// Falls back to an empty string if the attestation API is unavailable
/// (e.g. emulator, sideloaded app, old OS version). The server will
/// score this as "no attestation" rather than hard-blocking.
class Attestation {
  static const _channel = MethodChannel('io.hazor.shield/attestation');

  /// Request a device attestation token bound to [nonce].
  ///
  /// Returns the attestation token string, or empty string on failure.
  static Future<String> requestToken(String nonce) async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod<String>(
          'requestPlayIntegrity',
          {'nonce': nonce},
        );
        return result ?? '';
      } else if (Platform.isIOS) {
        final result = await _channel.invokeMethod<String>(
          'requestDeviceCheck',
          {'nonce': nonce},
        );
        return result ?? '';
      }
    } on PlatformException {
      // Attestation unavailable — degrade gracefully.
    } on MissingPluginException {
      // Plugin not registered (happens in unit tests).
    }
    return '';
  }
}
