import SwiftUI
import Observation
import YuguangCore

@MainActor @Observable
final class AppModel {
    let service: any LiveService
    var days: [GameDay] = []
    var selectedDay = ""
    var teamFilter = "全部球队"
    var favoriteTeams: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "favoriteTeams") ?? []) {
        didSet { UserDefaults.standard.set(Array(favoriteTeams).sorted(), forKey: "favoriteTeams") }
    }
    var selectedMatch: Match?
    var entries: [LiveEntry] = []
    var frozenEntries: [LiveEntry] = []
    var following = true
    var unread = 0
    var loadingSchedule = false
    var loadingLive = false
    var scheduleError: String?
    var matchError: String?
    var textError: String?
    var scoreUpdatedAt: Date?
    var textUpdatedAt: Date?
    var page: Page = .matches {
        didSet { if page != .settings { isRecordingShortcut = false } }
    }
    var compact = false
    var simpleModeEnabled = UserDefaults.standard.bool(forKey: "simpleModeEnabled") {
        didSet {
            UserDefaults.standard.set(simpleModeEnabled, forKey: "simpleModeEnabled")
            if simpleModeEnabled != oldValue { onSimpleModeChange?(simpleModeEnabled) }
        }
    }
    var compactRows = min(6, max(1, UserDefaults.standard.object(forKey: "compactRows") as? Int ?? 1)) {
        didSet { UserDefaults.standard.set(compactRows, forKey: "compactRows"); onWindowChange?() }
    }
    var compactHeight: CGFloat { CGFloat(compactRows) * 32 }
    var compactHovered = false {
        didSet { if compactHovered != oldValue { onWindowChange?() } }
    }
    var compactMenuOpen = false {
        didSet { if compactMenuOpen != oldValue { onWindowChange?() } }
    }
    var compactChromeVisible: Bool { !compact || compactHovered || compactMenuOpen }
    let brandVariant = 1 // B「余光之眼」：已由用户定稿。
    var shortcutError: String?
    var isRecordingShortcut = false
    var shortcut = HotKeySpec.saved
    var theme = UserDefaults.standard.string(forKey: "theme") ?? "system" {
        didSet { UserDefaults.standard.set(theme, forKey: "theme"); onAppearanceChange?() }
    }
    var pinned = UserDefaults.standard.object(forKey: "pinned") as? Bool ?? true {
        didSet { UserDefaults.standard.set(pinned, forKey: "pinned"); onWindowChange?() }
    }
    var scoreOnly = UserDefaults.standard.bool(forKey: "scoreOnly") {
        didSet { UserDefaults.standard.set(scoreOnly, forKey: "scoreOnly") }
    }
    var menuScore = UserDefaults.standard.object(forKey: "menuScore") as? Bool ?? true {
        didSet { UserDefaults.standard.set(menuScore, forKey: "menuScore"); onScoreChange?() }
    }
    var onToggleCompact: (() -> Void)?
    var onSimpleModeChange: ((Bool) -> Void)?
    var onHide: (() -> Void)?
    var onWindowChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    var onScoreChange: (() -> Void)?
    var onShortcutChange: ((HotKeySpec) -> Bool)?
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var schedulePolling: Task<Void, Never>?
    @ObservationIgnored private var scheduleGeneration = 0
    @ObservationIgnored private var selectionGeneration = 0
    @ObservationIgnored private var lastStatusPoll = Date.distantPast
    @ObservationIgnored private var liveKey: String?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored var demo = false

    enum Page { case matches, live, settings }
    init(service: any LiveService = HupuAPI()) { self.service = service }
    var allMatches: [Match] { days.flatMap(\.matchList) }
    var teams: [String] { Set(allMatches.flatMap { [$0.homeTeamName, $0.awayTeamName] }).sorted() }
    var visibleMatches: [Match] {
        switchableMatches.filter { teamFilter == "全部球队" || $0.homeTeamName == teamFilter || $0.awayTeamName == teamFilter }
    }
    /// Quick switching intentionally ignores the full-window team filter.
    var switchableMatches: [Match] {
        let matches = days.first { $0.day == selectedDay }?.matchList ?? []
        return matches.sorted { a, b in
                let af = favoriteTeams.contains(a.homeTeamName) || favoriteTeams.contains(a.awayTeamName)
                let bf = favoriteTeams.contains(b.homeTeamName) || favoriteTeams.contains(b.awayTeamName)
                if af != bf { return af }
                if a.isLive != b.isLive { return a.isLive }
                return a.matchTime < b.matchTime
            }
    }
    var displayedEntries: [LiveEntry] { following ? entries : frozenEntries }
    var latestText: String {
        entries.first?.content ?? (selectedMatch?.isUpcoming == true ? "等待开赛 · \(selectedMatch?.startLabel ?? "")" : "等待文字直播")
    }
    var colorScheme: ColorScheme? { theme == "dark" ? .dark : (theme == "light" ? .light : nil) }
    var connectionError: String? { matchError ?? textError }
    func start() {
        schedulePolling = Task { [weak self] in
            guard let self else { return }
            await refreshSchedule(restore: true)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await refreshSchedule()
            }
        }
    }
    func stop() { polling?.cancel(); schedulePolling?.cancel() }
    func refreshSchedule(restore: Bool = false) async {
        guard !demo else { return }
        scheduleGeneration += 1
        let generation = scheduleGeneration
        loadingSchedule = true
        defer { if generation == scheduleGeneration { loadingSchedule = false } }
        do {
            let data = try await service.schedule()
            guard !Task.isCancelled, generation == scheduleGeneration else { return }
            days = data.gameList
            if !days.contains(where: { $0.day == selectedDay }) {
                selectedDay = data.scheduleListStats?.currentDate ?? days.first?.day ?? ""
                if !days.contains(where: { $0.day == selectedDay }) { selectedDay = days.first?.day ?? "" }
            }
            scheduleError = nil
            if restore, let saved = UserDefaults.standard.string(forKey: "lastMatch"), let match = allMatches.first(where: { $0.id == saved }) {
                select(match)
            }
        } catch {
            guard !Task.isCancelled, generation == scheduleGeneration else { return }
            scheduleError = error.localizedDescription
        }
    }
    func select(_ match: Match) {
        if selectedMatch?.id == match.id { page = .live; return }
        polling?.cancel(); selectionGeneration += 1
        selectedMatch = match; page = .live; entries = []; frozenEntries = []; following = true; unread = 0
        liveKey = nil; failures = 0; lastStatusPoll = .distantPast
        scoreUpdatedAt = nil; textUpdatedAt = nil; matchError = nil; textError = nil
        UserDefaults.standard.set(match.id, forKey: "lastMatch")
        onScoreChange?()
        guard !demo else { return }
        let generation = selectionGeneration
        polling = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await poll(generation: generation)
                guard !Task.isCancelled, generation == selectionGeneration else { return }
                if selectedMatch?.isFinished == true && failures == 0 { return }
                let interval = selectedMatch?.isUpcoming == true ? 30 : 5
                let seconds = failures == 0 ? interval : min(60, 5 * (1 << min(failures, 3)))
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            }
        }
    }
    private func poll(generation: Int) async {
        guard let match = selectedMatch else { return }
        loadingLive = entries.isEmpty
        defer { if generation == selectionGeneration { loadingLive = false } }
        if Date().timeIntervalSince(lastStatusPoll) >= 9 {
            do {
                let update = try await service.match(id: match.id)
                guard !Task.isCancelled, generation == selectionGeneration else { return }
                selectedMatch = update; scoreUpdatedAt = Date(); lastStatusPoll = Date(); matchError = nil
                onScoreChange?()
            } catch {
                guard !Task.isCancelled, generation == selectionGeneration else { return }
                matchError = error.localizedDescription
            }
        }
        guard !Task.isCancelled, generation == selectionGeneration else { return }
        if selectedMatch?.isUpcoming == true {
            textError = nil
            failures = matchError == nil ? 0 : failures + 1
            return
        }
        if selectedMatch?.openLive == false { textError = "本场暂未提供文字直播"; failures = matchError == nil ? 0 : failures + 1; return }
        do {
            let key: String
            if let saved = liveKey { key = saved } else { key = try await service.liveKey(matchID: match.id) }
            guard !Task.isCancelled, generation == selectionGeneration else { return }
            liveKey = key
            let batch = try await service.text(matchID: match.id, key: key)
            guard !Task.isCancelled, generation == selectionGeneration else { return }
            let known = Set(entries.map(\.id))
            let newCount = batch.filter { !known.contains($0.id) }.count
            entries = LiveEntry.merge(batch, into: entries)
            if !following { unread += newCount }
            textUpdatedAt = Date(); textError = nil
        } catch {
            guard !Task.isCancelled, generation == selectionGeneration else { return }
            textError = error.localizedDescription
            liveKey = nil // Renew room credentials after failures; retries back off.
        }
        failures = connectionError == nil ? 0 : failures + 1
    }
    func retryLive() {
        guard let match = selectedMatch, !demo else { return }
        selectedMatch = nil; select(match)
    }
    func toggleFollowing() {
        if following { frozenEntries = entries; following = false } else { following = true; frozenEntries = []; unread = 0 }
    }
    func followLatest() { following = true; frozenEntries = []; unread = 0 }
    func toggleFavorite(_ team: String) {
        if favoriteTeams.contains(team) { favoriteTeams.remove(team) } else { favoriteTeams.insert(team) }
    }
    func applyShortcut(_ spec: HotKeySpec) {
        if onShortcutChange?(spec) == true {
            shortcut = spec; spec.save(); shortcutError = nil
        } else { shortcutError = "快捷键已被占用，原快捷键仍有效。请换一个组合。" }
        isRecordingShortcut = false
    }
    func loadDemo() {
        demo = true
        let sample = #"{"gameList":[{"day":"20261021","dayBlock":"演示比赛日","matchList":[{"matchId":"demo","matchStatus":"INPROGRESS","homeTeamName":"勇士","awayTeamName":"湖人","homeScore":99,"awayScore":102,"matchTime":"2026-10-21 10:00:00","frontEndMatchStatus":{"desc":"第四节 剩2:18"}},{"matchId":"demo-2","matchStatus":"COMPLETED","homeTeamName":"尼克斯","awayTeamName":"76人","homeScore":100,"awayScore":106,"frontEndMatchStatus":{"desc":"已结束"}},{"matchId":"demo-3","matchStatus":"NOTSTARTED","homeTeamName":"马刺","awayTeamName":"雷霆","matchTime":"2026-10-21 11:00:00"}]}]}"#
        if let schedule = try? JSONDecoder().decode(Schedule.self, from: Data(sample.utf8)) {
            days = schedule.gameList; selectedDay = "20261021"
        }
        selectedMatch = Match(matchId: "demo", matchStatus: "INPROGRESS", homeTeamName: "勇士", awayTeamName: "湖人", homeScore: 99, awayScore: 102, status: "第四节 剩2:18")
        entries = [
            LiveEntry(id: "4", content: "詹姆斯突破上篮得分，湖人领先三分。", time: "2026-10-21 10:18:32", nickName: "演示解说"),
            LiveEntry(id: "3", content: "库里借掩护三分出手，球弹筐而出。", time: "2026-10-21 10:18:16", nickName: "演示解说"),
            LiveEntry(id: "2", content: "湖人拿下防守篮板，准备发动反击。", time: "2026-10-21 10:17:58", nickName: "演示解说"),
            LiveEntry(id: "1", content: "暂停结束，比赛继续。", time: "2026-10-21 10:17:40", nickName: "演示解说")
        ]; page = .live; scoreUpdatedAt = Date(); textUpdatedAt = Date()
    }
}
