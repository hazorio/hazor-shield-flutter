import 'package:flutter_test/flutter_test.dart';
import 'package:hazor_shield/hazor_shield.dart';

void main() {
  group('InMemoryCtStore', () {
    test('read returns null on empty store', () async {
      final store = InMemoryCtStore();
      expect(await store.read('hzs_live_x'), isNull);
    });

    test('write then read round-trips', () async {
      final store = InMemoryCtStore();
      final ct = CachedCt(
        ct: 'abc.def',
        sessionId: 'sess-1',
        expiresAt: DateTime.utc(2030, 1, 1),
      );
      await store.write('hzs_live_x', ct);
      final got = await store.read('hzs_live_x');
      expect(got, isNotNull);
      expect(got!.ct, 'abc.def');
      expect(got.sessionId, 'sess-1');
      expect(got.expiresAt, DateTime.utc(2030, 1, 1));
    });

    test('clear removes entry', () async {
      final store = InMemoryCtStore();
      await store.write(
        'hzs_live_x',
        CachedCt(
          ct: 'x',
          sessionId: 's',
          expiresAt: DateTime.utc(2030),
        ),
      );
      await store.clear('hzs_live_x');
      expect(await store.read('hzs_live_x'), isNull);
    });

    test('entries are isolated per site key', () async {
      final store = InMemoryCtStore();
      await store.write(
        'hzs_live_a',
        CachedCt(ct: 'a', sessionId: 's', expiresAt: DateTime.utc(2030)),
      );
      await store.write(
        'hzs_live_b',
        CachedCt(ct: 'b', sessionId: 's', expiresAt: DateTime.utc(2030)),
      );
      expect((await store.read('hzs_live_a'))!.ct, 'a');
      expect((await store.read('hzs_live_b'))!.ct, 'b');
    });
  });

  group('CachedCt.isValidAt', () {
    test('expired entry is invalid', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final ct = CachedCt(
        ct: 'x',
        sessionId: 's',
        expiresAt: now.subtract(const Duration(seconds: 1)),
      );
      expect(ct.isValidAt(now), isFalse);
    });

    test('default 60s safety margin rejects entries near expiry', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final ct = CachedCt(
        ct: 'x',
        sessionId: 's',
        expiresAt: now.add(const Duration(seconds: 30)),
      );
      expect(ct.isValidAt(now), isFalse);
    });

    test('fresh entry is valid', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final ct = CachedCt(
        ct: 'x',
        sessionId: 's',
        expiresAt: now.add(const Duration(hours: 1)),
      );
      expect(ct.isValidAt(now), isTrue);
    });

    test('custom margin honored', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final ct = CachedCt(
        ct: 'x',
        sessionId: 's',
        expiresAt: now.add(const Duration(seconds: 10)),
      );
      expect(ct.isValidAt(now, margin: const Duration(seconds: 5)), isTrue);
      expect(ct.isValidAt(now, margin: const Duration(seconds: 20)), isFalse);
    });
  });

  group('CachedCt JSON', () {
    test('round-trips through toJson/fromJson', () {
      final original = CachedCt(
        ct: 'header.payload.sig',
        sessionId: 'session-uuid',
        expiresAt: DateTime.utc(2030, 6, 15, 14, 30),
      );
      final restored = CachedCt.fromJson(original.toJson());
      expect(restored.ct, original.ct);
      expect(restored.sessionId, original.sessionId);
      expect(restored.expiresAt, original.expiresAt);
    });
  });
}
