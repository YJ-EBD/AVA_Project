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
private let avaChatNotificationSize = NSSize(width: 310, height: 132)
private let avaChatNotificationMargin = CGFloat(18)

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var avaWindowChannel: FlutterMethodChannel?
  private var preAzoomFrame: NSRect?
  private var normalWindowFrame: NSRect?
  private var quickAvaAiHotKeyRef: EventHotKeyRef?
  private var quickAvaAiHotKeyHandler: EventHandlerRef?
  private var quickAvaAiEnabled = false
  private var quickAvaAiWindowMode = false
  private var statusItem: NSStatusItem?
  private var exitRequested = false
  private var activeNotification: AvaChatNotificationController?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    delegate = self
    configureAvaChrome()
    configureAvaStatusItem()
    configureAvaWindowChannel(flutterViewController)
    registerQuickAvaAiHotKey()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  deinit {
    unregisterQuickAvaAiHotKey()
    if let statusItem {
      NSStatusBar.system.removeStatusItem(statusItem)
    }
  }

  private func configureAvaChrome() {
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true
  }

  private func configureAvaStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "AVA"
    item.button?.toolTip = "AVA"

    let menu = NSMenu()
    let openItem = NSMenuItem(title: "열기", action: #selector(openFromStatusItem), keyEquivalent: "")
    openItem.target = self
    menu.addItem(openItem)

    let lockItem = NSMenuItem(title: "잠금모드 설정", action: #selector(lockFromStatusItem), keyEquivalent: "")
    lockItem.target = self
    menu.addItem(lockItem)

    let logoutItem = NSMenuItem(title: "로그아웃", action: #selector(logoutFromStatusItem), keyEquivalent: "")
    logoutItem.target = self
    menu.addItem(logoutItem)

    menu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(title: "종료", action: #selector(quitFromStatusItem), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)

    item.menu = menu
    statusItem = item
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
        self.hideToStatusItem()
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
      case "showChatNotification":
        self.showChatNotification(arguments: call.arguments)
        result(true)
      default:
        result(nil)
      }
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if exitRequested {
      return true
    }
    hideToStatusItem()
    return false
  }

  @objc private func openFromStatusItem() {
    invokeTrayAction("open")
  }

  @objc private func lockFromStatusItem() {
    invokeTrayAction("lock")
  }

  @objc private func logoutFromStatusItem() {
    invokeTrayAction("logout")
  }

  @objc private func quitFromStatusItem() {
    exitRequested = true
    activeNotification?.dismiss(animated: false)
    NSApp.terminate(nil)
  }

  private func invokeTrayAction(_ action: String) {
    restoreNormalWindowFrameIfNeeded()
    showAvaWindow()
    avaWindowChannel?.invokeMethod("trayMenuAction", arguments: ["action": action])
  }

  private func hideToStatusItem() {
    if quickAvaAiWindowMode {
      hideQuickAvaAiWindow()
      return
    }
    if isMiniaturized {
      deminiaturize(nil)
    }
    orderOut(nil)
    NSApp.setActivationPolicy(.accessory)
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
    NSApp.setActivationPolicy(.regular)
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
    NSApp.setActivationPolicy(.regular)
    makeKeyAndOrderFront(nil)
    orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
  }

  private func showChatNotification(arguments: Any?) {
    guard let args = arguments as? [String: Any] else {
      return
    }

    let roomId = args["roomId"] as? String ?? ""
    guard !roomId.isEmpty else {
      return
    }

    activeNotification?.dismiss(animated: false)
    let controller = AvaChatNotificationController(
      roomId: roomId,
      roomTitle: args["roomTitle"] as? String ?? "AVA",
      senderName: args["senderName"] as? String ?? "",
      senderNickname: args["senderNickname"] as? String ?? "",
      avatarColor: args["avatarColor"] as? String ?? "#5B6CFF",
      body: args["body"] as? String ?? "",
      onOpen: { [weak self] openedRoomId in
        self?.openNotificationRoom(openedRoomId)
      },
      onReply: { [weak self] repliedRoomId, content in
        self?.sendNotificationReply(roomId: repliedRoomId, content: content)
      },
      onDismiss: { [weak self] in
        self?.activeNotification = nil
      }
    )
    activeNotification = controller
    controller.show(on: screen ?? NSScreen.main)
  }

  private func openNotificationRoom(_ roomId: String) {
    restoreNormalWindowFrameIfNeeded()
    showAvaWindow()
    avaWindowChannel?.invokeMethod(
      "floatingAction",
      arguments: ["action": "openRoom", "roomId": roomId]
    )
  }

  private func sendNotificationReply(roomId: String, content: String) {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return
    }
    avaWindowChannel?.invokeMethod(
      "notificationReply",
      arguments: ["roomId": roomId, "content": trimmed]
    )
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

private final class AvaChatNotificationController {
  private let roomId: String
  private let onOpen: (String) -> Void
  private let onReply: (String, String) -> Void
  private let onDismiss: () -> Void
  private var closeTimer: Timer?
  private var window: AvaChatNotificationWindow?

  init(
    roomId: String,
    roomTitle: String,
    senderName: String,
    senderNickname: String,
    avatarColor: String,
    body: String,
    onOpen: @escaping (String) -> Void,
    onReply: @escaping (String, String) -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.roomId = roomId
    self.onOpen = onOpen
    self.onReply = onReply
    self.onDismiss = onDismiss

    let view = AvaChatNotificationView(
      roomTitle: roomTitle,
      senderName: senderName,
      senderNickname: senderNickname,
      avatarColor: avatarColor,
      body: body
    )
    view.onClose = { [weak self] in
      self?.dismiss(animated: true)
    }
    view.onOpen = { [weak self] in
      guard let self else {
        return
      }
      self.onOpen(self.roomId)
      self.dismiss(animated: true)
    }
    view.onReply = { [weak self] content in
      guard let self else {
        return
      }
      self.onReply(self.roomId, content)
      self.dismiss(animated: true)
    }
    view.onMouseEntered = { [weak self] in
      self?.closeTimer?.invalidate()
      self?.closeTimer = nil
    }
    view.onMouseExited = { [weak self] in
      self?.scheduleAutoDismiss()
    }

    let notificationWindow = AvaChatNotificationWindow(
      contentRect: NSRect(origin: .zero, size: avaChatNotificationSize),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    notificationWindow.contentView = view
    notificationWindow.isOpaque = false
    notificationWindow.backgroundColor = .clear
    notificationWindow.hasShadow = true
    notificationWindow.level = .floating
    notificationWindow.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
    self.window = notificationWindow
  }

  func show(on screen: NSScreen?) {
    guard let window else {
      return
    }
    let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(
      x: 0,
      y: 0,
      width: 1440,
      height: 900
    )
    let targetFrame = NSRect(
      x: visibleFrame.maxX - avaChatNotificationSize.width - avaChatNotificationMargin,
      y: visibleFrame.minY + avaChatNotificationMargin,
      width: avaChatNotificationSize.width,
      height: avaChatNotificationSize.height
    )
    let hiddenFrame = targetFrame.offsetBy(dx: 0, dy: -(avaChatNotificationSize.height + 24))
    window.setFrame(hiddenFrame, display: false)
    window.alphaValue = 0
    window.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      window.animator().setFrame(targetFrame, display: true)
      window.animator().alphaValue = 1
    }
    scheduleAutoDismiss()
  }

  func dismiss(animated: Bool) {
    closeTimer?.invalidate()
    closeTimer = nil
    guard let window else {
      onDismiss()
      return
    }

    let complete = { [weak self] in
      window.orderOut(nil)
      self?.window = nil
      self?.onDismiss()
    }

    if animated {
      let hiddenFrame = window.frame.offsetBy(dx: 0, dy: -(window.frame.height + 24))
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.14
        window.animator().setFrame(hiddenFrame, display: true)
        window.animator().alphaValue = 0
      } completionHandler: {
        complete()
      }
    } else {
      complete()
    }
  }

  private func scheduleAutoDismiss() {
    closeTimer?.invalidate()
    closeTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
      self?.dismiss(animated: true)
    }
  }
}

private final class AvaChatNotificationWindow: NSWindow {
  override var canBecomeKey: Bool {
    return true
  }

  override var canBecomeMain: Bool {
    return false
  }
}

private final class AvaChatNotificationView: NSView, NSTextFieldDelegate {
  var onClose: (() -> Void)?
  var onOpen: (() -> Void)?
  var onReply: ((String) -> Void)?
  var onMouseEntered: (() -> Void)?
  var onMouseExited: (() -> Void)?

  private let avatarView = NSView()
  private let roomLabel = NSTextField(labelWithString: "")
  private let senderLabel = NSTextField(labelWithString: "")
  private let bodyLabel = NSTextField(wrappingLabelWithString: "")
  private let replyField = NSTextField()
  private let closeButton = NSButton(title: "×", target: nil, action: nil)
  private let sendButton = NSButton(title: "전송", target: nil, action: nil)
  private var trackingAreaRef: NSTrackingArea?

  init(
    roomTitle: String,
    senderName: String,
    senderNickname: String,
    avatarColor: String,
    body: String
  ) {
    super.init(frame: NSRect(origin: .zero, size: avaChatNotificationSize))
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor

    let displaySender = senderNickname.isEmpty ? senderName : senderNickname
    roomLabel.stringValue = roomTitle.isEmpty ? "AVA" : roomTitle
    senderLabel.stringValue = displaySender.isEmpty ? "AVA" : displaySender
    bodyLabel.stringValue = body
    avatarView.wantsLayer = true
    avatarView.layer?.cornerRadius = 17
    avatarView.layer?.backgroundColor = NSColor.avaColor(hex: avatarColor).cgColor

    configureLabel(roomLabel, font: .boldSystemFont(ofSize: 13), color: .labelColor)
    configureLabel(senderLabel, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
    configureLabel(bodyLabel, font: .systemFont(ofSize: 12), color: .labelColor)
    bodyLabel.maximumNumberOfLines = 2

    closeButton.isBordered = false
    closeButton.font = .systemFont(ofSize: 15, weight: .semibold)
    closeButton.target = self
    closeButton.action = #selector(closePressed)

    replyField.delegate = self
    replyField.placeholderString = "메시지 입력"
    replyField.font = .systemFont(ofSize: 12)
    replyField.isBezeled = true
    replyField.bezelStyle = .roundedBezel
    replyField.focusRingType = .none

    sendButton.bezelStyle = .rounded
    sendButton.font = .systemFont(ofSize: 12, weight: .semibold)
    sendButton.target = self
    sendButton.action = #selector(sendPressed)

    addSubview(avatarView)
    addSubview(roomLabel)
    addSubview(senderLabel)
    addSubview(bodyLabel)
    addSubview(replyField)
    addSubview(sendButton)
    addSubview(closeButton)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingAreaRef {
      removeTrackingArea(trackingAreaRef)
    }
    let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
    let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
    addTrackingArea(area)
    trackingAreaRef = area
  }

  override func layout() {
    super.layout()
    let inset = CGFloat(12)
    let buttonSize = CGFloat(22)
    avatarView.frame = NSRect(x: inset, y: bounds.height - 46, width: 34, height: 34)
    closeButton.frame = NSRect(
      x: bounds.width - inset - buttonSize,
      y: bounds.height - inset - buttonSize,
      width: buttonSize,
      height: buttonSize
    )
    roomLabel.frame = NSRect(
      x: avatarView.frame.maxX + 9,
      y: bounds.height - 30,
      width: bounds.width - avatarView.frame.maxX - 46,
      height: 16
    )
    senderLabel.frame = NSRect(
      x: roomLabel.frame.minX,
      y: bounds.height - 47,
      width: roomLabel.frame.width,
      height: 14
    )
    bodyLabel.frame = NSRect(
      x: inset,
      y: 45,
      width: bounds.width - (inset * 2),
      height: 36
    )
    sendButton.frame = NSRect(
      x: bounds.width - inset - 54,
      y: inset,
      width: 54,
      height: 25
    )
    replyField.frame = NSRect(
      x: inset,
      y: inset,
      width: sendButton.frame.minX - inset - 8,
      height: 25
    )
  }

  override func draw(_ dirtyRect: NSRect) {
    let rect = bounds.insetBy(dx: 1, dy: 1)
    let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
    NSColor.windowBackgroundColor.withAlphaComponent(0.98).setFill()
    path.fill()
    NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
    path.lineWidth = 1
    path.stroke()
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if point.y > 40 {
      onOpen?()
    } else {
      super.mouseDown(with: event)
    }
  }

  override func mouseEntered(with event: NSEvent) {
    onMouseEntered?()
  }

  override func mouseExited(with event: NSEvent) {
    onMouseExited?()
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    if commandSelector == #selector(NSResponder.insertNewline(_:)) {
      sendPressed()
      return true
    }
    return false
  }

  @objc private func closePressed() {
    onClose?()
  }

  @objc private func sendPressed() {
    let content = replyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else {
      return
    }
    onReply?(content)
  }

  private func configureLabel(_ label: NSTextField, font: NSFont, color: NSColor) {
    label.font = font
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    label.backgroundColor = .clear
    label.isBordered = false
    label.isEditable = false
    label.isSelectable = false
  }
}

private extension NSColor {
  static func avaColor(hex: String) -> NSColor {
    let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
      return NSColor.systemIndigo
    }
    return NSColor(
      calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1
    )
  }
}
