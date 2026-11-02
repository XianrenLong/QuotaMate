import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers
import UserNotifications

class MainFlutterWindow: NSWindow {
  private var bridge: FlutterMethodChannel!
  private var statusItem: NSStatusItem!
  private var english = false
  override func awakeFromNib() {
    let controller = FlutterViewController()
    contentViewController = controller
    styleMask.insert(.fullSizeContentView)
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    title = "QuotaMate"
    backgroundColor = NSColor(calibratedRed: 0.93, green: 0.925, blue: 0.95, alpha: 1)
    minSize = NSSize(width: 1000, height: 720)
    setContentSize(NSSize(width: 1320, height: 850))
    center()
    isMovableByWindowBackground = true
    isReleasedWhenClosed = false
    RegisterGeneratedPlugins(registry: controller)
    bridge = FlutterMethodChannel(name: "dev.quotamate/native", binaryMessenger: controller.engine.binaryMessenger)
    bridge.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    setupTray()
    super.awakeFromNib()
  }
  private func setupTray() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "QuotaMate")
    statusItem.button?.imagePosition = .imageLeading
    statusItem.button?.title = " GPT"
    updateTrayMenu()
  }
  private func updateTrayMenu() {
    let menu = NSMenu()
    let open = menu.addItem(withTitle: english ? "Open QuotaMate" : "打开 QuotaMate", action: #selector(showWindow), keyEquivalent: "")
    open.target = self
    let refresh = menu.addItem(withTitle: english ? "Refresh limits" : "刷新额度", action: #selector(refreshUsage), keyEquivalent: "")
    refresh.target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: english ? "Quit QuotaMate" : "退出 QuotaMate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    statusItem.menu = menu
  }
  @objc private func showWindow() { makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
  @objc private func refreshUsage() { bridge.invokeMethod("refresh", arguments: nil) }
  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "setAppearance":
      let mode = args["appearance"] as? String ?? "light"
      let selected: NSAppearance? = mode == "dark" ? NSAppearance(named: .darkAqua) : mode == "light" ? NSAppearance(named: .aqua) : nil
      NSApp.appearance = selected
      appearance = selected
      backgroundColor = NSColor.windowBackgroundColor
      result(nil)
    case "setLanguage":
      english = args["language"] as? String == "en"
      updateTrayMenu()
      result(nil)
    case "dragWindow": if let event = NSApp.currentEvent { performDrag(with: event) }; result(nil)
    case "chooseDirectory":
      let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
      panel.prompt = english ? "Choose folder" : "选择数据目录"
      let claude = args["provider"] as? String == "Claude"
      panel.message = claude ? (english ? "Choose a Claude Code configuration folder containing projects" : "选择 Claude Code 配置目录（包含 projects 文件夹）") : (english ? "Choose an existing Codex configuration folder containing sessions" : "选择已有 Codex 配置目录（包含 sessions 文件夹）")
      panel.beginSheetModal(for: self) { response in result(response == .OK ? panel.url?.path : nil) }
    case "chooseExecutable":
      let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
      let claude = args["provider"] as? String == "Claude"
      panel.message = claude ? (english ? "Choose the installed Claude Code executable" : "选择已安装的 Claude Code 可执行文件") : (english ? "Choose the installed Codex executable" : "选择已安装的 Codex 可执行文件")
      panel.beginSheetModal(for: self) { response in result(response == .OK ? panel.url?.path : nil) }
    case "saveCsv":
      let panel = NSSavePanel(); panel.nameFieldStringValue = args["name"] as? String ?? (english ? "GPT-usage.csv" : "GPT-用量统计.csv")
      panel.allowedContentTypes = [.commaSeparatedText]
      panel.beginSheetModal(for: self) { response in
        guard response == .OK, let url = panel.url else { result(nil); return }
        do { try (args["content"] as? String ?? "").write(to: url, atomically: true, encoding: .utf8); result(url.path) }
        catch { result(FlutterError(code: "save", message: self.english ? "Unable to save. Choose another location." : "文件保存失败，请选择其他位置。", details: nil)) }
      }
    case "reveal": if let path = args["path"] as? String { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }; result(nil)
    case "openUrl": if let text = args["url"] as? String, let url = URL(string: text), url.scheme == "https" { NSWorkspace.shared.open(url) }; result(nil)
    case "openCodex":
      let paths = ["/Applications/ChatGPT.app", "/Applications/Codex.app"]
      if let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()) { _, _ in } }; result(nil)
    case "openClaude":
      let paths = ["/Applications/Claude.app", NSHomeDirectory() + "/Applications/Claude.app"]
      if let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()) { _, _ in } }; result(nil)
    case "claudeHelperPath": result(Bundle.main.url(forResource: "quotamate-claude-statusline", withExtension: nil)?.path)
    case "launchClaudeLogin":
      guard let path = args["path"] as? String, path.hasSuffix(".command"), FileManager.default.fileExists(atPath: path) else { result(false); return }
      NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: .init()) { _, error in
        DispatchQueue.main.async { result(error == nil) }
      }
    case "updateTray": statusItem.button?.title = " " + (args["title"] as? String ?? "GPT"); statusItem.button?.toolTip = args["tooltip"] as? String; result(nil)
    case "requestNotifications": UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in DispatchQueue.main.async { result(granted) } }
    case "notify":
      let content = UNMutableNotificationContent(); content.title = args["title"] as? String ?? (english ? "Limit alert" : "额度提醒"); content.body = args["body"] as? String ?? ""
      UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: args["id"] as? String ?? UUID().uuidString, content: content, trigger: nil)); result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }
}
