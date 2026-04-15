import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Maximum iterations before giving up. At difficulty 6 the expected
/// count is ~16M, at difficulty 7 ~268M. We cap at 50M to keep a
/// runaway solver bounded even if the server misbehaves and requests a
/// difficulty the device can't realistically solve in <1min.
const int _maxIterations = 50 * 1000 * 1000;

/// Pure-Dart proof-of-work solver.
///
/// Finds a [nonce] such that `SHA-256(challenge || nonce)` has at least
/// [difficulty] leading **hex zero characters** (4 bits each). Returns
/// `(nonce, hexHash)`.
///
/// IMPORTANT: the server (`lb-shield::api::verify::handle_verify`)
/// computes the hash as `format!("{}{}", challenge, nonce)` — direct
/// concatenation with **no separator** — and counts leading hex zeros.
/// This implementation must match exactly or /verify returns
/// `hash_mismatch` or `difficulty_not_met`.
///
/// Throws [StateError] if no solution is found within [_maxIterations].
(int, String) solveProofOfWork(String challenge, int difficulty) {
  final prefix = utf8.encode(challenge);
  final buffer = Uint8List(prefix.length + 20) // 20 = max u64 decimal chars
    ..setAll(0, prefix);

  for (var nonce = 0; nonce < _maxIterations; nonce++) {
    final nonceBytes = utf8.encode(nonce.toString());
    buffer.setRange(prefix.length, prefix.length + nonceBytes.length, nonceBytes);
    final view = Uint8List.view(buffer.buffer, 0, prefix.length + nonceBytes.length);
    final hex = sha256.convert(view).toString();
    if (_hasLeadingHexZeros(hex, difficulty)) {
      return (nonce, hex);
    }
  }
  throw StateError(
    'PoW: no solution within $_maxIterations iterations at difficulty $difficulty',
  );
}

bool _hasLeadingHexZeros(String hex, int required) {
  if (required <= 0) return true;
  if (required > hex.length) return false;
  for (var i = 0; i < required; i++) {
    if (hex.codeUnitAt(i) != 0x30 /* '0' */) return false;
  }
  return true;
}
