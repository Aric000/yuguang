import AppKit
import SwiftUI
import YuguangCore

/// Keep the compact chrome alive while a native popup is tracking outside the window.
struct QuickMatchButton: NSViewRepresentable {
    let model: AppModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "切换比赛、统计或新闻") ?? NSImage()
        let button = NSButton(image: image, target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .labelColor
        button.setAccessibilityLabel("切换比赛、统计或新闻")
        button.toolTip = "切换数据统计 / 主队新闻 / 比赛 / 社区板块 · 保持精简模式"
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
            let stats = NSMenuItem(title: "数据统计", action: #selector(openStats), keyEquivalent: "")
            stats.target = self; stats.isEnabled = model.selectedMatch != nil
            stats.state = model.showingStats ? .on : .off; menu.addItem(stats)
            let news = NSMenuItem(title: "主队新闻列表", action: #selector(openFavoriteNews), keyEquivalent: "")
            news.target = self
            news.state = model.showingForum && model.forum.board?.path == "/502" && model.onlyFavoriteNews ? .on : .off
            menu.addItem(news)
            let teams = NSMenuItem(title: "更改我的主队…", action: #selector(chooseFavoriteTeams), keyEquivalent: "")
            teams.target = self; menu.addItem(teams)
            menu.addItem(.separator())
            let communities = NSMenu(title: "社区板块")
            let favorites = ForumBoard.catalog.filter { board in model.favoriteTeams.contains(where: { board.title.contains($0) }) }
            if !favorites.isEmpty {
                let sub = NSMenu(title: "我的主队")
                for board in favorites { sub.addItem(boardItem(board)) }
                let item = NSMenuItem(title: "我的主队", action: nil, keyEquivalent: "")
                item.submenu = sub; communities.addItem(item); communities.addItem(.separator())
            }
            let categories = ["NBA"] + Array(Set(ForumBoard.catalog.map(\.category))).filter { $0 != "NBA" }.sorted()
            for category in categories {
                let sub = NSMenu(title: category)
                for board in ForumBoard.catalog.filter({ $0.category == category }) { sub.addItem(boardItem(board)) }
                let item = NSMenuItem(title: category, action: nil, keyEquivalent: "")
                item.submenu = sub; communities.addItem(item)
            }
            let communityItem = NSMenuItem(title: "社区板块", action: nil, keyEquivalent: "")
            communityItem.submenu = communities; menu.addItem(communityItem)
            if model.showingForum || model.showingStats {
                let live = NSMenuItem(title: "回到文字直播", action: #selector(returnToLive), keyEquivalent: "")
                live.target = self; menu.addItem(live)
            }
            menu.addItem(.separator())
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
                item.state = !model.showingForum && !model.showingStats && match.id == model.selectedMatch?.id ? .on : .off
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
        private func boardItem(_ board: ForumBoard) -> NSMenuItem {
            let item = NSMenuItem(title: board.title, action: #selector(pickBoard(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = board.path
            item.state = model.showingForum && model.forum.board == board ? .on : .off
            return item
        }
        @objc private func openStats() { model.openStats() }
        @objc private func openFavoriteNews() {
            guard let board = ForumBoard.catalog.first(where: { $0.path == "/502" }) else { return }
            model.onlyFavoriteNews = true
            model.selectBoard(board)
        }
        @objc private func chooseFavoriteTeams() { model.beginTeamSelection() }
        @objc private func pickBoard(_ item: NSMenuItem) {
            guard let path = item.representedObject as? String, let board = ForumBoard.catalog.first(where: { $0.path == path }) else { return }
            model.selectBoard(board)
        }
        @objc private func returnToLive() {
            model.showingStats = false
            model.showingForum = false; model.page = model.selectedMatch == nil ? .matches : .live
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
