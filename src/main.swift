// QuickTranslate —— ⌥D 划词翻译（macOS 原生翻译，零 API）
// 原理：全局热键 ⌥D → 模拟 ⌘C 取选中文本 → 调用快捷指令(系统原生翻译) → 光标旁弹窗显示
import AppKit
import Carbon.HIToolbox
import Vision

// ============ 配置 ============
let kShortcutName = "Bob.Translate.v2"   // 复用系统原生翻译的快捷指令

// 默认热键（用户可在「偏好设置」里自定义，保存到 UserDefaults）
let kDefaultTranslate: (code: UInt32, mods: UInt32) = (UInt32(kVK_ANSI_D), UInt32(optionKey)) // ⌥D
let kDefaultOCR:       (code: UInt32, mods: UInt32) = (UInt32(kVK_ANSI_S), UInt32(optionKey)) // ⌥S

enum HotkeyStore {
    static let translateID: UInt32 = 1
    static let ocrID: UInt32 = 2
    private static let d = UserDefaults.standard

    static func load(_ id: UInt32, _ def: (code: UInt32, mods: UInt32)) -> (code: UInt32, mods: UInt32) {
        if d.object(forKey: "hk.\(id).code") != nil {
            return (UInt32(d.integer(forKey: "hk.\(id).code")), UInt32(d.integer(forKey: "hk.\(id).mods")))
        }
        return def
    }
    static func save(_ id: UInt32, code: UInt32, mods: UInt32) {
        d.set(Int(code), forKey: "hk.\(id).code")
        d.set(Int(mods), forKey: "hk.\(id).mods")
    }
    static func reset() {
        for id in [translateID, ocrID] {
            d.removeObject(forKey: "hk.\(id).code"); d.removeObject(forKey: "hk.\(id).mods")
        }
    }
}

// ============ 热键显示/转换 ============
func carbonFromCocoa(_ f: NSEvent.ModifierFlags) -> UInt32 {
    var m: UInt32 = 0
    if f.contains(.control) { m |= UInt32(controlKey) }
    if f.contains(.option)  { m |= UInt32(optionKey) }
    if f.contains(.shift)   { m |= UInt32(shiftKey) }
    if f.contains(.command) { m |= UInt32(cmdKey) }
    return m
}

let kKeyNames: [UInt32: String] = {
    var m: [UInt32: String] = [:]
    let letters: [(Int, String)] = [
        (kVK_ANSI_A,"A"),(kVK_ANSI_B,"B"),(kVK_ANSI_C,"C"),(kVK_ANSI_D,"D"),(kVK_ANSI_E,"E"),
        (kVK_ANSI_F,"F"),(kVK_ANSI_G,"G"),(kVK_ANSI_H,"H"),(kVK_ANSI_I,"I"),(kVK_ANSI_J,"J"),
        (kVK_ANSI_K,"K"),(kVK_ANSI_L,"L"),(kVK_ANSI_M,"M"),(kVK_ANSI_N,"N"),(kVK_ANSI_O,"O"),
        (kVK_ANSI_P,"P"),(kVK_ANSI_Q,"Q"),(kVK_ANSI_R,"R"),(kVK_ANSI_S,"S"),(kVK_ANSI_T,"T"),
        (kVK_ANSI_U,"U"),(kVK_ANSI_V,"V"),(kVK_ANSI_W,"W"),(kVK_ANSI_X,"X"),(kVK_ANSI_Y,"Y"),(kVK_ANSI_Z,"Z"),
        (kVK_ANSI_0,"0"),(kVK_ANSI_1,"1"),(kVK_ANSI_2,"2"),(kVK_ANSI_3,"3"),(kVK_ANSI_4,"4"),
        (kVK_ANSI_5,"5"),(kVK_ANSI_6,"6"),(kVK_ANSI_7,"7"),(kVK_ANSI_8,"8"),(kVK_ANSI_9,"9"),
        (kVK_Space,"Space"),(kVK_Return,"↩"),(kVK_Tab,"⇥"),(kVK_Escape,"⎋"),(kVK_Delete,"⌫"),
        (kVK_ANSI_Equal,"="),(kVK_ANSI_Minus,"-"),(kVK_ANSI_Slash,"/"),(kVK_ANSI_Period,"."),(kVK_ANSI_Comma,","),
        (kVK_LeftArrow,"←"),(kVK_RightArrow,"→"),(kVK_UpArrow,"↑"),(kVK_DownArrow,"↓"),
        (kVK_F1,"F1"),(kVK_F2,"F2"),(kVK_F3,"F3"),(kVK_F4,"F4"),(kVK_F5,"F5"),(kVK_F6,"F6"),
        (kVK_F7,"F7"),(kVK_F8,"F8"),(kVK_F9,"F9"),(kVK_F10,"F10"),(kVK_F11,"F11"),(kVK_F12,"F12"),
    ]
    for (k, v) in letters { m[UInt32(k)] = v }
    return m
}()

func describeHotkey(code: UInt32, mods: UInt32) -> String {
    var s = ""
    if mods & UInt32(controlKey) != 0 { s += "⌃" }
    if mods & UInt32(optionKey)  != 0 { s += "⌥" }
    if mods & UInt32(shiftKey)   != 0 { s += "⇧" }
    if mods & UInt32(cmdKey)     != 0 { s += "⌘" }
    s += kKeyNames[code] ?? "Key\(code)"
    return s
}

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

// ============ 截图 OCR（系统截图 + Vision 本地识别）============
func captureRegionToFile() -> String? {
    let tmp = NSTemporaryDirectory() + "qt_ocr_\(getpid()).png"
    try? FileManager.default.removeItem(atPath: tmp)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-i", "-x", tmp]   // -i 交互框选, -x 无快门声
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    // 用户按 Esc 取消框选时不会生成文件
    return FileManager.default.fileExists(atPath: tmp) ? tmp : nil
}

func ocrImage(_ path: String) -> String {
    guard let img = NSImage(contentsOfFile: path),
          let tiff = img.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let cg = bitmap.cgImage else { return "" }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = true
    req.recognitionLanguages = ["zh-Hans", "en-US"]
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try? handler.perform([req])
    let obs = req.results ?? []
    let lines = obs.compactMap { $0.topCandidates(1).first?.string }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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

// ============ 全局热键（支持多个，按 id 分发）============
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false

    func unregister(id: UInt32) {
        if let r = refs[id] { UnregisterEventHotKey(r); refs[id] = nil }
        handlers[id] = nil
    }

    @discardableResult
    func register(id: UInt32, code: UInt32, mods: UInt32, action: @escaping () -> Void) -> Bool {
        if !installed { install() }
        unregister(id: id)   // 先注销同 id 的旧热键，支持运行时改键
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x51545254 /* 'QTRT' */), id: id)
        let status = RegisterEventHotKey(code, mods, hkID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr || ref == nil { return false }
        handlers[id] = action
        refs[id] = ref
        return true
    }

    private func install() {
        installed = true
        var et = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                               eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, evt, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(evt, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let id = hkID.id
            DispatchQueue.main.async { HotKeyCenter.shared.handlers[id]?() }
            return noErr
        }, 1, &et, nil, nil)
    }
}

// ============ 热键录制控件 ============
final class HotKeyRecorder: NSButton {
    var onChange: ((UInt32, UInt32) -> Void)?
    private var code: UInt32
    private var mods: UInt32
    private var recording = false

    init(code: UInt32, mods: UInt32) {
        self.code = code; self.mods = mods
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 28))
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(begin)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(code: UInt32, mods: UInt32) { self.code = code; self.mods = mods; refresh() }

    @objc private func begin() {
        recording = true
        title = "请按新快捷键…"
        window?.makeFirstResponder(self)
    }
    override var acceptsFirstResponder: Bool { true }
    override func resignFirstResponder() -> Bool { recording = false; refresh(); return true }

    override func keyDown(with e: NSEvent) {
        guard recording else { super.keyDown(with: e); return }
        if e.keyCode == UInt16(kVK_Escape) {           // Esc 取消录制
            recording = false; refresh(); window?.makeFirstResponder(nil); return
        }
        let m = carbonFromCocoa(e.modifierFlags.intersection([.command, .option, .control, .shift]))
        if m == 0 {                                     // 必须带至少一个修饰键
            title = "需含 ⌘ / ⌥ / ⌃ / ⇧"
            return
        }
        code = UInt32(e.keyCode); mods = m
        recording = false
        refresh()
        window?.makeFirstResponder(nil)
        onChange?(code, mods)
    }
    private func refresh() { title = recording ? "请按新快捷键…" : describeHotkey(code: code, mods: mods) }
}

// ============ 偏好设置窗口 ============
final class SettingsWC: NSWindowController {
    private var translateRec: HotKeyRecorder!
    private var ocrRec: HotKeyRecorder!

    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 210),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "QuickTranslate 偏好设置"
        self.init(window: w)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let t = HotkeyStore.load(HotkeyStore.translateID, kDefaultTranslate)
        let o = HotkeyStore.load(HotkeyStore.ocrID, kDefaultOCR)

        translateRec = HotKeyRecorder(code: t.code, mods: t.mods)
        translateRec.onChange = { c, m in
            HotkeyStore.save(HotkeyStore.translateID, code: c, mods: m)
            (NSApp.delegate as? AppDelegate)?.applyHotkey(id: HotkeyStore.translateID, code: c, mods: m)
        }
        ocrRec = HotKeyRecorder(code: o.code, mods: o.mods)
        ocrRec.onChange = { c, m in
            HotkeyStore.save(HotkeyStore.ocrID, code: c, mods: m)
            (NSApp.delegate as? AppDelegate)?.applyHotkey(id: HotkeyStore.ocrID, code: c, mods: m)
        }

        let title = NSTextField(labelWithString: "全局快捷键")
        title.font = .boldSystemFont(ofSize: 13)
        let tip = NSTextField(labelWithString: "点击右侧按钮，再按下想要的组合键（需含 ⌘/⌥/⌃/⇧）")
        tip.font = .systemFont(ofSize: 11); tip.textColor = .secondaryLabelColor

        let reset = NSButton(title: "恢复默认 (⌥D / ⌥S)", target: self, action: #selector(resetDefaults))
        reset.bezelStyle = .rounded

        let stack = NSStackView(views: [
            title,
            row("划词翻译", translateRec),
            row("截图翻译", ocrRec),
            tip,
            reset,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    private func row(_ label: String, _ rec: HotKeyRecorder) -> NSView {
        let l = NSTextField(labelWithString: label)
        l.font = .systemFont(ofSize: 13)
        l.widthAnchor.constraint(equalToConstant: 80).isActive = true
        rec.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let r = NSStackView(views: [l, rec])
        r.orientation = .horizontal
        r.spacing = 12
        return r
    }

    @objc private func resetDefaults() {
        HotkeyStore.reset()
        translateRec.set(code: kDefaultTranslate.code, mods: kDefaultTranslate.mods)
        ocrRec.set(code: kDefaultOCR.code, mods: kDefaultOCR.mods)
        let d = NSApp.delegate as? AppDelegate
        d?.applyHotkey(id: HotkeyStore.translateID, code: kDefaultTranslate.code, mods: kDefaultTranslate.mods)
        d?.applyHotkey(id: HotkeyStore.ocrID, code: kDefaultOCR.code, mods: kDefaultOCR.mods)
    }
}

// ============ App ============
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let popup = PopupPanel()
    var busy = false
    var settingsWC: SettingsWC?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)   // 无 Dock 图标
        ensureAccessibility()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let icon = loadMenuBarIcon() {
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "译"
        }
        let t = HotkeyStore.load(HotkeyStore.translateID, kDefaultTranslate)
        let o = HotkeyStore.load(HotkeyStore.ocrID, kDefaultOCR)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "QuickTranslate", action: nil, keyEquivalent: ""))
        hintItem = NSMenuItem(title: hintText(t, o), action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "截图翻译 (OCR)", action: #selector(triggerOCR), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "翻译剪贴板内容", action: #selector(translateClipboard), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "偏好设置（自定义快捷键）…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "辅助功能权限设置…", action: #selector(openAXSettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        applyHotkey(id: HotkeyStore.translateID, code: t.code, mods: t.mods)
        applyHotkey(id: HotkeyStore.ocrID, code: o.code, mods: o.mods)
    }

    var hintItem: NSMenuItem!
    func hintText(_ t: (code: UInt32, mods: UInt32), _ o: (code: UInt32, mods: UInt32)) -> String {
        "  \(describeHotkey(code: t.code, mods: t.mods)) 划词   ·   \(describeHotkey(code: o.code, mods: o.mods)) 截图"
    }

    func actionFor(id: UInt32) -> () -> Void {
        if id == HotkeyStore.translateID { return { [weak self] in self?.trigger() } }
        return { [weak self] in self?.triggerOCR() }
    }

    func applyHotkey(id: UInt32, code: UInt32, mods: UInt32) {
        let ok = HotKeyCenter.shared.register(id: id, code: code, mods: mods, action: actionFor(id: id))
        if !ok {
            notify("热键注册失败",
                   "\(describeHotkey(code: code, mods: mods)) 可能被其它软件占用，请在偏好设置里换一个组合键。")
        }
        // 刷新菜单里的提示行
        let t = HotkeyStore.load(HotkeyStore.translateID, kDefaultTranslate)
        let o = HotkeyStore.load(HotkeyStore.ocrID, kDefaultOCR)
        hintItem?.title = hintText(t, o)
    }

    @objc func openSettings() {
        if settingsWC == nil { settingsWC = SettingsWC() }
        NSApp.activate(ignoringOtherApps: true)
        settingsWC?.window?.center()
        settingsWC?.showWindow(nil)
        settingsWC?.window?.makeKeyAndOrderFront(nil)
    }

    func ensureAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// 菜单栏图标：用 app 自己的 logo，缩到 18pt（彩色，非模板）
    func loadMenuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let src = NSImage(contentsOf: url) else { return nil }
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            src.draw(in: rect)
            return true
        }
        img.isTemplate = false
        return img
    }

    @objc func openAXSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func translateClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { notify("剪贴板为空", ""); return }
        runTranslate(text)
    }

    @objc func triggerOCR() {
        if busy { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            // 1. 框选截图（用户 Esc 取消则无文件）
            guard let path = captureRegionToFile() else {
                DispatchQueue.main.async { self.busy = false }
                return
            }
            DispatchQueue.main.async { self.popup.present(original: "识别中…", translation: "翻译中…") }
            // 2. 本地 OCR
            let text = ocrImage(path)
            try? FileManager.default.removeItem(atPath: path)
            if text.isEmpty {
                DispatchQueue.main.async {
                    self.popup.present(original: "", translation: "⚠️ 未识别到文字")
                    self.busy = false
                }
                return
            }
            // 3. 翻译
            let result = nativeTranslate(text)
            DispatchQueue.main.async {
                self.popup.present(original: text, translation: result)
                self.busy = false
            }
        }
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
