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

/// Result of a successful [HazorShield.verify] call.
class VerifyResult {
  /// Clearance decision token. Pass this to your backend which validates
  /// it via the server-side Shield SDK.
  final String cd;

  /// Session id assigned by the server during init.
  final String sessionId;

  VerifyResult({required this.cd, required this.sessionId});
}

/// Error thrown by Shield operations.
class ShieldException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  ShieldException(this.message, {this.code, this.statusCode});

  @override
  String toString() => 'ShieldException: $message${code != null ? ' ($code)' : ''}';
}
