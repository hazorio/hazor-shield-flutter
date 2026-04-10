import DeviceCheck
import Flutter
import UIKit

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
        case "requestDeviceCheck":
            let args = call.arguments as? [String: Any] ?? [:]
            let _ = args["nonce"] as? String ?? ""
            requestDeviceCheck(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

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
}
