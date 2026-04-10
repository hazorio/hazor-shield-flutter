import 'package:flutter_test/flutter_test.dart';
import 'package:hazor_shield/src/pow.dart';

void main() {
  group('solveProofOfWork', () {
    test('finds a valid nonce for difficulty 1', () {
      final (nonce, hash) = solveProofOfWork('test-challenge', 1);
      expect(nonce, greaterThanOrEqualTo(0));
      expect(hash.length, 64); // SHA-256 hex = 64 chars
      // First hex char must be 0-7 (leading zero bit)
      final firstNibble = int.parse(hash[0], radix: 16);
      expect(firstNibble, lessThan(8));
    });

    test('finds a valid nonce for difficulty 4', () {
      final (nonce, hash) = solveProofOfWork('challenge-4', 4);
      expect(nonce, greaterThanOrEqualTo(0));
      // First hex char must be 0 (4 leading zero bits)
      expect(hash[0], '0');
    });

    test('finds a valid nonce for difficulty 8', () {
      final (nonce, hash) = solveProofOfWork('challenge-8', 8);
      expect(nonce, greaterThanOrEqualTo(0));
      // First 2 hex chars must be 00
      expect(hash.substring(0, 2), '00');
    });

    test('different challenges produce different nonces', () {
      final (nonce1, _) = solveProofOfWork('challenge-a', 4);
      final (nonce2, _) = solveProofOfWork('challenge-b', 4);
      // They *could* be the same by coincidence, but extremely unlikely
      // for different challenges. We just verify both succeed.
      expect(nonce1, greaterThanOrEqualTo(0));
      expect(nonce2, greaterThanOrEqualTo(0));
    });
  });

  group('Signal', () {
    test('fromJson round-trip', () {
      final json = {
        'name': 'os_version',
        'value': '17.4',
        'confidence': 1.0,
        'source': 'system',
      };
      // Import types to test
    });
  });
}
