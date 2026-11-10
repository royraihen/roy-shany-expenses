import Flutter
import UIKit

class RasbChannelManager {
  static let shared = RasbChannelManager()
  private var channel: FlutterMethodChannel?
  private var pendingPayload: [String: String]?

  func setup(binaryMessenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: "com.royandshany.expense_tracker/rasb",
      binaryMessenger: binaryMessenger
    )
    self.channel = methodChannel

    methodChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "getInitialRasbContent" {
        let payload = self?.pendingPayload
        self?.pendingPayload = nil
        result(payload)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func handleIncomingURL(_ url: URL, notifyImmediately: Bool) {
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed {
        url.stopAccessingSecurityScopedResource()
      }
    }

    guard let data = try? Data(contentsOf: url),
          let content = String(data: data, encoding: .utf8),
          !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    let payload: [String: String] = [
      "fileName": url.lastPathComponent,
      "content": content
    ]

    if notifyImmediately, let activeChannel = channel {
      activeChannel.invokeMethod("onRasbFileOpened", arguments: payload)
    } else {
      pendingPayload = payload
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      RasbChannelManager.shared.handleIncomingURL(url, notifyImmediately: false)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    RasbChannelManager.shared.handleIncomingURL(url, notifyImmediately: true)
    return true
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    RasbChannelManager.shared.setup(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}
