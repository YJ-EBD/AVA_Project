import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerWindowChannel(flutterViewController: flutterViewController)

    super.awakeFromNib()
  }

  private func registerWindowChannel(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ava/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
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
      case "compactMessenger":
        self.resizeCentered(width: 480, height: 760)
        result(nil)
      case "expandMessenger":
        self.resizeCentered(width: 1440, height: 860)
        result(nil)
      case "openAzoomMessenger":
        self.resizeCentered(width: 1366, height: 820)
        result(nil)
      case "restoreMessengerFromAzoom":
        self.resizeCentered(width: 1440, height: 860)
        result(nil)
      case "setAzoomFullscreen":
        let args = call.arguments as? [String: Any]
        let fullscreen = args?["fullscreen"] as? Bool ?? false
        let isFullscreen = self.styleMask.contains(.fullScreen)
        if fullscreen != isFullscreen {
          self.toggleFullScreen(nil)
        }
        result(nil)
      case "setMessengerOpacity":
        let args = call.arguments as? [String: Any]
        let opacity = args?["opacity"] as? Double ?? 1.0
        self.alphaValue = min(1.0, max(0.18, opacity))
        result(nil)
      case "isAvaForeground":
        result(NSApp.isActive)
      case "showChatNotification":
        result(false)
      default:
        result(nil)
      }
    }
  }

  private func resizeCentered(width: CGFloat, height: CGFloat) {
    if styleMask.contains(.fullScreen) {
      return
    }

    let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
    let resolvedWidth = min(width, visibleFrame.width)
    let resolvedHeight = min(height, visibleFrame.height)
    let nextFrame = NSRect(
      x: visibleFrame.midX - resolvedWidth / 2,
      y: visibleFrame.midY - resolvedHeight / 2,
      width: resolvedWidth,
      height: resolvedHeight
    )
    setFrame(nextFrame, display: true, animate: true)
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
