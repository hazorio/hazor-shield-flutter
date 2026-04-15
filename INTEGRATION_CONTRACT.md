# Hazor Shield — Integration Contract (v1.0)

Fuente de verdad para el Flutter SDK. Extraído del código de `hazorlb/crates/lb-shield` y validado contra los server SDKs (`hazor-shield-sdk-python`, `hazor-shield-sdk-node`) y los mobile SDKs nativos de referencia (`hazor-shield-android`, `hazor-shield-ios`).

## Endpoints

Base URL: `https://protect.hazor.io`

### `POST /api/v1/protect/init`
Request headers:
- `Content-Type: application/json`
- `X-Hazor-Shield-Site-Key: <site_key>`

Body:
```json
{ "site_key": "hzs_live_abc123" }
```

Response 200:
```json
{
  "session_id": "uuid-v4",
  "challenge": "<32 chars url-safe base64>",
  "difficulty": 4,
  "tls_pins": { "current": ["sha256/..."], "next": [] }
}
```

Errores: `403 invalid_site_key`, `429 rate_limited`.

### `POST /api/v1/protect/verify`
Body:
```json
{
  "site_key": "hzs_live_abc123",
  "session_id": "uuid-v4-from-init",
  "challenge": "<same as init>",
  "nonce": 12345,
  "hash": "<64 hex chars>"
}
```

Response 200:
```json
{ "ct": "<opaque token>", "expires_at": 1700000000 }
```

Errores: `403 invalid_site_key | hash_mismatch | difficulty_not_met`.

### `POST /api/v1/protect/refresh`
Body: `{ "ct": "<from verify>" }`

Response 200:
```json
{ "cd": "<opaque token>", "expires_in_secs": 300 }
```

Errores: `403 invalid_ct_format | invalid_site_key | invalid_ct`.

### `POST /api/v1/protect/validate`
**NO llamar desde mobile.** Este endpoint lo consume el backend del cliente (vía los server SDKs python/node/go). Single-use. Si lo llamas desde mobile quemas el cd.

## Propagación del CD al backend del cliente

**Header canónico:** `X-Hazor-Shield-CD: <cd>`

Confirmado en `hazor-shield-sdk-python/hazor_shield/{django,flask}.py` (leen `X-Hazor-Shield-CD`) y `hazor-shield-sdk-node/src/middleware/{express,fastify}.ts` (leen `x-hazor-shield-cd`).

> ⚠️ El docstring del SDK Android (`HazorShield.kt:76-77`) dice `X-Hazor-Shield-CT` — **está equivocado**. El nombre correcto en todos los server SDKs es `X-Hazor-Shield-CD`.

El backend del cliente extrae ese header, lo envía a `/protect/validate`, y decide allow/challenge/deny. Hazorlb NO intercepta el header en el tráfico del cliente — es el middleware del backend quien lo consume.

## PoW: detalle crítico

**Composición del input:** `SHA-256(challenge || nonce)` — concatenación directa, **sin separador**.
- Rust server (verify.rs:61): `format!("{}{}", req.challenge, req.nonce)` ← **canónico**
- Android ref (HazorShield.kt:181): `"$prefix$nonce"` con `prefix = "$challenge:"` ← **BUG**, usa `:`
- iOS ref (HazorShield.swift:199): `challenge + ":"` ← **BUG**, usa `:`

Los fallbacks nativos iOS/Android fallan si el native core no está linkeado. Solo funcionan porque el native core (Rust) hace la concatenación correcta.

**Unidad de difficulty:** **hex zeros** (no bits).
- Rust server (verify.rs:91-100): cuenta chars `'0'` al inicio del hex hash.
- Android ref (`hasLeadingZeroBits`): cuenta **bits** ← **BUG**, diverge del server.
- iOS ref (`leadingZeroBitCount`): cuenta **bits** ← **BUG**, diverge.

El SDK Flutter en `pow.dart` debe contar **leading hex zeros** (cada zero hex = 4 bits). Con `difficulty=4` del server, se requieren 4 chars `'0'` al inicio = 16 bits.

**Formato del nonce:** `u64` (unsigned 64-bit). `hash` en hex minúsculas, 64 chars.

## CT / CD

- **CT (Challenge Token)**: 7 partes separadas por `.`, firmado con HMAC-SHA256 del `secret_hash` del site. TTL ~1h. Reutilizable dentro de su TTL.
- **CD (Clearance Decision)**: opaco, base64 url-safe. **Single-use**, replay-protected por el `CdStore`. TTL:
  - Modo `enforce` / `monitor`: `DEFAULT_CD_TTL_SECS` (~300s).
  - Modo `enforce_mobile`: `MOBILE_CD_TTL_SECS` (30s).

**Implicación**: si el cliente mobile cachea un CD, el TTL efectivo para mobile es **30s**. Después hay que hacer `/refresh` con el CT (sin re-PoW, CT dura 1h), y solo cada hora re-PoW completo.

## Attestation (estado real)

**`/protect/verify` actualmente NO recibe attestation token.** El schema `VerifyRequest` en `lb-shield/src/api/verify.rs:31-38` solo tiene `site_key, session_id, challenge, nonce, hash`. Los SDKs envían `signals` y `device_token` pero el handler los ignora (serde default drop).

La lógica de attestation (`play_integrity.rs`, `app_attest.rs`) existe pero no está conectada al endpoint de verify. Está diseñada para un flujo futuro.

**Consecuencia para la Fase 6 (nonce server-issued)**: el trabajo de backend es mayor de lo pensado. No es solo agregar `attestation_nonce` a InitResponse — hay que:
1. Agregar `attestation_token` + `attestation_nonce` al `VerifyRequest`.
2. Wire `RealPlayIntegrityVerifier` / `RealAppAttestVerifier` dentro de `handle_verify`.
3. Bajar el verdict al `CdStore` para que `/validate` lo componga con los demás signals.

## Modo mobile (`enforce_mobile`)

Existe como variante de `EnforceMode`. Afecta:
- TTL corto del CD (30s en vez de 300s).
- Rule context tiene `mobile_attestation_verified: bool` que las reglas custom del tenant pueden evaluar.

No existe endpoint específico tipo `/protect/attest` para mobile — el flujo es el mismo que web pero con el site type marcado como mobile y enforce_mode `enforce_mobile`.

## Allowlist de cert (mobile_app_certs)

Tabla `shield_mobile_certs` en el tenant DB (gestionada desde el panel via `MobileAppCertService`). Hot-reload en cada edge de hazorlb cada 10s via `ApkAllowlistCache`. La verificación del allowlist ocurre **después** de que el attestation token esté verificado — check package name + signing cert SHA-256 contra la entrada correspondiente al site_key + platform.

## Bugs identificados (para arreglar en Fase 1/2)

1. **PoW con separador `:`** en fallbacks Kotlin/Swift → debe ser sin separador (`challenge || nonce`).
2. **PoW cuenta bits en fallback** Kotlin/Swift → debe contar hex chars.
3. **Docstring header equivocado** en `hazor-shield-android/HazorShield.kt:76-77` → `X-Hazor-Shield-CT` debe ser `X-Hazor-Shield-CD`.
4. **`device_token` enviado al server pero ignorado**: hasta que la Fase 6 aterrice el cambio de backend, el campo no tiene efecto.
5. **Flutter SDK envía `nonce` como `u64` en JSON**: verificar serialización (Dart int es 64-bit, OK).
6. **DeviceCheck es deprecated**: Apple marca DeviceCheck como legacy. App Attest es el camino oficial desde iOS 14. Tanto el iOS ref SDK como el plugin Flutter usan DeviceCheck — gap abierto.

## TTLs — resumen

| Objeto | TTL | Reusable |
|--------|-----|----------|
| Challenge (init) | ~session lifetime | No (único por init) |
| CT (verify→refresh) | ~1h | Sí |
| CD web (refresh→validate) | ~300s | **NO, single-use** |
| CD mobile | 30s | **NO, single-use** |
| Site key cache (edge) | 10s refresh | — |
| mobile_app_certs cache | 10s refresh | — |

## Decisiones derivadas para el Flutter SDK

1. **Header de propagación**: `X-Hazor-Shield-CD` (no `CT`). Corregir el docstring Flutter.
2. **PoW**: mantener/migrar a SHA-256 sin separador, difficulty en hex chars.
3. **CT cache**: cachear el **CT** (1h), no el CD (30s single-use). Cada request que necesite cd hace `POST /refresh` con el CT. Solo si el CT expira se hace el verify completo.
4. **Nonce de attestation**: seguir usando `{sessionId}:{nonce}` hasta que aterrice Fase 6 (backend cambia schema).
5. **Flujo en Flutter SDK**:
   - `HazorShield.verify()` → hace init+PoW+verify → CT cacheado → refresh → cd.
   - `HazorShield.getCd()` → si CT vigente, solo refresh; si no, verify completo.
   - `ShieldHttpClient` → inyecta `X-Hazor-Shield-CD` en cada request; en 401 con `WWW-Authenticate: Hazor-Shield`, llama `getCd()` y reintenta.

## Contratos que NO vamos a implementar (fuera de scope v1.0)

- `/protect/behavioral`: telemetría de mouse/touch. Mobile no aplica igual.
- `/sdk/{site_key}/p.js`: polymorphic JS bundle. Es solo web.
- `/telemetry`: no mencionado en este contrato, mobile envía signals embebido en verify (pero server los ignora hoy).
