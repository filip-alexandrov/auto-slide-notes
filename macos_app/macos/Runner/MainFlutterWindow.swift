import Carbon.HIToolbox
import Cocoa
import FlutterMacOS
import MultipeerConnectivity

class MainFlutterWindow: NSWindow {
  private var screenChannel: ScreenChannel?
  private var slideLink: SlideLinkHost?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 460, height: 620))
    self.minSize = NSSize(width: 380, height: 480)
    self.title = "Slide Notes"
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    screenChannel = ScreenChannel(
      messenger: flutterViewController.engine.binaryMessenger, window: self)
    slideLink = SlideLinkHost(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

// MARK: - Method channel

/// Bridges the Flutter UI to native screen APIs.
///
/// All rectangles crossing the channel are in global "top-left" points:
/// origin at the top-left corner of the primary display, y growing down.
/// This is the coordinate space `screencapture -R` expects, and it covers
/// secondary displays too (their coordinates may be negative).
final class ScreenChannel {
  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?
  private let selector = RegionSelector()
  private let highlight = RegionHighlight()
  private let hotKey = GlobalHotKey()
  private let recorder = HotKeyRecorder()

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    self.channel = FlutterMethodChannel(name: "mac_capture/screen", binaryMessenger: messenger)
    self.window = window
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    hotKey.onPress = { [weak self] in
      self?.channel.invokeMethod("hotKeyPressed", arguments: nil)
    }
  }
}
