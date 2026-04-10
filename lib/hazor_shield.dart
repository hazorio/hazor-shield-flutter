/// Hazor Shield SDK for Flutter.
///
/// ```dart
/// final shield = HazorShield(siteKey: 'hzs_live_abc123');
/// final cd = await shield.verify();
/// // Pass `cd` to your backend which calls /validate via the server SDK.
/// ```
library hazor_shield;

export 'src/shield.dart';
export 'src/types.dart';
export 'src/native_bridge.dart' show NativeBridge;
