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

/// Receives screenshots from the Mac app over Multipeer Connectivity
/// (peer-to-peer Wi-Fi / Bluetooth) — no server or shared network needed.
///
/// While a note is open, Dart calls `start`: the iPad looks for nearby Macs
/// and asks to connect (the Mac app approves an iPad once). Each slide
/// arrives as a resource named `slide-<n>.png` and is passed to Dart.
///
/// Channel `ipad_notes/link`:
///   Dart → native: `start`, `stop`
///   native → Dart: `status({state: searching|connecting|connected, peer})`,
///                  `slide({seq: Int, bytes: Uint8List})`
final class SlideLinkClient: NSObject, MCSessionDelegate, MCNearbyServiceBrowserDelegate {
  static let shared = SlideLinkClient()

  /// Must match the Mac app (and NSBonjourServices in both Info.plists).
  private static let serviceType = "notes-slides"

  private var channel: FlutterMethodChannel?
  private let peerID = MCPeerID(displayName: UIDevice.current.name)
  private lazy var session: MCSession = {
    let s = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
    s.delegate = self
    return s
  }()
  private lazy var browser: MCNearbyServiceBrowser = {
    let b = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
    b.delegate = self
    return b
  }()
  private var running = false

  func attach(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "ipad_notes/link", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "start":
        self?.start()
        result(nil)
      case "stop":
        self?.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
  }

  private func start() {
    guard !running else { return reportStatus() }
    running = true
    browser.startBrowsingForPeers()
    reportStatus()
  }

  private func stop() {
    guard running else { return }
    running = false
    browser.stopBrowsingForPeers()
    session.disconnect()
  }
}
