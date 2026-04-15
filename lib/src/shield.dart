import 'dart:convert';

import 'package:http/http.dart' as http;

import 'attestation.dart';
import 'ct_store.dart';
import 'native_bridge.dart';
import 'pow.dart';
import 'types.dart';

/// Hazor Shield SDK for Flutter.
///
/// ```dart
/// final shield = HazorShield(siteKey: 'hzs_live_abc123');
/// final result = await shield.getCd();
/// final resp = await http.post(
///   Uri.parse('https://api.example.com/login'),
///   headers: {kShieldCdHeader: result.cd},
/// );
/// ```
///
/// `getCd()` reuses a cached Challenge Token (CT, ~1h TTL) when possible
/// and only pays the init+PoW+verify cost when the CT expires. The CD
/// itself is single-use and TTL-bound (30s on mobile) — request a fresh
/// one per backend call.
class HazorShield {
  final String siteKey;
  final String baseUrl;
  final Duration timeout;

  final http.Client _http;
  final CtStore _ctStore;

  /// De-duplicates concurrent `verify()` calls. When two callers hit
  /// `getCd()` at the same time with an expired CT, both see "stale"
  /// and would otherwise both run a full round-trip. The in-flight
  /// future lets the second caller await the first's result.
  Future<VerifyResult>? _pendingVerify;

  HazorShield({
    required this.siteKey,
    this.baseUrl = 'https://protect.hazor.io',
    this.timeout = const Duration(seconds: 10),
    http.Client? httpClient,
    CtStore? ctStore,
  })  : _http = httpClient ?? http.Client(),
        _ctStore = ctStore ?? SecureCtStore() {
    NativeBridge.load();
  }

  String get version => NativeBridge.version();

  List<Signal> collectSignals() => NativeBridge.collectAllSignals();

  /// Obtain a fresh Clearance Decision. Uses the cached CT when valid.
  Future<VerifyResult> getCd() async {
    final now = DateTime.now();
    final cached = await _ctStore.read(siteKey);
    if (cached != null && cached.isValidAt(now)) {
      try {
        return await _refresh(cached);
      } on ShieldException catch (e) {
        // Treat any auth-level rejection as "cache stale" and fall
        // through to a fresh verify. 5xx, 429 and network errors
        // should NOT trigger re-PoW — rethrow them instead.
        if (e.statusCode == 401 ||
            e.statusCode == 403 ||
            e.statusCode == 404) {
          await _ctStore.clear(siteKey);
        } else {
          rethrow;
        }
      }
    }
    return verify();
  }

  /// Force a full verification round-trip. Concurrent callers share the
  /// same in-flight future.
  Future<VerifyResult> verify() {
    return _pendingVerify ??= _runVerify().whenComplete(() {
      _pendingVerify = null;
    });
  }

  Future<VerifyResult> _runVerify() async {
    final signals = collectSignals();

    final initResp = await _post('/api/v1/protect/init', {
      'site_key': siteKey,
    });
    final sessionId = initResp['session_id'] as String? ??
        (throw ShieldException('init: missing session_id'));
    final challenge = initResp['challenge'] as String? ??
        (throw ShieldException('init: missing challenge'));
    final difficulty = (initResp['difficulty'] as num?)?.toInt() ??
        (throw ShieldException('init: missing difficulty'));
    final attestationNonce = initResp['attestation_nonce'] as String?;

    final (nonce, hash) = solveProofOfWork(challenge, difficulty);

    final attestNonceInput = attestationNonce ?? '$sessionId:$nonce';
    final deviceToken = await Attestation.requestToken(attestNonceInput);

    final verifyResp = await _post('/api/v1/protect/verify', {
      'site_key': siteKey,
      'session_id': sessionId,
      'challenge': challenge,
      'nonce': nonce,
      'hash': hash,
      'signals': jsonEncode(signals.map((s) => s.toJson()).toList()),
      'attestation_token': deviceToken,
      if (attestationNonce != null) 'attestation_nonce': attestationNonce,
    });
    final ct = verifyResp['ct'] as String? ??
        (throw ShieldException('verify: missing ct'));
    // `expires_at` is required — without it we'd cache a CT with an
    // epoch-zero expiry and loop through verify() forever.
    final expiresAtSecs = (verifyResp['expires_at'] as num?)?.toInt() ??
        (throw ShieldException('verify: missing expires_at'));
    final ctExpiresAt = DateTime.fromMillisecondsSinceEpoch(
      expiresAtSecs * 1000,
      isUtc: true,
    );

    final cached = CachedCt(
      ct: ct,
      sessionId: sessionId,
      expiresAt: ctExpiresAt,
    );
    await _ctStore.write(siteKey, cached);

    return _refresh(cached);
  }

  Future<void> invalidate() => _ctStore.clear(siteKey);

  void dispose() {
    _http.close();
  }

  // ─── Internal ────────────────────────────────────────────────────

  Future<VerifyResult> _refresh(CachedCt cached) async {
    final refreshResp = await _post('/api/v1/protect/refresh', {
      'ct': cached.ct,
    });
    final cd = refreshResp['cd'] as String? ??
        (throw ShieldException('refresh: missing cd'));
    final ttlSecs = (refreshResp['expires_in_secs'] as num?)?.toInt() ?? 30;
    return VerifyResult(
      cd: cd,
      sessionId: cached.sessionId,
      expiresAt: DateTime.now().add(Duration(seconds: ttlSecs)),
    );
  }

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
              kShieldSiteKeyHeader: siteKey,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (e) {
      throw ShieldException('network error: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? code;
      try {
        final err = jsonDecode(response.body);
        if (err is Map && err['error'] is String) {
          code = err['error'] as String;
        }
      } catch (_) {}
      throw ShieldException(
        'HTTP ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
        code: code,
      );
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw ShieldException('invalid JSON response: $e');
    }
  }
}
