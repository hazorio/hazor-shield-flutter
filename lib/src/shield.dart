import 'dart:convert';

import 'package:http/http.dart' as http;

import 'attestation.dart';
import 'native_bridge.dart';
import 'pow.dart';
import 'types.dart';

/// Hazor Shield SDK for Flutter.
///
/// ```dart
/// final shield = HazorShield(siteKey: 'hzs_live_abc123');
///
/// // In your login / checkout / signup handler:
/// final result = await shield.verify();
/// final cd = result.cd;
/// // Send `cd` to your backend → your backend calls /validate via the
/// // server-side Shield SDK (Python / Go / Node).
/// ```
class HazorShield {
  /// Site key from the Hazor dashboard (starts with `hzs_live_` or `hzs_test_`).
  final String siteKey;

  /// Base URL of the Shield protection endpoint.
  /// Defaults to `https://protect.hazor.io`.
  final String baseUrl;

  /// HTTP request timeout.
  final Duration timeout;

  /// HTTP client (injectable for testing).
  final http.Client _http;

  HazorShield({
    required this.siteKey,
    this.baseUrl = 'https://protect.hazor.io',
    this.timeout = const Duration(seconds: 10),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client() {
    // Eagerly load native library so collectSignals() is fast.
    NativeBridge.load();
  }

  /// SDK version from the native Rust core, or `'unknown'` if the native
  /// binary is not linked (dev builds, unsupported platforms).
  String get version => NativeBridge.version();

  /// Collect all device signals from the native core.
  ///
  /// Returns an empty list if the native binary isn't available. Exposed
  /// for customers who want to inspect what the SDK sends; normally you
  /// just call [verify] which collects + submits in one shot.
  List<Signal> collectSignals() => NativeBridge.collectAllSignals();

  /// Run the full verification flow:
  ///
  /// 1. Collect signals (native Rust core)
  /// 2. `POST /api/v1/protect/init` → session + challenge
  /// 3. Solve proof-of-work (native or Dart fallback)
  /// 4. Request device attestation (Play Integrity / DeviceCheck)
  /// 5. `POST /api/v1/protect/verify` → challenge token
  /// 6. `POST /api/v1/protect/refresh` → clearance decision
  ///
  /// Returns a [VerifyResult] containing the clearance decision (`cd`).
  /// Your backend passes this to the server-side SDK's `/validate`
  /// endpoint to get the final verdict (allow / challenge / deny).
  ///
  /// Throws [ShieldException] on network errors, server errors, or if
  /// the challenge cannot be solved.
  Future<VerifyResult> verify() async {
    final signals = collectSignals();

    // Step 1: init
    final initResp = await _post('/api/v1/protect/init', {
      'site_key': siteKey,
    });
    final sessionId = initResp['session_id'] as String? ??
        (throw ShieldException('init: missing session_id'));
    final challenge = initResp['challenge'] as String? ??
        (throw ShieldException('init: missing challenge'));
    final difficulty = (initResp['difficulty'] as num?)?.toInt() ??
        (throw ShieldException('init: missing difficulty'));

    // Step 2: solve PoW
    final (nonce, hash) = solveProofOfWork(challenge, difficulty);

    // Step 3: device attestation (best-effort)
    final deviceToken =
        await Attestation.requestToken('$sessionId:$nonce');

    // Step 4: verify
    final verifyResp = await _post('/api/v1/protect/verify', {
      'site_key': siteKey,
      'session_id': sessionId,
      'challenge': challenge,
      'nonce': nonce,
      'hash': hash,
      'signals': jsonEncode(signals.map((s) => s.toJson()).toList()),
      'device_token': deviceToken,
    });
    final ct = verifyResp['ct'] as String? ??
        (throw ShieldException('verify: missing ct'));

    // Step 5: refresh
    final refreshResp = await _post('/api/v1/protect/refresh', {
      'ct': ct,
    });
    final cd = refreshResp['cd'] as String? ??
        (throw ShieldException('refresh: missing cd'));

    return VerifyResult(cd: cd, sessionId: sessionId);
  }

  /// POST JSON to the Shield API. Returns the parsed response body.
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final url = Uri.parse('$baseUrl$path');
    final http.Response response;

    try {
      response = await _http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'X-Hazor-Shield-Site-Key': siteKey,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (e) {
      throw ShieldException('network error: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ShieldException(
        'HTTP ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw ShieldException('invalid JSON response: $e');
    }
  }

  /// Release resources. Call when the Shield instance is no longer needed.
  void dispose() {
    _http.close();
  }
}
