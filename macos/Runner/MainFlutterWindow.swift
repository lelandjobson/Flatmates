import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Simulate iPhone 15 viewport (393×852 logical points).
    // Comment out or toggle the flag below to restore free-form sizing.
    let simulateMobile = true
    if simulateMobile {
      let mobileSize = NSSize(width: 393, height: 852)
      self.setContentSize(mobileSize)
      self.contentMinSize = mobileSize
      self.contentMaxSize = mobileSize
      self.styleMask.remove(.resizable)
      if let screen = self.screen {
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - mobileSize.width / 2
        let y = screenFrame.midY - mobileSize.height / 2
        self.setFrameOrigin(NSPoint(x: x, y: y))
      }
    } else {
      let windowFrame = self.frame
      self.setFrame(windowFrame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
