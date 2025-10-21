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
