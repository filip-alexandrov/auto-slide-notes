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

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "selectRegion":
      window?.orderOut(nil)
      highlight.hide()
      selector.begin { [weak self] rect in
        self?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard let rect = rect else { return result(nil) }
        result(Self.encode(rect))
      }

    case "capture":
      guard let args = call.arguments as? [String: Any], let rect = Self.decode(args) else {
        return result(FlutterError(code: "bad_args", message: "Expected x, y, width, height", details: nil))
      }
      capture(rect, result: result)

    case "showRegion":
      guard let args = call.arguments as? [String: Any], let rect = Self.decode(args) else {
        return result(FlutterError(code: "bad_args", message: "Expected x, y, width, height", details: nil))
      }
      highlight.show(rect)
      result(nil)

    case "hideRegion":
      highlight.hide()
      result(nil)

    case "hasScreenRecordingPermission":
      result(CGPreflightScreenCaptureAccess())

    case "requestScreenRecordingPermission":
      result(CGRequestScreenCaptureAccess())

    case "registerHotKey":
      guard let args = call.arguments as? [String: Any],
            let keyCode = (args["keyCode"] as? NSNumber)?.uint32Value,
            let modifiers = (args["modifiers"] as? NSNumber)?.uint32Value else {
        return result(FlutterError(code: "bad_args", message: "Expected keyCode, modifiers", details: nil))
      }
      result(hotKey.register(keyCode: keyCode, modifiers: modifiers))

    case "unregisterHotKey":
      hotKey.unregister()
      result(nil)

    case "recordHotKey":
      // Pressing the current shortcut must be recorded, not trigger a capture.
      hotKey.unregister()
      recorder.begin { result($0) }

    case "cancelHotKeyRecording":
      recorder.finish(nil)
      result(nil)

    case "playFeedback":
      if (call.arguments as? Bool) ?? false {
        NSSound(named: "Tink")?.play()
      } else {
        NSSound.beep()
      }
      result(nil)

    case "setAlwaysOnTop":
      let onTop = (call.arguments as? Bool) ?? false
      window?.level = onTop ? .floating : .normal
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - Region selection overlay

/// Covers every display with a dimmed, borderless window and lets the user
/// drag out a rectangle. Esc or right-click cancels.
final class RegionSelector {
  private var windows: [NSWindow] = []
  private var completion: ((CGRect?) -> Void)?

  /// Drag start / current position in Cocoa global coordinates.
  fileprivate var start: NSPoint?
  fileprivate var current: NSPoint?

  fileprivate var selection: NSRect? {
    guard let a = start, let b = current else { return nil }
    return NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
  }

  func begin(completion: @escaping (CGRect?) -> Void) {
    if !windows.isEmpty { finish(cancelled: true) }
    self.completion = completion
    start = nil
    current = nil

    for screen in NSScreen.screens {
      let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless,
                            backing: .buffered, defer: false)
      w.setFrame(screen.frame, display: false)
      w.level = .screenSaver
      w.isOpaque = false
      w.backgroundColor = .clear
      w.hasShadow = false
      w.isReleasedWhenClosed = false
      w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
      view.selector = self
      w.contentView = view
      w.orderFrontRegardless()
      windows.append(w)
    }
    NSApp.activate(ignoringOtherApps: true)
    // Make the window under the mouse key so it receives Esc.
    let mouse = NSEvent.mouseLocation
    (windows.first { $0.frame.contains(mouse) } ?? windows.first)?.makeKey()
    NSCursor.crosshair.push()
  }

  fileprivate func redraw() {
    windows.forEach { $0.contentView?.needsDisplay = true }
  }

  fileprivate func finish(cancelled: Bool) {
    let rect = cancelled ? nil : selection
    NSCursor.pop()
    windows.forEach { $0.orderOut(nil) }
    windows.removeAll()
    start = nil
    current = nil
    let done = completion
    completion = nil
    done?(rect.map(ScreenChannel.topLeftRect(fromCocoa:)))
  }
}

private final class OverlayWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
