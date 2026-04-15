import 'package:flutter/material.dart';
import 'package:hazor_shield/hazor_shield.dart';
import 'package:http/http.dart' as http;

/// Pass via `flutter run --dart-define=SITE_KEY=hzs_live_...`.
const String kSiteKey = String.fromEnvironment('SITE_KEY');
const String kBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'https://api.example.com',
);

void main() {
  runApp(const ShieldExampleApp());
}

class ShieldExampleApp extends StatelessWidget {
  const ShieldExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hazor Shield Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: kSiteKey.isEmpty
          ? const _MissingSiteKey()
          : const _HomePage(),
    );
  }
}

class _MissingSiteKey extends StatelessWidget {
  const _MissingSiteKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hazor Shield Example')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Missing SITE_KEY. Run with:\n\n'
          '  flutter run --dart-define=SITE_KEY=hzs_live_...',
          style: TextStyle(fontFamily: 'monospace'),
        ),
      ),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage();
  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  late final HazorShield _shield;
  late final ShieldHttpClient _client;
  String _status = 'idle';
  String? _lastCd;
  int _verifyCount = 0;
  int _getCdCount = 0;

  @override
  void initState() {
    super.initState();
    _shield = HazorShield(siteKey: kSiteKey);
    _client = ShieldHttpClient(inner: http.Client(), shield: _shield);
  }

  @override
  void dispose() {
    _client.close();
    _shield.dispose();
    super.dispose();
  }

  Future<void> _verifyFull() async {
    setState(() => _status = 'running full verify…');
    try {
      final result = await _shield.verify();
      setState(() {
        _verifyCount++;
        _lastCd = result.cd;
        _status = 'verify OK — cd valid for ${_remaining(result.expiresAt)}';
      });
    } catch (e) {
      setState(() => _status = 'verify failed: $e');
    }
  }

  Future<void> _getCd() async {
    setState(() => _status = 'getCd…');
    try {
      final result = await _shield.getCd();
      setState(() {
        _getCdCount++;
        _lastCd = result.cd;
        _status = 'getCd OK (CT cache ${_verifyCount > 0 ? "warm" : "cold"})';
      });
    } catch (e) {
      setState(() => _status = 'getCd failed: $e');
    }
  }

  Future<void> _callBackend() async {
    setState(() => _status = 'calling backend…');
    try {
      final resp = await _client.get(Uri.parse('$kBackendUrl/me'));
      setState(() {
        _status = 'backend HTTP ${resp.statusCode}: ${resp.body.substring(0,
            resp.body.length.clamp(0, 80))}';
      });
    } catch (e) {
      setState(() => _status = 'backend error: $e');
    }
  }

  Future<void> _invalidate() async {
    await _shield.invalidate();
    setState(() => _status = 'cache invalidated');
  }

  String _remaining(DateTime expiresAt) {
    final d = expiresAt.difference(DateTime.now());
    if (d.isNegative) return 'expired';
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hazor Shield Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoCard(
              siteKey: kSiteKey,
              status: _status,
              verifyCount: _verifyCount,
              getCdCount: _getCdCount,
              lastCd: _lastCd,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _verifyFull,
              child: const Text('Full verify (init + PoW + attest)'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _getCd,
              child: const Text('getCd (uses cached CT when possible)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _callBackend,
              child: const Text('GET /me via ShieldHttpClient'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _invalidate,
              child: const Text('Invalidate cache'),
            ),
            const Spacer(),
            Text(
              'native core version: ${_shield.version}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.siteKey,
    required this.status,
    required this.verifyCount,
    required this.getCdCount,
    required this.lastCd,
  });

  final String siteKey;
  final String status;
  final int verifyCount;
  final int getCdCount;
  final String? lastCd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row(k: 'site_key', v: siteKey),
            _Row(k: 'status', v: status),
            _Row(k: 'verifies', v: '$verifyCount'),
            _Row(k: 'getCd calls', v: '$getCdCount'),
            _Row(k: 'last cd', v: lastCd ?? '—', truncate: true),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.k, required this.v, this.truncate = false});
  final String k;
  final String v;
  final bool truncate;
  @override
  Widget build(BuildContext context) {
    final display =
        truncate && v.length > 40 ? '${v.substring(0, 40)}…' : v;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              k,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: Text(
              display,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
