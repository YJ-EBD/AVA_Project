import Cocoa
import Carbon.HIToolbox
import FlutterMacOS

private let avaQuickAvaAiHotKeySignature = OSType(0x41564151)
private let avaQuickAvaAiHotKeyId = UInt32(7201)
private let avaCompactMessengerSize = NSSize(width: 460, height: 720)
private let avaExpandedMessengerWidth = CGFloat(960)
private let avaQuickAvaAiSize = NSSize(width: 430, height: 680)
private let avaQuickAvaAiMargin = CGFloat(16)
private let avaAzoomMessengerSize = NSSize(width: 1344, height: 722)

class MainFlutterWindow: NSWindow {
  private var avaWindowChannel: FlutterMethodChannel?
  private var preAzoomFrame: NSRect?
  private var normalWindowFrame: NSRect?
  private var quickAvaAiHotKeyRef: EventHotKeyRef?
  private var quickAvaAiHotKeyHandler: EventHandlerRef?
  private var quickAvaAiEnabled = false
  private var quickAvaAiWindowMode = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    configureAvaChrome()
    configureAvaWindowChannel(flutterViewController)
    registerQuickAvaAiHotKey()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  deinit {
    unregisterQuickAvaAiHotKey()
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
        self.restoreNormalWindowFrameIfNeeded()
        self.setAvaContentWidth(avaCompactMessengerSize.width)
        result(nil)
      case "showAuthWindow":
        self.restoreNormalWindowFrameIfNeeded()
        self.setAvaContentSize(
          width: avaCompactMessengerSize.width,
          height: avaCompactMessengerSize.height
        )
        self.showAvaWindow()
        result(nil)
      case "expandMessenger":
        self.restoreNormalWindowFrameIfNeeded()
        self.setAvaContentWidth(avaExpandedMessengerWidth)
        self.showAvaWindow()
        result(nil)
      case "showMessengerWindow":
        self.restoreNormalWindowFrameIfNeeded()
        self.showAvaWindow()
        result(nil)
      case "showQuickAvaAiWindow":
        self.showQuickAvaAiWindow()
        result(nil)
      case "setQuickAvaAiEnabled":
        let args = call.arguments as? [String: Any]
        self.quickAvaAiEnabled = args?["enabled"] as? Bool ?? false
        result(nil)
      case "openAzoomMessenger":
        self.restoreNormalWindowFrameIfNeeded()
        if self.preAzoomFrame == nil {
          self.preAzoomFrame = self.frame
        }
        self.setAvaContentSize(
          width: avaAzoomMessengerSize.width,
          height: avaAzoomMessengerSize.height
        )
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
    let currentHeight = contentView?.bounds.height ?? avaCompactMessengerSize.height
    setAvaContentSize(width: width, height: currentHeight)
  }

  private func setAvaContentSize(width: CGFloat, height: CGFloat) {
    let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
    setContentSize(NSSize(width: width, height: height))
    setFrameTopLeftPoint(topLeft)
  }

  private func quickAvaAiFrame() -> NSRect {
    let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame ?? frame
    let margin = avaQuickAvaAiMargin
    let width = min(
      avaQuickAvaAiSize.width,
      max(CGFloat(320), visibleFrame.width - (margin * 2))
    )
    let height = min(
      avaQuickAvaAiSize.height,
      max(CGFloat(420), visibleFrame.height - (margin * 2))
    )
    return NSRect(
      x: visibleFrame.maxX - width - margin,
      y: visibleFrame.minY + margin,
      width: width,
      height: height
    )
  }

  private func quickAvaAiHiddenFrame(from visibleFrame: NSRect) -> NSRect {
    return NSRect(
      x: visibleFrame.minX,
      y: visibleFrame.minY - visibleFrame.height - 24,
      width: visibleFrame.width,
      height: visibleFrame.height
    )
  }

  private func showQuickAvaAiWindow() {
    if !quickAvaAiWindowMode {
      normalWindowFrame = frame
    }
    if isMiniaturized {
      deminiaturize(nil)
    }
    let targetFrame = quickAvaAiFrame()
    setFrame(quickAvaAiHiddenFrame(from: targetFrame), display: false)
    level = .floating
    quickAvaAiWindowMode = true
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      animator().setFrame(targetFrame, display: true)
    }
  }

  private func hideQuickAvaAiWindow() {
    let hiddenFrame = quickAvaAiHiddenFrame(from: frame)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      animator().setFrame(hiddenFrame, display: true)
    } completionHandler: { [weak self] in
      self?.orderOut(nil)
    }
  }

  private func restoreNormalWindowFrameIfNeeded() {
    guard quickAvaAiWindowMode else {
      return
    }
    level = .normal
    if let normalWindowFrame {
      setFrame(normalWindowFrame, display: true, animate: true)
    }
    normalWindowFrame = nil
    quickAvaAiWindowMode = false
  }

  private func showAvaWindow() {
    if isMiniaturized {
      deminiaturize(nil)
    }
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func registerQuickAvaAiHotKey() {
    guard quickAvaAiHotKeyRef == nil else {
      return
    }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let selfPointer = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event, let userData else {
          return noErr
        }
        let window = Unmanaged<MainFlutterWindow>
          .fromOpaque(userData)
          .takeUnretainedValue()
        var hotKeyId = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyId
        )
        guard status == noErr,
              hotKeyId.signature == avaQuickAvaAiHotKeySignature,
              hotKeyId.id == avaQuickAvaAiHotKeyId else {
          return noErr
        }
        window.handleQuickAvaAiHotKey()
        return noErr
      },
      1,
      &eventType,
      selfPointer,
      &quickAvaAiHotKeyHandler
    )

    let hotKeyId = EventHotKeyID(
      signature: avaQuickAvaAiHotKeySignature,
      id: avaQuickAvaAiHotKeyId
    )
    RegisterEventHotKey(
      UInt32(kVK_ANSI_Q),
      UInt32(controlKey),
      hotKeyId,
      GetApplicationEventTarget(),
      0,
      &quickAvaAiHotKeyRef
    )
  }

  private func unregisterQuickAvaAiHotKey() {
    if let quickAvaAiHotKeyRef {
      UnregisterEventHotKey(quickAvaAiHotKeyRef)
      self.quickAvaAiHotKeyRef = nil
    }
    if let quickAvaAiHotKeyHandler {
      RemoveEventHandler(quickAvaAiHotKeyHandler)
      self.quickAvaAiHotKeyHandler = nil
    }
  }

  private func handleQuickAvaAiHotKey() {
    if quickAvaAiWindowMode && isVisible {
      hideQuickAvaAiWindow()
      return
    }
    if quickAvaAiEnabled {
      showQuickAvaAiWindow()
    } else {
      restoreNormalWindowFrameIfNeeded()
      showAvaWindow()
    }
    avaWindowChannel?.invokeMethod("quickAvaAiRequested", arguments: nil)
  }
}
