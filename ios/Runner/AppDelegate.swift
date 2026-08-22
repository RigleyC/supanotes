import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    UNUserNotificationCenter.current().delegate = self
    // Recreating the background session flushes events queued by the system
    // for uploads started in previous runs.
    ShareBackgroundUploader.shared.resumePendingDelivery()

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.supanotes/share",
        binaryMessenger: controller.binaryMessenger
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
        case "readPendingShare":
          result(ShareBridgeStore.shared.readPendingShare())
        case "clearPendingShare":
          ShareBridgeStore.shared.clearPendingShare()
          result(nil)
        case "retryPendingShares":
          ShareBackgroundUploader.shared.resumePendingDelivery()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
