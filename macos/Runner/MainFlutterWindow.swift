import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Cửa sổ dạng dọc giống điện thoại, đặt giữa màn hình; vẫn kéo rộng được.
    let size = NSSize(width: 480, height: 940)
    let visible = (self.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(origin: .zero, size: size)
    let height = min(size.height, visible.height - 40)
    let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - height / 2)
    self.setFrame(NSRect(origin: origin, size: NSSize(width: size.width, height: height)), display: true)
    self.minSize = NSSize(width: 400, height: 640)
    self.title = "AMV-WebManage"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
