import AppKit
import SwiftUI
import YuguangCore

final class LivePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let model = AppModel()
    let hotKey = HotKeyManager()
    private var panel: LivePanel?
    private var statusItem: NSStatusItem?
    private var changingFrame = false
    private var expandedFrame = NSRect(x: 180, y: 240, width: 400, height: 580)
    private var compactFrame = NSRect(x: 180, y: 240, width: 640, height: 32)
    private var menuTitle: NSMenuItem?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private let diagnosticKeys = ["lastMatch", "pinned", "compactRows", "simpleModeEnabled", "theme", "expandedFrame", "compactFrame"]
    private var diagnosticPreferences: [String: Any]?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--capture") {
            diagnosticPreferences = Dictionary(uniqueKeysWithValues: diagnosticKeys.compactMap { key in
                UserDefaults.standard.object(forKey: key).map { (key, $0) }
            })
        }
        NSApp.setActivationPolicy(.accessory)
        let demo = CommandLine.arguments.contains("--demo")
        if demo { model.loadDemo() }
        let window = LivePanel(contentRect: expandedFrame, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.title = "余光"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.acceptsMouseMovedEvents = true
        window.hasShadow = true // A native floating window, not a resting content card.
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.contentView = NSHostingView(rootView: RootView(model: model))
        panel = window
        monitorPointer()
        restoreFrames()
        model.onToggleCompact = { [weak self] in self?.toggleCompact() }
        model.onSimpleModeChange = { [weak self] enabled in
            guard let self, self.model.compact != enabled else { return }
            self.toggleCompact()
        }
        model.onHide = { [weak self] in self?.hide() }
        model.onWindowChange = { [weak self] in self?.updateWindow() }
        model.onAppearanceChange = { [weak self] in self?.updateWindow() }
        model.onScoreChange = { [weak self] in self?.updateStatus() }
        model.onShortcutChange = { [weak self] spec in self?.hotKey.register(spec) ?? false }
        hotKey.onPress = { [weak self] in
            guard let self, !self.model.isRecordingShortcut else { return }
            self.toggleVisibility()
        }
        if !hotKey.register(model.shortcut) {
            model.shortcutError = "全局快捷键注册失败。请在设置里选择其他组合，或从菜单栏隐藏和恢复。"
        }
        setupMenu()
        updateWindow()
        changingFrame = true
        window.setFrame(clamped(expandedFrame), display: true)
        changingFrame = false
        if model.simpleModeEnabled { toggleCompact() }
        show()
        if !demo { model.start() }
        if CommandLine.arguments.contains("--self-test") {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                self?.runWindowChecks()
            }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--capture"), CommandLine.arguments.count > index + 1 {
            let directory = CommandLine.arguments[index + 1]
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.captureAll(to: directory)
                NSApp.terminate(nil)
            }
        }
    }
    private func setupMenu() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu(title: "余光")
        appMenu.addItem(menuItem("偏好设置…", action: #selector(openSettings), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("退出余光", action: #selector(quit), key: "q"))
        let appItem = NSMenuItem(); appItem.submenu = appMenu
        mainMenu.addItem(appItem); NSApp.mainMenu = mainMenu
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = BrandRenderer.menuIcon()
        item.button?.imagePosition = .imageLeading
        item.button?.setAccessibilityLabel("余光菜单")
        statusItem = item
        let menu = NSMenu(); menu.delegate = self
        let title = NSMenuItem(title: "余光 · 安静地看一场球", action: nil, keyEquivalent: "")
        title.isEnabled = false; menuTitle = title; menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(menuItem("显示 / 隐藏直播", action: #selector(toggleFromMenu)))
        menu.addItem(menuItem("选择比赛", action: #selector(chooseMatch)))
        menu.addItem(menuItem("精简 / 展开", action: #selector(compactFromMenu)))
        menu.addItem(menuItem("偏好设置…", action: #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出余光", action: #selector(quit), key: "q"))
        item.menu = menu
        updateStatus()
    }
    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; return item
    }
    func menuWillOpen(_ menu: NSMenu) {
        menuTitle?.title = model.selectedMatch.map { "\($0.title) · \($0.status)" } ?? "余光 · 安静地看一场球"
    }
    private func updateStatus() {
        if model.menuScore, let match = model.selectedMatch {
            statusItem?.button?.title = " \(match.awayTeamName) \(match.score) \(match.homeTeamName)"
            statusItem?.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        } else {
            statusItem?.button?.title = ""
        }
        statusItem?.button?.toolTip = "余光 · \(model.shortcut.label) 隐藏 / 恢复"
    }
    private func updateWindow() {
        guard let panel else { return }
        let previousFrame = panel.frame
        panel.level = model.pinned ? .floating : .normal
        panel.hasShadow = model.compactChromeVisible
        panel.appearance = model.theme == "system" ? nil : NSAppearance(named: model.theme == "dark" ? .darkAqua : .aqua)
        panel.minSize = model.compact ? NSSize(width: 360, height: model.compactHeight) : NSSize(width: 360, height: 460)
        panel.maxSize = model.compact ? NSSize(width: 1200, height: model.compactHeight) : NSSize(width: 620, height: 1000)
        if model.compact && previousFrame.height != model.compactHeight {
            var frame = previousFrame
            frame.origin.y = previousFrame.maxY - model.compactHeight
            frame.size.height = model.compactHeight
            panel.setFrame(clamped(frame), display: true)
        }
    }
    private func monitorPointer() {
        // A fully transparent window can pass mouse events to the app beneath it.
        // Observe both local and other-app mouse motion so the entire rectangle can wake up.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .rightMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointer(event) }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointer(event) }
        }
    }
    private func updatePointer(_ event: NSEvent) {
        guard let panel, model.compact, panel.isVisible else { return }
        let location = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
        model.compactHovered = panel.frame.contains(location)
    }
    func toggleCompact() {
        guard let panel else { return }
        if model.compact { compactFrame = panel.frame } else { expandedFrame = panel.frame }
        model.isRecordingShortcut = false
        model.compact.toggle()
        updateWindow()
        changingFrame = true
        var destination = model.compact ? compactFrame : expandedFrame
        if model.compact { destination.size.height = model.compactHeight }
        // Keep the current upper-left corner when changing shape.
        destination.origin.x = panel.frame.minX
        destination.origin.y = panel.frame.maxY - destination.height
        panel.setFrame(clamped(destination), display: true)
        model.compactHovered = panel.frame.contains(NSEvent.mouseLocation)
        changingFrame = false
        saveFrame()
    }
    private func clamped(_ proposed: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(proposed) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return proposed }
        var frame = proposed
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }
    private func restoreFrames() {
        if let value = UserDefaults.standard.string(forKey: "expandedFrame") {
            let rect = NSRectFromString(value)
            if rect.width >= 360, rect.height >= 460 { expandedFrame = rect }
        } else if let screen = NSScreen.main {
            expandedFrame.origin = NSPoint(x: screen.visibleFrame.maxX - 424, y: screen.visibleFrame.maxY - 620)
        }
        if let value = UserDefaults.standard.string(forKey: "compactFrame") {
            let rect = NSRectFromString(value)
            if rect.width >= 360 { compactFrame = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: model.compactHeight) }
        }
    }
    private func saveFrame() {
        guard !changingFrame, let panel else { return }
        if model.compact { compactFrame = panel.frame } else { expandedFrame = panel.frame }
        UserDefaults.standard.set(NSStringFromRect(expandedFrame), forKey: "expandedFrame")
        UserDefaults.standard.set(NSStringFromRect(compactFrame), forKey: "compactFrame")
    }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { saveFrame() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
    func applicationDidChangeScreenParameters(_ notification: Notification) {
        if let panel { panel.setFrame(clamped(panel.frame), display: true) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show(); return true
    }
    private func show() {
        if let panel { model.compactHovered = panel.frame.contains(NSEvent.mouseLocation) }
        NSApp.unhide(nil); panel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func hide() { model.isRecordingShortcut = false; panel?.orderOut(nil); NSApp.hide(nil) }
    private func toggleVisibility() { if panel?.isVisible == true { hide() } else { show() } }
    @objc private func toggleFromMenu() { toggleVisibility() }
    @objc private func compactFromMenu() { if model.selectedMatch != nil { toggleCompact() }; show() }
    @objc private func chooseMatch() {
        if model.compact { toggleCompact() }
        model.page = .matches; show()
    }
    @objc private func openSettings() {
        if model.compact { toggleCompact() }
        model.page = .settings; show()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        saveFrame(); model.stop(); hotKey.stop()
        restoreDiagnosticPreferences()
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
    }

    private func restoreDiagnosticPreferences() {
        guard let diagnosticPreferences else { return }
        for key in diagnosticKeys {
            if let value = diagnosticPreferences[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    private func runWindowChecks() {
        guard let panel else { exit(1) }
        let preferredSimpleMode = model.simpleModeEnabled
        if model.compact { toggleCompact() }
        let preferredRows = model.compactRows
        model.compactRows = 1
        func check(_ condition: Bool, _ name: String) {
            guard condition else { print("FAIL: \(name)"); restoreDiagnosticPreferences(); exit(1) }
            print("PASS: \(name)")
        }
        check(model.shortcutError == nil, "Carbon global hotkey registered")
        check(model.brandVariant == 1 && statusItem?.button?.image?.isTemplate == true, "Official B logo is always present as a template menu icon")
        check(TeamAssets.catalog.count == 30 && TeamAssets.catalog.keys.allSatisfy { TeamAssets.image($0) != nil }, "All 30 team crests load from the bundled catalog")
        check(panel.isVisible && panel.frame.height >= 460, "Expanded window visible")
        if let content = panel.contentView {
            content.layoutSubtreeIfNeeded()
            let original = panel.frame
            let start = NSPoint(x: 100, y: original.height - 24)
            let hit = content.hitTest(content.superview?.convert(start, from: nil) ?? start)
            check(hit is DragView, "Expanded title routes pointer events to the native drag surface")
            if let drag = hit as? DragView {
                func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
                    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                       windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
                                       clickCount: 1, pressure: 1)!
                }
                drag.mouseDown(with: event(.leftMouseDown, start))
                drag.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: start.x + 30, y: start.y - 20)))
                check(panel.frame.origin == NSPoint(x: original.minX + 30, y: original.minY - 20), "Expanded title dragging moves the window")
                drag.mouseUp(with: event(.leftMouseUp, start))
                panel.setFrame(original, display: true)
            }
        }
        let filter = model.teamFilter
        model.teamFilter = "湖人"
        check(model.switchableMatches.count > model.visibleMatches.count, "Quick switch includes other teams despite full-window filter")
        model.teamFilter = filter
        toggleCompact()
        let saved = panel.frame
        check(model.compact && panel.frame.height == 32, "Compact window is 32 pt")
        model.compactRows = 3
        check(panel.frame.height == 96 && panel.frame.maxY == saved.maxY, "Three rows resize to 96 pt and preserve top edge")
        if let alternate = model.switchableMatches.first(where: { $0.id != model.selectedMatch?.id }) {
            let before = panel.frame
            model.select(alternate)
            check(model.compact && panel.frame == before && model.selectedMatch?.id == alternate.id, "Quick match selection keeps compact mode, size and position")
        }
        model.compactRows = 6
        check(panel.frame.height == 192, "Six rows resize to 192 pt")
        model.compactRows = 1
        model.compactHovered = false
        check(!model.compactChromeVisible && !panel.hasShadow, "Pointer outside removes compact chrome and shadow")
        model.compactHovered = true
        check(model.compactChromeVisible && panel.hasShadow, "Pointer inside restores compact chrome and shadow")
        hide()
        check(!panel.isVisible, "Hide removes window immediately")
        show()
        check(panel.isVisible && model.compact && panel.frame == saved, "Restore preserves compact shape and position")
        toggleCompact()
        check(!model.compact && panel.frame.height >= 460, "Expand restores reading window")
        model.compactHovered = false
        check(model.compactChromeVisible && panel.hasShadow, "Expanded window keeps chrome without hover")
        model.pinned = false
        check(panel.level == .normal, "Unpin uses normal window level")
        model.pinned = true
        check(panel.level == .floating, "Pin uses floating window level")
        model.simpleModeEnabled = false
        model.simpleModeEnabled = true
        check(model.compact, "Enabling simple mode immediately enters the text-only compact view")
        toggleCompact()
        check(!model.compact && model.simpleModeEnabled, "Temporary expansion preserves the simple-mode preference and hides team crests")
        model.simpleModeEnabled = false
        check(!model.compact, "Disabling simple mode restores the full window")
        print("Window checks complete")
        model.compactRows = preferredRows
        model.simpleModeEnabled = preferredSimpleMode
        NSApp.terminate(nil)
    }

    private func captureAll(to directory: String) {
        guard let panel else { return }
        let preferredRows = model.compactRows
        let preferredTheme = model.theme
        let preferredSimpleMode = model.simpleModeEnabled
        if model.compact { toggleCompact() }
        model.simpleModeEnabled = false
        model.compactRows = 1
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        func capture(_ name: String) {
            guard let view = panel.contentView else { return }
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
            }
        }
        // Native screenshots: render actual SwiftUI views, never a separate HTML mockup.
        model.theme = "light"; model.page = .live
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)); capture("live-light")
        model.theme = "dark"
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)); capture("live-dark")
        model.theme = "light"; model.page = .settings
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)); capture("settings")
        model.page = .matches
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)); capture("matches")
        model.page = .live
        changingFrame = true
        let original = panel.frame
        panel.setFrame(NSRect(x: original.minX, y: original.minY, width: 360, height: 580), display: true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)); capture("live-narrow")
        panel.setFrame(NSRect(x: original.minX, y: original.minY, width: 620, height: 640), display: true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)); capture("live-wide")
        panel.setFrame(original, display: true); changingFrame = false
        model.simpleModeEnabled = true
        if model.compact { toggleCompact() }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)); capture("simple-window")
        model.simpleModeEnabled = false
        model.page = .live; toggleCompact()
        model.compactHovered = true
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)); capture("compact")
        model.compactHovered = false
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)); capture("compact-text-only")
        model.compactRows = 3; model.compactHovered = true
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)); capture("compact-multiline")
        model.compactHovered = false
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)); capture("compact-multiline-transparent")
        model.compactRows = preferredRows
        model.theme = preferredTheme
        model.simpleModeEnabled = preferredSimpleMode
    }
}

@main enum YuguangApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--check-api") {
            Task {
                do {
                    let api = HupuAPI()
                    let schedule = try await api.schedule()
                    print("赛程：\(schedule.gameList.count) 天，\(schedule.matches.count) 场")
                    guard let match = schedule.matches.first(where: \.isLive) ?? schedule.matches.first(where: \.isFinished) else { throw APIError.missingResult }
                    async let key = api.liveKey(matchID: match.id)
                    let detail = try await api.match(id: match.id)
                    let entries = try await api.text(matchID: match.id, key: key)
                    print("比赛：\(detail.title) · \(detail.score) · \(detail.status)")
                    print("文字：\(entries.count) 条；最新：\(entries.first?.content ?? "暂无")")
                    exit(0)
                } catch { fputs("接口验证失败：\(error.localizedDescription)\n", stderr); exit(1) }
            }
            RunLoop.main.run()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
