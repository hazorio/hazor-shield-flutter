import CommonCrypto
import DeviceCheck
import Flutter
import UIKit

// Hazor Shield Flutter plugin — iOS platform channel.
//
// Exposes three methods to Dart:
//   requestAppAttest(nonce)  — iOS 14+: full App Attest flow.
//                              Returns {keyId, attestation, assertion}.
//   requestDeviceCheck(nonce) — legacy fallback (iOS 11+). Returns the
//                              base64 DCDevice token. Nonce is unused
//                              because DeviceCheck has no binding
//                              mechanism — kept for backward compat.
//   isAppAttestSupported()  — probes DCAppAttestService availability.

private let kKeychainService = "io.hazor.shield"
private let kKeychainKeyId = "appattest.keyId"

public class HazorShieldPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "io.hazor.shield/attestation",
            binaryMessenger: registrar.messenger()
        )
        let instance = HazorShieldPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "requestAppAttest":
            let args = call.arguments as? [String: Any] ?? [:]
            let nonce = args["nonce"] as? String ?? ""
            requestAppAttest(nonce: nonce, result: result)
        case "requestDeviceCheck":
            requestDeviceCheck(result: result)
        case "isAppAttestSupported":
            if #available(iOS 14.0, *) {
                result(DCAppAttestService.shared.isSupported)
            } else {
                result(false)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - App Attest

    @available(iOS 14.0, *)
    private func requestAppAttest(nonce: String, result: @escaping FlutterResult) {
        let service = DCAppAttestService.shared
        guard service.isSupported else {
            result(FlutterError(
                code: "APP_ATTEST_UNSUPPORTED",
                message: "App Attest not supported on this device (simulator or iOS<14)",
                details: nil
            ))
            return
        }

        generateOrLoadKey(service: service) { keyResult in
            switch keyResult {
            case .failure(let err):
                result(FlutterError(
                    code: "APP_ATTEST_KEY_FAILED",
                    message: err.localizedDescription,
                    details: nil
                ))
            case .success(let keyId):
                // Always try generateAssertion first. If the key hasn't
                // been attested yet (fresh install, keychain wiped, OS
                // reset), Apple returns DCError.invalidKey and we fall
                // back to attestKey + a second generateAssertion.
                //
                // This avoids the UserDefaults/Keychain desync where
                // the keyId survives reinstall but a "has attested"
                // flag in UserDefaults does not.
                let clientDataHash = Data(HazorShieldPlugin.sha256(nonce))
                service.generateAssertion(keyId, clientDataHash: clientDataHash) { assertion, err in
                    if let assertion = assertion {
                        result([
                            "keyId": keyId,
                            "attestation": NSNull(),
                            "assertion": assertion.base64EncodedString(),
                        ])
                        return
                    }
                    // Assertion failed — check if it's because the key
                    // needs attestation first.
                    let nsError = err as NSError?
                    let isInvalidKey = nsError?.domain == DCError.errorDomain
                        && nsError?.code == DCError.invalidKey.rawValue
                    if !isInvalidKey {
                        result(FlutterError(
                            code: "APP_ATTEST_ASSERTION_FAILED",
                            message: err?.localizedDescription ?? "unknown",
                            details: nil
                        ))
                        return
                    }
                    // First use for this key on this device — attest,
                    // then produce an assertion bound to the same nonce.
                    service.attestKey(keyId, clientDataHash: clientDataHash) { attestation, err in
                        if let err = err {
                            result(FlutterError(
                                code: "APP_ATTEST_ATTEST_FAILED",
                                message: err.localizedDescription,
                                details: nil
                            ))
                            return
                        }
                        guard let attestation = attestation else {
                            result(FlutterError(code: "APP_ATTEST_EMPTY", message: "empty attestation", details: nil))
                            return
                        }
                        service.generateAssertion(keyId, clientDataHash: clientDataHash) { assertion, err in
                            if let err = err {
                                result(FlutterError(
                                    code: "APP_ATTEST_ASSERTION_FAILED",
                                    message: err.localizedDescription,
                                    details: nil
                                ))
                                return
                            }
                            result([
                                "keyId": keyId,
                                "attestation": attestation.base64EncodedString(),
                                "assertion": assertion?.base64EncodedString() ?? NSNull(),
                            ])
                        }
                    }
                }
            }
        }
    }

    @available(iOS 14.0, *)
    private func generateOrLoadKey(
        service: DCAppAttestService,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        if let keyId = HazorShieldPlugin.loadKeyIdFromKeychain() {
            completion(.success(keyId))
            return
        }
        service.generateKey { keyId, err in
            if let err = err {
                completion(.failure(err))
                return
            }
            guard let keyId = keyId else {
                completion(.failure(NSError(
                    domain: "io.hazor.shield",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "generateKey returned nil"]
                )))
                return
            }
            HazorShieldPlugin.saveKeyIdToKeychain(keyId: keyId)
            completion(.success(keyId))
        }
    }

    // MARK: - DeviceCheck (legacy fallback)

    private func requestDeviceCheck(result: @escaping FlutterResult) {
        guard DCDevice.current.isSupported else {
            result(FlutterError(
                code: "DEVICE_CHECK_UNAVAILABLE",
                message: "DeviceCheck is not supported on this device",
                details: nil
            ))
            return
        }
        DCDevice.current.generateToken { tokenData, error in
            if let error = error {
                result(FlutterError(
                    code: "DEVICE_CHECK_FAILED",
                    message: error.localizedDescription,
                    details: nil
                ))
                return
            }
            guard let data = tokenData else {
                result(FlutterError(
                    code: "DEVICE_CHECK_EMPTY",
                    message: "DeviceCheck returned empty token",
                    details: nil
                ))
                return
            }
            result(data.base64EncodedString())
        }
    }

    // MARK: - Keychain helpers (keyId persistence)

    private static func loadKeyIdFromKeychain() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kKeychainService,
            kSecAttrAccount as String: kKeychainKeyId,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func saveKeyIdToKeychain(keyId: String) {
        let data = keyId.data(using: .utf8)!
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kKeychainService,
            kSecAttrAccount as String: kKeychainKeyId,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(attrs as CFDictionary)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    // MARK: - Crypto helpers

    private static func sha256(_ s: String) -> [UInt8] {
        let data = Data(s.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash
    }
}
