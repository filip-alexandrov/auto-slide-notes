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

  private func reportStatus() {
    let peers = session.connectedPeers
    let state = peers.isEmpty ? (connecting ? "connecting" : "searching") : "connected"
    let peer = peers.first?.displayName ?? pendingPeer?.displayName
    DispatchQueue.main.async {
      self.channel?.invokeMethod("status", arguments: ["state": state, "peer": peer as Any])
    }
  }

  private var connecting = false
  private var pendingPeer: MCPeerID?

  // MARK: MCNearbyServiceBrowserDelegate

  func browser(
    _ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
    withDiscoveryInfo info: [String: String]?
  ) {
    guard running, !connecting, !session.connectedPeers.contains(peerID) else { return }
    pendingPeer = peerID
    connecting = true
    reportStatus()
    // The Mac may need the user to approve this iPad, so allow time.
    browser.invitePeer(peerID, to: session, withContext: nil, timeout: 60)
  }

  func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

  func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
    NSLog("SlideLink: browsing failed: \(error)")
  }

  // MARK: MCSessionDelegate

  func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
    if state != .connecting {
      connecting = false
      pendingPeer = nil
    }
    reportStatus()
    // If the Mac declined or the link dropped, look again (a new
    // invitation is sent when the Mac is found).
    if state == .notConnected, running, session.connectedPeers.isEmpty {
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
        guard let self, self.running else { return }
        self.browser.stopBrowsingForPeers()
        self.browser.startBrowsingForPeers()
      }
    }
  }

  func session(
    _ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?
  ) {
    // The temporary file is deleted after this returns, so read it now.
    guard error == nil, let url = localURL, let data = try? Data(contentsOf: url) else {
      return
    }
    let seq = Int(resourceName.filter(\.isNumber)) ?? 0
    DispatchQueue.main.async {
      self.channel?.invokeMethod(
        "slide", arguments: ["seq": seq, "bytes": FlutterStandardTypedData(bytes: data)])
    }
  }
}
