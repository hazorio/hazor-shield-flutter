import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hazor_shield/src/pow.dart';
import 'dart:convert';

void main() {
  group('solveProofOfWork', () {
    test('difficulty 1 produces hash with >=1 leading hex zero', () {
      final (nonce, hash) = solveProofOfWork('test-challenge', 1);
      expect(nonce, greaterThanOrEqualTo(0));
      expect(hash.length, 64);
      expect(hash[0], '0');
    });

    test('difficulty 4 produces hash with 4 leading hex zeros', () {
      final (_, hash) = solveProofOfWork('challenge-4', 4);
      expect(hash.substring(0, 4), '0000');
    });

    test('hash matches server formula SHA256(challenge||nonce)', () {
      // Server verifies: hash_client == hex(sha256(challenge ++ nonce_str))
      // with NO separator between challenge and nonce.
      const challenge = 'contract-check';
      final (nonce, hash) = solveProofOfWork(challenge, 2);
      final recomputed =
          sha256.convert(utf8.encode('$challenge$nonce')).toString();
      expect(hash, recomputed);
    });

    test('difficulty 0 returns nonce 0 and any hash', () {
      final (nonce, hash) = solveProofOfWork('anything', 0);
      expect(nonce, 0);
      expect(hash.length, 64);
    });
  });
}
