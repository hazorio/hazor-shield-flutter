/// Hazor Shield SDK for Flutter.
///
/// ```dart
/// import 'package:hazor_shield/hazor_shield.dart';
///
/// final shield = HazorShield(siteKey: 'hzs_live_abc123');
///
/// // Before a sensitive request:
/// final result = await shield.getCd();
/// final resp = await http.post(
///   Uri.parse('https://api.example.com/login'),
///   headers: {kShieldCdHeader: result.cd},
/// );
/// ```
library hazor_shield;

export 'src/ct_store.dart' show CtStore, InMemoryCtStore, SecureCtStore;
export 'src/http/shield_http_client.dart' show ShieldHttpClient;
export 'src/native_bridge.dart' show NativeBridge;
export 'src/shield.dart';
export 'src/types.dart';
// NOTE: No Dio interceptor is shipped. Dio requires the interceptor
// to extend `Interceptor` (nominal type check), so a dynamic duck-
// typed version would crash at registration time. Consumers using Dio
// should write a ~20-line interceptor that calls `shield.getCd()` +
// injects `kShieldCdHeader` + retries on 401. See README for a sample.
