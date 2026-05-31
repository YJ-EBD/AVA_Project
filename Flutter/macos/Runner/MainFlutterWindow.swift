import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var avaWindowChannel: FlutterMethodChannel?
  private var preAzoomFrame: NSRect?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    configureAvaChrome()
    configureAvaWindowChannel(flutterViewController)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  private func configureAvaChrome() {
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true
  }

  private func configureAvaWindowChannel(_ flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ava/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    avaWindowChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Window is unavailable.", details: nil))
        return
      }

      switch call.method {
      case "startDrag":
        if let event = NSApp.currentEvent {
          self.performDrag(with: event)
        }
        result(nil)
      case "minimize":
        self.miniaturize(nil)
        result(nil)
      case "toggleMaximize":
        self.zoom(nil)
        result(nil)
      case "close":
        self.close()
        result(nil)
      case "setWindowTitle":
        let args = call.arguments as? [String: Any]
        let requestedTitle = args?["title"] as? String
        self.title = requestedTitle?.isEmpty == false ? requestedTitle! : "AVA"
        result(nil)
      case "compactMessenger":
        self.setAvaContentWidth(460)
        result(nil)
      case "showAuthWindow":
        self.setAvaContentSize(width: 460, height: 720)
        self.showAvaWindow()
        result(nil)
      case "expandMessenger":
        self.setAvaContentWidth(960)
        self.showAvaWindow()
        result(nil)
      case "showMessengerWindow":
        self.showAvaWindow()
        result(nil)
      case "showQuickAvaAiWindow":
        self.setAvaContentSize(width: 430, height: 680)
        self.showAvaWindow()
        result(nil)
      case "openAzoomMessenger":
        if self.preAzoomFrame == nil {
          self.preAzoomFrame = self.frame
        }
        self.setAvaContentSize(width: 1344, height: 722)
        self.showAvaWindow()
        result(nil)
      case "restoreMessengerFromAzoom":
        if let frame = self.preAzoomFrame {
          self.setFrame(frame, display: true, animate: true)
          self.preAzoomFrame = nil
        }
        self.showAvaWindow()
        result(nil)
      case "setAzoomFullscreen":
        let args = call.arguments as? [String: Any]
        let fullscreen = args?["fullscreen"] as? Bool ?? false
        let isFullscreen = self.styleMask.contains(.fullScreen)
        if fullscreen != isFullscreen {
          self.toggleFullScreen(nil)
        }
        result(nil)
      case "isAvaForeground":
        result(NSApp.isActive && self.isKeyWindow)
      default:
        result(nil)
      }
    }
  }

  private func setAvaContentWidth(_ width: CGFloat) {
    let currentHeight = contentView?.bounds.height ?? 720
    setAvaContentSize(width: width, height: currentHeight)
  }

  private func setAvaContentSize(width: CGFloat, height: CGFloat) {
    let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
    setContentSize(NSSize(width: width, height: height))
    setFrameTopLeftPoint(topLeft)
  }

  private func showAvaWindow() {
    if isMiniaturized {
      deminiaturize(nil)
    }
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
