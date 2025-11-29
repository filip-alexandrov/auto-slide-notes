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

  private func capture(_ rect: CGRect, result: @escaping FlutterResult) {
    // Hide our own window if it overlaps the region so it doesn't end up in the shot.
    let hide = window.map { Self.topLeftRect(fromCocoa: $0.frame).intersects(rect) } ?? false
    if hide { window?.alphaValue = 0 }
    let delay: TimeInterval = hide ? 0.2 : 0

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      DispatchQueue.global(qos: .userInitiated).async {
        let outcome = Self.runScreencapture(rect)
        DispatchQueue.main.async {
          if hide { self.window?.alphaValue = 1 }
          switch outcome {
          case .success(let data):
            result(FlutterStandardTypedData(bytes: data))
          case .failure(let error):
            result(FlutterError(code: "capture_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  private static func runScreencapture(_ rect: CGRect) -> Result<Data, Error> {
    let path = NSTemporaryDirectory() + "mac_capture_\(UUID().uuidString).png"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let r = rect.integral
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    // -x: no sound, -R: rectangle in global points, -t: format
    process.arguments = [
      "-x", "-t", "png",
      "-R", "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))",
      path,
    ]
    let stderr = Pipe()
    process.standardError = stderr
    do {
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw NSError(domain: "screencapture", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "screencapture failed: \(msg)"])
      }
      return .success(try Data(contentsOf: URL(fileURLWithPath: path)))
    } catch {
      return .failure(error)
    }
  }

  // MARK: Coordinates

  /// Cocoa global coordinates have their origin at the bottom-left of the
  /// primary display; convert to top-left origin.
  static func topLeftRect(fromCocoa r: NSRect) -> CGRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
  }

  /// Inverse of `topLeftRect(fromCocoa:)` (the flip is its own inverse).
  static func cocoaRect(fromTopLeft r: CGRect) -> NSRect {
    topLeftRect(fromCocoa: r)
  }

  private static func encode(_ r: CGRect) -> [String: Double] {
    ["x": Double(r.minX), "y": Double(r.minY), "width": Double(r.width), "height": Double(r.height)]
  }

  private static func decode(_ a: [String: Any]) -> CGRect? {
    guard let x = (a["x"] as? NSNumber)?.doubleValue,
          let y = (a["y"] as? NSNumber)?.doubleValue,
          let w = (a["width"] as? NSNumber)?.doubleValue,
          let h = (a["height"] as? NSNumber)?.doubleValue,
          w > 0, h > 0 else { return nil }
    return CGRect(x: x, y: y, width: w, height: h)
  }
}

// MARK: - Region highlight

/// Draws a frame around the capture region. The frame sits just *outside*
/// the region so it never appears in screenshots, and the window ignores
/// the mouse so it doesn't get in the way.
final class RegionHighlight {
  private static let thickness: CGFloat = 4
  private var window: NSWindow?

  func show(_ topLeftRect: CGRect) {
    let region = ScreenChannel.cocoaRect(fromTopLeft: topLeftRect)
    let frame = region.insetBy(dx: -Self.thickness, dy: -Self.thickness)
    let w = window ?? makeWindow()
    w.setFrame(frame, display: true)
    w.contentView?.needsDisplay = true
    w.orderFrontRegardless()
    window = w
  }

  func hide() {
    window?.orderOut(nil)
  }

  private func makeWindow() -> NSWindow {
    let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = .statusBar
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.ignoresMouseEvents = true
    w.isReleasedWhenClosed = false
    w.sharingType = .none
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    w.contentView = FrameView(thickness: Self.thickness)
    return w
  }

  private final class FrameView: NSView {
    let thickness: CGFloat

    init(thickness: CGFloat) {
      self.thickness = thickness
      super.init(frame: .zero)
      autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
      NSColor.clear.setFill()
      bounds.fill()
      let ring = NSBezierPath(rect: bounds)
      ring.append(NSBezierPath(rect: bounds.insetBy(dx: thickness, dy: thickness)).reversed)
      NSColor.systemRed.withAlphaComponent(0.85).setFill()
      ring.fill()
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

private final class OverlayView: NSView {
  weak var selector: RegionSelector?

  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .crosshair)
  }

  private func globalPoint(_ event: NSEvent) -> NSPoint {
    window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
  }

  override func mouseDown(with event: NSEvent) {
    selector?.start = globalPoint(event)
    selector?.current = selector?.start
    selector?.redraw()
  }

  override func mouseDragged(with event: NSEvent) {
    selector?.current = globalPoint(event)
    selector?.redraw()
  }

  override func mouseUp(with event: NSEvent) {
    guard let selector = selector else { return }
    selector.current = globalPoint(event)
    if let r = selector.selection, r.width >= 4, r.height >= 4 {
      selector.finish(cancelled: false)
    } else {
      // A plain click: keep waiting for a real drag.
      selector.start = nil
      selector.current = nil
      selector.redraw()
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    selector?.finish(cancelled: true)
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { // Esc
      selector?.finish(cancelled: true)
    } else {
      super.keyDown(with: event)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.black.withAlphaComponent(0.35).setFill()
    bounds.fill()

    guard let window = window else { return }
    if let global = selector?.selection {
      let local = window.convertFromScreen(global)
      NSColor.clear.setFill()
      local.fill(using: .copy)
      NSColor.white.setStroke()
      let border = NSBezierPath(rect: local.insetBy(dx: -1, dy: -1))
      border.lineWidth = 2
      border.stroke()

      let label = "\(Int(global.width)) × \(Int(global.height))"
      drawLabel(label, at: NSPoint(x: local.minX, y: local.minY - 24))
    } else {
      let text = "Drag to select the capture area  ·  Esc to cancel"
      let size = (text as NSString).size(withAttributes: Self.labelAttributes)
      drawLabel(text, at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY))
    }
  }

  private static let labelAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor.white,
  ]

  private func drawLabel(_ text: String, at point: NSPoint) {
    let str = text as NSString
    let size = str.size(withAttributes: Self.labelAttributes)
    let bg = NSRect(x: point.x - 6, y: point.y - 3, width: size.width + 12, height: size.height + 6)
    NSColor.black.withAlphaComponent(0.7).setFill()
    NSBezierPath(roundedRect: bg, xRadius: 5, yRadius: 5).fill()
    str.draw(at: point, withAttributes: Self.labelAttributes)
  }
}
