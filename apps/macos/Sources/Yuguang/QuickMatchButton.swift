import AppKit
import SwiftUI
import YuguangCore

/// Keep the compact chrome alive while a native popup is tracking outside the window.
struct QuickMatchButton: NSViewRepresentable {
    let model: AppModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "切换比赛") ?? NSImage()
        let button = NSButton(image: image, target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .labelColor
        button.setAccessibilityLabel("切换比赛")
        button.toolTip = "切换比赛 · 保持精简模式"
        return button
    }
    func updateNSView(_ view: NSButton, context: Context) {}

    @MainActor final class Coordinator: NSObject {
        let model: AppModel
        private var matches: [String: Match] = [:]
        init(model: AppModel) { self.model = model }
        @objc func open(_ sender: NSButton) {
            model.compactMenuOpen = true
            defer {
                model.compactMenuOpen = false
                model.compactHovered = sender.window?.frame.contains(NSEvent.mouseLocation) ?? false
            }
            let menu = NSMenu()
            let title = NSMenuItem(title: model.days.first(where: { $0.day == model.selectedDay })?.dayBlock ?? "比赛", action: nil, keyEquivalent: "")
            title.isEnabled = false; menu.addItem(title)
            matches = Dictionary(model.switchableMatches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            if model.switchableMatches.isEmpty {
                let empty = NSMenuItem(title: model.loadingSchedule ? "正在获取赛程…" : "这一天暂无比赛", action: nil, keyEquivalent: "")
                empty.isEnabled = false; menu.addItem(empty)
            }
            for match in model.switchableMatches {
                let title = "\(match.awayTeamName) \(match.score) \(match.homeTeamName) · \(match.isUpcoming ? match.startLabel : match.status)"
                let item = NSMenuItem(title: title, action: #selector(pickMatch(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = match.id
                item.state = match.id == model.selectedMatch?.id ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let dates = NSMenu(title: "比赛日期")
            for day in model.days {
                let item = NSMenuItem(title: day.dayBlock ?? day.day, action: #selector(pickDate(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = day.day
                item.state = day.day == model.selectedDay ? .on : .off
                dates.addItem(item)
            }
            let datesItem = NSMenuItem(title: "比赛日期", action: nil, keyEquivalent: "")
            datesItem.submenu = dates; menu.addItem(datesItem)
            let refresh = NSMenuItem(title: "刷新赛程", action: #selector(refreshSchedule), keyEquivalent: "")
            refresh.target = self; menu.addItem(refresh)
            let y = sender.isFlipped ? sender.bounds.maxY + 4 : sender.bounds.minY - 4
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: sender)
        }
        @objc private func pickMatch(_ item: NSMenuItem) {
            guard let id = item.representedObject as? String, let match = matches[id] else { return }
            model.select(match)
        }
        @objc private func pickDate(_ item: NSMenuItem) {
            if let day = item.representedObject as? String { model.selectedDay = day }
        }
        @objc private func refreshSchedule() { Task { await model.refreshSchedule() } }
    }
}
