/// Header name the customer's backend reads to extract the Clearance
/// Decision. Must match the server-side middleware in
/// `hazor-shield-sdk-{python,node,go}`.
const String kShieldCdHeader = 'X-Hazor-Shield-CD';

/// Header the `/protect/*` endpoints expect when the site_key is sent
/// out-of-band (all mobile flows include it).
const String kShieldSiteKeyHeader = 'X-Hazor-Shield-Site-Key';

/// Signal collected by the native Rust core.
class Signal {
  final String name;
  final dynamic value;
  final double confidence;
  final String source;

  Signal({
    required this.name,
    required this.value,
    required this.confidence,
    required this.source,
  });

  factory Signal.fromJson(Map<String, dynamic> json) => Signal(
        name: json['name'] as String,
        value: json['value'],
        confidence: (json['confidence'] as num).toDouble(),
        source: json['source'] as String,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'confidence': confidence,
        'source': source,
      };
}

/// Result of a successful verification. The `cd` is single-use and
/// TTL-bound (30s on mobile sites). Send it to your backend in the
/// [kShieldCdHeader] header — do not re-use.
class VerifyResult {
  /// Clearance decision token. Your backend forwards this to
  /// `POST /api/v1/protect/validate` via the server-side SDK.
  final String cd;

  /// Session id assigned by the server during init.
  final String sessionId;

  /// When the cd expires (approximate, computed locally from
  /// `expires_in_secs` returned by /refresh).
  final DateTime expiresAt;

  VerifyResult({
    required this.cd,
    required this.sessionId,
    required this.expiresAt,
  });
}

/// Persisted Challenge Token. Reusable within its TTL (~1h) — the SDK
/// caches it and only re-runs init+PoW+verify when it expires. Each
/// call to `/refresh` with a valid CT yields a fresh single-use CD.
class CachedCt {
  final String ct;
  final String sessionId;
  final DateTime expiresAt;

  CachedCt({
    required this.ct,
    required this.sessionId,
    required this.expiresAt,
  });

  /// Bumped when the on-disk schema changes. Older entries fail to
  /// parse and get dropped by SecureCtStore.
  static const int _schemaVersion = 1;

  factory CachedCt.fromJson(Map<String, dynamic> json) {
    final v = json['v'] as int?;
    if (v != _schemaVersion) {
      throw FormatException('CachedCt schema version mismatch: got $v');
    }
    return CachedCt(
      ct: json['ct'] as String,
      sessionId: json['session_id'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        json['expires_at'] as int,
        isUtc: true,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'v': _schemaVersion,
        'ct': ct,
        'session_id': sessionId,
        'expires_at': expiresAt.millisecondsSinceEpoch,
      };

  bool isValidAt(DateTime now, {Duration margin = const Duration(seconds: 60)}) =>
      expiresAt.subtract(margin).isAfter(now);
}

/// Error thrown by Shield operations.
class ShieldException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  ShieldException(this.message, {this.code, this.statusCode});

  @override
  String toString() =>
      'ShieldException: $message${code != null ? ' ($code)' : ''}';
}
