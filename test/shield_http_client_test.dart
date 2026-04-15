import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hazor_shield/hazor_shield.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

/// Fake HazorShield that serves a pre-seeded CD without any network.
class _FakeShield implements HazorShield {
  _FakeShield({required this.cd});

  String cd;
  int getCdCalls = 0;
  int invalidateCalls = 0;

  @override
  Future<VerifyResult> getCd() async {
    getCdCalls++;
    return VerifyResult(
      cd: cd,
      sessionId: 'sess-1',
      expiresAt: DateTime.now().add(const Duration(seconds: 300)),
    );
  }

  @override
  Future<void> invalidate() async {
    invalidateCalls++;
  }

  @override
  Future<VerifyResult> verify() => getCd();

  @override
  String get siteKey => 'hzs_live_x';

  @override
  String get baseUrl => 'https://protect.hazor.io';

  @override
  Duration get timeout => const Duration(seconds: 10);

  @override
  String get version => 'test';

  @override
  List<Signal> collectSignals() => [];

  @override
  void dispose() {}
}

void main() {
  test('injects X-Hazor-Shield-CD on outbound requests', () async {
    final inner = http_testing.MockClient((req) async {
      expect(req.headers[kShieldCdHeader], 'cd-1');
      return http.Response('ok', 200);
    });
    final shield = _FakeShield(cd: 'cd-1');
    final client = ShieldHttpClient(inner: inner, shield: shield);

    final resp = await client.get(Uri.parse('https://api.example.com/me'));
    expect(resp.statusCode, 200);
    expect(shield.getCdCalls, 1);
  });

  test('skips /api/v1/protect/ paths automatically', () async {
    final inner = http_testing.MockClient((req) async {
      expect(req.headers.containsKey(kShieldCdHeader), isFalse);
      return http.Response('{"session_id":"s"}', 200);
    });
    final shield = _FakeShield(cd: 'cd-1');
    final client = ShieldHttpClient(inner: inner, shield: shield);

    await client.post(
      Uri.parse('https://protect.hazor.io/api/v1/protect/init'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'site_key': 'x'}),
    );
    expect(shield.getCdCalls, 0);
  });

  test('skips hosts in skipHosts set', () async {
    final inner = http_testing.MockClient((req) async {
      expect(req.headers.containsKey(kShieldCdHeader), isFalse);
      return http.Response('', 200);
    });
    final shield = _FakeShield(cd: 'cd-1');
    final client = ShieldHttpClient(
      inner: inner,
      shield: shield,
      skipHosts: {'third-party.io'},
    );
    await client.get(Uri.parse('https://third-party.io/ping'));
    expect(shield.getCdCalls, 0);
  });

  test('retries once on 401 with WWW-Authenticate: Hazor-Shield', () async {
    var callCount = 0;
    final seenCds = <String>[];
    final inner = http_testing.MockClient((req) async {
      callCount++;
      seenCds.add(req.headers[kShieldCdHeader] ?? '');
      if (callCount == 1) {
        return http.Response(
          'rejected',
          401,
          headers: {'www-authenticate': 'Hazor-Shield realm="shield"'},
        );
      }
      return http.Response('ok', 200);
    });
    final shield = _FakeShield(cd: 'cd-1');
    final client = ShieldHttpClient(inner: inner, shield: shield);

    final resp = await client.get(Uri.parse('https://api.example.com/secret'));
    expect(resp.statusCode, 200);
    expect(callCount, 2);
    expect(shield.invalidateCalls, 1);
    expect(shield.getCdCalls, 2);
    expect(seenCds, ['cd-1', 'cd-1']);
  });

  test('does not retry on 401 without Hazor-Shield auth challenge', () async {
    var callCount = 0;
    final inner = http_testing.MockClient((req) async {
      callCount++;
      return http.Response(
        'plain 401',
        401,
        headers: {'www-authenticate': 'Bearer realm="api"'},
      );
    });
    final shield = _FakeShield(cd: 'cd-1');
    final client = ShieldHttpClient(inner: inner, shield: shield);

    final resp = await client.get(Uri.parse('https://api.example.com/x'));
    expect(resp.statusCode, 401);
    expect(callCount, 1);
    expect(shield.invalidateCalls, 0);
  });
}
