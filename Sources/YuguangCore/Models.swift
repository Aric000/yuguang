import Foundation

public struct Match: Decodable, Identifiable, Hashable, Sendable {
    public let matchId: String
    public var matchStatus: String
    public let homeTeamName: String
    public let awayTeamName: String
    public var homeScore: Int?
    public var awayScore: Int?
    public let matchTime: String
    public var frontEndMatchStatus: DisplayStatus?
    public let openLive: Bool?
    public let homeTeamLogo: String?
    public let awayTeamLogo: String?
    public let homeTeamDayColor: String?
    public let awayTeamDayColor: String?
    public let homeTeamNightColor: String?
    public let awayTeamNightColor: String?
    public let competitionStageDesc: String?
    public var id: String { matchId }
    public var isLive: Bool { matchStatus == "INPROGRESS" }
    public var isFinished: Bool { matchStatus == "COMPLETED" }
    public var isUpcoming: Bool { matchStatus == "NOTSTARTED" }
    public var title: String { "\(awayTeamName) vs \(homeTeamName)" }
    public var score: String {
        isUpcoming ? "vs" : "\(awayScore.map(String.init) ?? "—") : \(homeScore.map(String.init) ?? "—")"
    }
    public var status: String {
        if let description = frontEndMatchStatus?.desc, !description.isEmpty { return description }
        return isLive ? "进行中" : (isFinished ? "已结束" : (isUpcoming ? "未开始" : "赛程待定"))
    }
    public var startLabel: String {
        guard matchTime.count >= 16 else { return matchTime }
        return String(matchTime.dropFirst(5).prefix(11))
    }
    public init(matchId: String, matchStatus: String, homeTeamName: String, awayTeamName: String,
                homeScore: Int? = nil, awayScore: Int? = nil, matchTime: String = "", status: String? = nil) {
        self.matchId = matchId; self.matchStatus = matchStatus
        self.homeTeamName = homeTeamName; self.awayTeamName = awayTeamName
        self.homeScore = homeScore; self.awayScore = awayScore; self.matchTime = matchTime
        self.frontEndMatchStatus = status.map { DisplayStatus(desc: $0) }; self.openLive = true
        self.homeTeamLogo = nil; self.awayTeamLogo = nil
        self.homeTeamDayColor = nil; self.awayTeamDayColor = nil
        self.homeTeamNightColor = nil; self.awayTeamNightColor = nil; self.competitionStageDesc = nil
    }
    enum CodingKeys: String, CodingKey {
        case matchId, matchStatus, homeTeamName, awayTeamName, homeScore, awayScore, matchTime, frontEndMatchStatus, openLive
        case homeTeamLogo, awayTeamLogo, homeTeamDayColor, awayTeamDayColor, homeTeamNightColor, awayTeamNightColor, competitionStageDesc
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matchId = try c.stringOrInteger(.matchId)
        matchStatus = try c.decode(String.self, forKey: .matchStatus)
        homeTeamName = try c.decode(String.self, forKey: .homeTeamName)
        awayTeamName = try c.decode(String.self, forKey: .awayTeamName)
        homeScore = try c.decodeIfPresent(Int.self, forKey: .homeScore)
        awayScore = try c.decodeIfPresent(Int.self, forKey: .awayScore)
        matchTime = try c.decodeIfPresent(String.self, forKey: .matchTime) ?? ""
        frontEndMatchStatus = try c.decodeIfPresent(DisplayStatus.self, forKey: .frontEndMatchStatus)
        openLive = try c.decodeIfPresent(Bool.self, forKey: .openLive)
        homeTeamLogo = try c.decodeIfPresent(String.self, forKey: .homeTeamLogo)
        awayTeamLogo = try c.decodeIfPresent(String.self, forKey: .awayTeamLogo)
        homeTeamDayColor = try c.decodeIfPresent(String.self, forKey: .homeTeamDayColor)
        awayTeamDayColor = try c.decodeIfPresent(String.self, forKey: .awayTeamDayColor)
        homeTeamNightColor = try c.decodeIfPresent(String.self, forKey: .homeTeamNightColor)
        awayTeamNightColor = try c.decodeIfPresent(String.self, forKey: .awayTeamNightColor)
        competitionStageDesc = try c.decodeIfPresent(String.self, forKey: .competitionStageDesc)
    }
}

public struct DisplayStatus: Decodable, Hashable, Sendable { public let desc: String? }
public struct Schedule: Decodable, Sendable {
    public let gameList: [GameDay]
    public let scheduleListStats: ScheduleStats?
    public var matches: [Match] { gameList.flatMap(\.matchList) }
}
public struct GameDay: Decodable, Sendable {
    public let day: String
    public let dayBlock: String?
    public let matchList: [Match]
}
public struct ScheduleStats: Decodable, Sendable { public let currentDate: String? }
public struct LiveKey: Decodable, Sendable { public let liveActivityKey: String }

public struct LiveEntry: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let content: String
    public let time: String
    public let nickName: String
    public var clock: String { time.count >= 19 ? String(time.suffix(8)) : time }
    enum CodingKeys: String, CodingKey { case commentId, content, time, nickName }
    public init(id: String, content: String, time: String, nickName: String = "") {
        self.id = id; self.content = content; self.time = time; self.nickName = nickName
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .content)
        content = Self.plainText(raw)
        time = try c.decodeIfPresent(String.self, forKey: .time) ?? ""
        nickName = try c.decodeIfPresent(String.self, forKey: .nickName) ?? ""
        id = (try? c.stringOrInteger(.commentId)) ?? "\(time)|\(raw)"
    }
    public static func plainText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Incoming batches are newest first. Never sort comment IDs: they are not chronological.
    public static func merge(_ incoming: [LiveEntry], into existing: [LiveEntry], limit: Int = 500) -> [LiveEntry] {
        var seen = Set<String>()
        return Array((incoming + existing).filter { seen.insert($0.id).inserted }.prefix(limit))
    }
}

extension KeyedDecodingContainer {
    func stringOrInteger(_ key: Key) throws -> String {
        if let s = try? decode(String.self, forKey: key) { return s }
        return String(try decode(Int64.self, forKey: key))
    }
}
