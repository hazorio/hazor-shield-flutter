import 'package:http/http.dart' as http;

import '../shield.dart';
import '../types.dart';

const String _shieldControlPlaneHost = 'protect.hazor.io';

/// [http.Client] wrapper that attaches a fresh Clearance Decision to
/// every outbound request and transparently retries once on a
/// Shield-rejected response.
///
/// ```dart
/// final shield = HazorShield(siteKey: 'hzs_live_x');
/// final client = ShieldHttpClient(inner: http.Client(), shield: shield);
/// final resp = await client.get(Uri.parse('https://api.example.com/me'));
/// ```
///
/// Behavior:
/// - Before each request, calls [HazorShield.getCd] and **mutates the
///   request's headers** with `X-Hazor-Shield-CD: <cd>`. Reusing the
///   same [http.BaseRequest] across calls is not supported and never
///   was — every `send()` consumes the body stream.
/// - On a 401 or 403 whose `WWW-Authenticate` starts with
///   `Hazor-Shield`, the client invalidates the cached CT and retries
///   the request once.
/// - Requests to `protect.hazor.io` bypass the interceptor so the SDK's
///   own `init/verify/refresh` calls don't recurse.
/// - Requests whose host is in [skipHosts] or for which [skip] returns
///   true bypass the interceptor entirely.
///
/// **Multipart / streamed requests**: retry on 401 is not possible —
/// the body stream is consumed by the first send. Such requests are
/// sent once with the CD header; a Shield-level rejection returns to
/// the caller as-is. The caller should then `shield.invalidate()`
/// manually and retry at the app level.
class ShieldHttpClient extends http.BaseClient {
  final http.Client _inner;
  final HazorShield _shield;
  final Set<String> skipHosts;
  final bool Function(Uri)? _skip;

  ShieldHttpClient({
    required http.Client inner,
    required HazorShield shield,
    this.skipHosts = const {},
    bool Function(Uri url)? skip,
  })  : _inner = inner,
        _shield = shield,
        _skip = skip;

  bool _shouldSkip(Uri url) {
    if (skipHosts.contains(url.host)) return true;
    if (_skip != null && _skip!(url)) return true;
    // Don't re-decorate requests to the Shield control plane. Checking
    // host AND path guards against backends that happen to mount a
    // /api/v1/protect/* route of their own.
    return url.host == _shieldControlPlaneHost &&
        url.path.startsWith('/api/v1/protect/');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_shouldSkip(request.url)) {
      return _inner.send(request);
    }

    final first = await _sendWithCd(request);
    if (!_looksLikeShieldReject(first)) {
      return first;
    }

    // Drain the first response so the socket can be reused.
    await first.stream.drain<void>();
    await _shield.invalidate();

    final retry = _cloneRequest(request);
    return _sendWithCd(retry);
  }

  Future<http.StreamedResponse> _sendWithCd(http.BaseRequest request) async {
    final result = await _shield.getCd();
    request.headers[kShieldCdHeader] = result.cd;
    return _inner.send(request);
  }

  bool _looksLikeShieldReject(http.StreamedResponse resp) {
    if (resp.statusCode != 401 && resp.statusCode != 403) return false;
    final auth = resp.headers['www-authenticate'];
    return auth != null && auth.toLowerCase().startsWith('hazor-shield');
  }

  @override
  void close() {
    _inner.close();
  }
}

http.BaseRequest _cloneRequest(http.BaseRequest original) {
  if (original is http.Request) {
    final copy = http.Request(original.method, original.url)
      ..headers.addAll(original.headers)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection
      ..bodyBytes = original.bodyBytes;
    if (original.encoding != copy.encoding) copy.encoding = original.encoding;
    return copy;
  }
  // http.MultipartRequest and http.StreamedRequest hold streams that
  // are consumed on first send. Retrying either would send an empty
  // body or throw "Stream already listened to". Fail loudly instead of
  // silently corrupting the upload — the caller should handle retry at
  // the app layer for these.
  throw StateError(
    'ShieldHttpClient: cannot auto-retry ${original.runtimeType}. '
    'Multipart and streamed bodies are consumed on first send — '
    'catch the 401 at the app layer, call shield.invalidate(), and '
    'build a fresh request.',
  );
}
