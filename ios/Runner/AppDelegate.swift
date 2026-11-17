import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WatchedLedgerReminders") {
      let channel = FlutterMethodChannel(
        name: "watchedledger/reminders", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        EpisodeReminders.handle(call, result: result)
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WatchedLedgerShare") {
      let channel = FlutterMethodChannel(
        name: "watchedledger/share", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "shareText", let text = call.arguments as? String else {
          result(FlutterMethodNotImplemented)
          return
        }
        ShareOut.present(String(text.prefix(200000)))
        result(nil)
      }
    }
  }
}

/// Shares a folder as plain text through the iPhone share sheet.
enum ShareOut {
  static func present(_ text: String) {
    DispatchQueue.main.async {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      guard let root = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?
        .rootViewController
      else { return }
      var top = root
      while let next = top.presentedViewController { top = next }
      let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
      if let popover = sheet.popoverPresentationController {
        popover.sourceView = top.view
        popover.sourceRect = CGRect(
          x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
      }
      top.present(sheet, animated: true)
    }
  }
}

/// "New episode" reminders scheduled by the phone for itself: no server,
/// no account, no push token.
enum EpisodeReminders {
  static let prefix = "wl-episode-"

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    switch call.method {
    case "requestPermission":
      center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    case "schedule":
      let list = (call.arguments as? [[String: Any]]) ?? []
      removeOurs(center) {
        let now = Date().timeIntervalSince1970
        for item in list.prefix(64) {
          guard let id = item["id"] as? Int,
            let atMs = (item["at"] as? NSNumber)?.doubleValue,
            let title = item["title"] as? String
          else { continue }
          let at = atMs / 1000
          if at <= now { continue }
          let content = UNMutableNotificationContent()
          content.title = String(title.prefix(120))
          content.body = String(((item["body"] as? String) ?? "").prefix(200))
          content.sound = .default
          let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, at - now), repeats: false)
          center.add(
            UNNotificationRequest(identifier: prefix + String(id), content: content, trigger: trigger))
        }
        DispatchQueue.main.async { result(nil) }
      }
    case "cancelAll":
      removeOurs(center) { DispatchQueue.main.async { result(nil) } }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func removeOurs(_ center: UNUserNotificationCenter, then done: @escaping () -> Void) {
    center.getPendingNotificationRequests { requests in
      let ids = requests.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
      center.removePendingNotificationRequests(withIdentifiers: ids)
      done()
    }
  }
}
