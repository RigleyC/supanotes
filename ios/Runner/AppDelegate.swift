import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ShareBridge")
    let channel = FlutterMethodChannel(
      name: "com.supanotes/share",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "publishNotesIndex":
        ShareBridgeStore.shared.saveIndex(call.arguments)
        result(nil)
      case "publishSessionCredentials":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(code: "invalid_payload", message: "Expected a map", details: nil))
          return
        }
        ShareBridgeStore.shared.saveSession(arguments)
        result(nil)
      case "clearShareSession":
        ShareBridgeStore.shared.clear()
        result(nil)
      case "retryPendingShares":
        result(nil)
      case "readPendingShare":
        result(ShareBridgeStore.shared.readPendingShare())
      case "clearPendingShare":
        ShareBridgeStore.shared.clearPendingShare()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
