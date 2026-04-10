import 'package:flutter_test/flutter_test.dart';
import 'package:hazor_shield/src/types.dart';

void main() {
  group('Signal', () {
    test('fromJson parses correctly', () {
      final signal = Signal.fromJson({
        'name': 'os_version',
        'value': '17.4',
        'confidence': 0.95,
        'source': 'system',
      });
      expect(signal.name, 'os_version');
      expect(signal.value, '17.4');
      expect(signal.confidence, 0.95);
      expect(signal.source, 'system');
    });

    test('toJson round-trips', () {
      final original = Signal(
        name: 'battery',
        value: 85,
        confidence: 1.0,
        source: 'hardware',
      );
      final json = original.toJson();
      final decoded = Signal.fromJson(json);
      expect(decoded.name, original.name);
      expect(decoded.value, original.value);
      expect(decoded.confidence, original.confidence);
      expect(decoded.source, original.source);
    });

    test('handles null value', () {
      final signal = Signal.fromJson({
        'name': 'test',
        'value': null,
        'confidence': 0.5,
        'source': 'test',
      });
      expect(signal.value, isNull);
    });
  });

  group('ShieldException', () {
    test('toString includes message', () {
      final ex = ShieldException('test error');
      expect(ex.toString(), contains('test error'));
    });

    test('toString includes code when present', () {
      final ex = ShieldException('fail', code: 'E001');
      expect(ex.toString(), contains('E001'));
    });
  });

  group('VerifyResult', () {
    test('holds cd and sessionId', () {
      final result = VerifyResult(cd: 'cd-123', sessionId: 'sess-456');
      expect(result.cd, 'cd-123');
      expect(result.sessionId, 'sess-456');
    });
  });
}
