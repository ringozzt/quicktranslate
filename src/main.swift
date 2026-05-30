// QuickTranslate —— ⌥D 划词翻译（macOS 原生翻译，零 API）
// 原理：全局热键 ⌥D → 模拟 ⌘C 取选中文本 → 调用快捷指令(系统原生翻译) → 光标旁弹窗显示
import AppKit
import Carbon.HIToolbox

// ============ 配置 ============
let kShortcutName = "Bob.Translate.v2"   // 复用系统原生翻译的快捷指令
let kHotKeyCode   = UInt32(kVK_ANSI_D)   // D
let kHotKeyMods   = UInt32(optionKey)    // ⌥ Option

// ============ 翻译方向判断 ============
func isMostlyCJK(_ s: String) -> Bool {
    var cjk = 0, latin = 0
    for u in s.unicodeScalars {
        switch u.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3040...0x30FF, 0xAC00...0xD7AF:
            cjk += 1
        case 0x41...0x5A, 0x61...0x7A:
            latin += 1
        default: break
        }
    }
    return cjk > latin
}

// ============ 调用原生翻译 ============
func nativeTranslate(_ text: String) -> String {
    let target = isMostlyCJK(text) ? "en_US" : "zh_CN"
    let payload: [String: String] = ["text": text, "detectFrom": "", "detectTo": target]
    guard let json = try? JSONSerialization.data(withJSONObject: payload) else { return "(编码失败)" }

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
    p.arguments = ["run", kShortcutName]
    let inPipe = Pipe(), outPipe = Pipe()
    p.standardInput = inPipe
    p.standardOutput = outPipe
    p.standardError = outPipe
    do { try p.run() } catch { return "(无法启动 shortcuts)" }
    inPipe.fileHandleForWriting.write(json)
    try? inPipe.fileHandleForWriting.close()
    let out = outPipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    var s = String(data: out, encoding: .utf8) ?? ""
    s = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("Error:") {
        return "⚠️ " + s.replacingOccurrences(of: "Error:", with: "").trimmingCharacters(in: .whitespaces)
    }
    return s.isEmpty ? "(无翻译结果)" : s
}

// ============ 取选中文本（模拟 ⌘C）============
func copySelectedText() -> String {
    let pb = NSPasteboard.general
    let prevCount = pb.changeCount
    let src = CGEventSource(stateID: .combinedSessionState)
    let cDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
    cDown?.flags = .maskCommand
    let cUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
    cUp?.flags = .maskCommand
    cDown?.post(tap: .cghidEventTap)
    cUp?.post(tap: .cghidEventTap)
    // 轮询等待剪贴板更新，最多 ~450ms
    var waited = 0
    while pb.changeCount == prevCount && waited < 45 {
        usleep(10_000); waited += 1
    }
    return pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

// ============ 弹窗 ============
final class PopupPanel: NSPanel {
    private let origLabel = NSTextField(wrappingLabelWithString: "")
    private let transLabel = NSTextField(wrappingLabelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "点击译文可复制 · Esc 关闭")
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var currentTranslation = ""

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true

        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.state = .active
        bg.blendingMode = .behindWindow
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true

        origLabel.font = .systemFont(ofSize: 12)
        origLabel.textColor = .secondaryLabelColor
        origLabel.maximumNumberOfLines = 3

        transLabel.font = .systemFont(ofSize: 16, weight: .medium)
        transLabel.textColor = .labelColor
        transLabel.isSelectable = true

        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabelColor

        let sep = NSBox(); sep.boxType = .separator

        let stack = NSStackView(views: [origLabel, sep, transLabel, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView = bg
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bg.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
            origLabel.widthAnchor.constraint(equalToConstant: 388),
            transLabel.widthAnchor.constraint(equalToConstant: 388),
        ])

        // 点击译文复制
        let click = NSClickGestureRecognizer(target: self, action: #selector(copyTranslation))
        transLabel.addGestureRecognizer(click)
    }

    @objc private func copyTranslation() {
        guard !currentTranslation.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentTranslation, forType: .string)
        hintLabel.stringValue = "✓ 已复制到剪贴板"
        hintLabel.textColor = .systemGreen
    }

    func present(original: String, translation: String) {
        origLabel.stringValue = original
        transLabel.stringValue = translation
        currentTranslation = translation.hasPrefix("⚠️") ? "" : translation
        hintLabel.stringValue = "点击译文可复制 · Esc 关闭"
        hintLabel.textColor = .tertiaryLabelColor
        layoutIfNeeded()

        let fitting = (contentView?.fittingSize) ?? NSSize(width: 420, height: 120)
        let w: CGFloat = 420
        let h = max(80, fitting.height)
        var origin = NSEvent.mouseLocation
        origin.x += 12
        origin.y -= (h + 12)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let vis = screen.visibleFrame
            origin.x = min(max(vis.minX + 8, origin.x), vis.maxX - w - 8)
            origin.y = min(max(vis.minY + 8, origin.y), vis.maxY - h - 8)
        }
        setFrame(NSRect(x: origin.x, y: origin.y, width: w, height: h), display: true)
        orderFrontRegardless()
        installDismissMonitors()
    }

    private func installDismissMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] e in
            if e.type == .keyDown && e.keyCode == UInt16(kVK_Escape) { self?.dismiss(); return nil }
            return e
        }
    }
    private func removeMonitors() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
    }
    func dismiss() { removeMonitors(); orderOut(nil) }
    override var canBecomeKey: Bool { true }
}

// ============ 全局热键 ============
final class HotKey {
    private var ref: EventHotKeyRef?
    private let onFire: () -> Void
    init?(code: UInt32, mods: UInt32, onFire: @escaping () -> Void) {
        self.onFire = onFire
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, evt, ctx -> OSStatus in
            guard let ctx = ctx else { return noErr }
            let me = Unmanaged<HotKey>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { me.onFire() }
            _ = evt
            return noErr
        }, 1, &eventType, selfPtr, nil)

        let hkID = EventHotKeyID(signature: OSType(0x51545254 /* 'QTRT' */), id: 1)
        let status = RegisterEventHotKey(code, mods, hkID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { return nil }
    }
    deinit { if let r = ref { UnregisterEventHotKey(r) } }
}

// ============ App ============
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var hotKey: HotKey?
    let popup = PopupPanel()
    var busy = false

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)   // 无 Dock 图标
        ensureAccessibility()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "译"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "QuickTranslate · ⌥D 划词翻译", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "翻译剪贴板内容", action: #selector(translateClipboard), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "辅助功能权限设置…", action: #selector(openAXSettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        hotKey = HotKey(code: kHotKeyCode, mods: kHotKeyMods) { [weak self] in self?.trigger() }
        if hotKey == nil { notify("热键注册失败", "⌥D 可能被占用") }
    }

    func ensureAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    @objc func openAXSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func translateClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { notify("剪贴板为空", ""); return }
        runTranslate(text)
    }

    func trigger() {
        if busy { return }
        let text = copySelectedText()
        if text.isEmpty {
            popup.present(original: "", translation: "⚠️ 没取到选中文本（请确认已授予辅助功能权限）")
            return
        }
        runTranslate(text)
    }

    func runTranslate(_ text: String) {
        busy = true
        popup.present(original: text, translation: "翻译中…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = nativeTranslate(text)
            DispatchQueue.main.async {
                self?.popup.present(original: text, translation: result)
                self?.busy = false
            }
        }
    }

    func notify(_ title: String, _ body: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = body; a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
