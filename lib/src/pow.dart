import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Pure-Dart proof-of-work solver.
///
/// Finds a nonce such that SHA-256(challenge + ":" + nonce) has at least
/// [difficulty] leading zero bits. Returns (nonce, hexHash).
///
/// This is the fallback when the Rust native core isn't linked. The Rust
/// version is ~10x faster, but for typical difficulty values (16–20 bits)
/// the Dart solver completes in <1s on modern phones.
(int, String) solveProofOfWork(String challenge, int difficulty) {
  final prefix = utf8.encode('$challenge:');

  for (var nonce = 0; nonce < 0x7FFFFFFFFFFFFFFF; nonce++) {
    final nonceBytes = utf8.encode(nonce.toString());
    final input = Uint8List(prefix.length + nonceBytes.length)
      ..setAll(0, prefix)
      ..setAll(prefix.length, nonceBytes);

    final hash = sha256.convert(input);
    if (_hasLeadingZeroBits(hash.bytes, difficulty)) {
      return (nonce, hash.toString());
    }
  }
  throw StateError('PoW: search space exhausted');
}

bool _hasLeadingZeroBits(List<int> hash, int required) {
  var remaining = required;
  for (final byte in hash) {
    if (remaining <= 0) return true;
    // Count leading zeros in this byte (0–8).
    var b = byte;
    var zeros = 0;
    for (var bit = 7; bit >= 0; bit--) {
      if ((b >> bit) & 1 == 0) {
        zeros++;
      } else {
        break;
      }
    }
    if (zeros < remaining.clamp(0, 8)) return false;
    remaining -= 8;
  }
  return remaining <= 0;
}
