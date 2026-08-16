import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Sensible desktop default; keep the window freely resizable.
    let defaultSize = NSSize(width: 1280, height: 800)
    self.setContentSize(defaultSize)
    self.contentMinSize = NSSize(width: 640, height: 480)
    self.styleMask.insert(.resizable)

    if let screen = self.screen ?? NSScreen.main {
      let visible = screen.visibleFrame
      let origin = NSPoint(
        x: visible.midX - defaultSize.width / 2,
        y: visible.midY - defaultSize.height / 2
      )
      self.setFrameOrigin(origin)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
