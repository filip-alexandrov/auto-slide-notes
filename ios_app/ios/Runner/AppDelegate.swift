import Flutter
import MultipeerConnectivity
import UIKit

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PencilTap") {
      PencilTap.shared.channel = FlutterMethodChannel(
        name: "ipad_notes/pencil", binaryMessenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SlideLink") {
      SlideLinkClient.shared.attach(messenger: registrar.messenger())
    }
  }
}

/// Forwards Apple Pencil double-taps (2nd gen / Pro) to Dart as `doubleTap`.
final class PencilTap: NSObject, UIPencilInteractionDelegate {
  static let shared = PencilTap()
  var channel: FlutterMethodChannel?

  func attach(to view: UIView) {
    guard !view.interactions.contains(where: { $0 is UIPencilInteraction }) else { return }
    let interaction = UIPencilInteraction()
    interaction.delegate = self
    view.addInteraction(interaction)
  }

  @available(iOS 17.5, *)
  func pencilInteraction(_ interaction: UIPencilInteraction,
                         didReceiveTap tap: UIPencilInteraction.Tap) {
    channel?.invokeMethod("doubleTap", arguments: nil)
  }

  // Called instead of the method above before iOS 17.5.
  func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    channel?.invokeMethod("doubleTap", arguments: nil)
  }
}
