import Foundation

public enum NewsTeamFilter {
    private static let aliases: [String: [String]] = [
        "76人": ["76人", "七六人"], "独行侠": ["独行侠", "小牛"], "森林狼": ["森林狼", "灰狼"],
        "开拓者": ["开拓者", "拓荒者"], "篮网": ["篮网", "网队"]
    ]
    public static func matches(_ text: String, teams: Set<String>) -> Bool {
        teams.contains { team in (aliases[team] ?? [team]).contains { !$0.isEmpty && text.localizedCaseInsensitiveContains($0) } }
    }
    public static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<(script|style)[^>]*>.*?</\1\s*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
public struct FilteredNews: Sendable {
    public let topics: [ForumTopic]
    public let unavailable: Int
}
public extension ForumService {
    func newsBody(id: String) async throws -> String { NewsTeamFilter.plainText(try await detail(id: id, page: 1).html) }
    /// Classify public articles with bounded concurrency; player names never imply a team.
    func filterNews(_ topics: [ForumTopic], teams: Set<String>) async throws -> FilteredNews {
        guard !teams.isEmpty else { return FilteredNews(topics: [], unavailable: 0) }
        return try await withThrowingTaskGroup(of: (Int, Bool, Bool).self) { group in
            var next = 0, accepted: Set<Int> = [], unavailable = 0
            func enqueue(_ index: Int) {
                let topic = topics[index]
                group.addTask {
                    try Task.checkCancellation()
                    if NewsTeamFilter.matches(topic.title, teams: teams) { return (index, true, false) }
                    do { return (index, NewsTeamFilter.matches(try await newsBody(id: topic.id), teams: teams), false) }
                    catch { try Task.checkCancellation(); return (index, false, true) }
                }
            }
            while next < min(3, topics.count) { enqueue(next); next += 1 }
            while let (index, matches, failed) = try await group.next() {
                if matches { accepted.insert(index) }
                if failed { unavailable += 1 }
                try Task.checkCancellation()
                if next < topics.count { enqueue(next); next += 1 }
            }
            return FilteredNews(topics: topics.enumerated().filter { accepted.contains($0.offset) }.map(\.element), unavailable: unavailable)
        }
    }
}

actor NewsBodyCache {
    static let shared = NewsBodyCache()
    private var values: [String: (Date, String)] = [:]
    func value(_ id: String) -> String? {
        guard let (date, text) = values[id], Date().timeIntervalSince(date) < 600 else { return nil }
        return text
    }
    func put(_ id: String, text: String) {
        if values.count >= 512, let oldest = values.min(by: { $0.value.0 < $1.value.0 })?.key { values.removeValue(forKey: oldest) }
        values[id] = (Date(), text)
    }
}
