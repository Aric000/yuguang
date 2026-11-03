import Foundation

public protocol LiveService: Sendable {
    func schedule() async throws -> Schedule
    func match(id: String) async throws -> Match
    func liveKey(matchID: String) async throws -> String
    func text(matchID: String, key: String) async throws -> [LiveEntry]
}

public enum APIError: LocalizedError, Sendable {
    case invalidURL, http(Int), rejected(String), missingResult
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "直播地址无效"
        case .http(let code): "直播服务暂不可用（HTTP \(code)）"
        case .rejected(let message): message.isEmpty ? "直播服务返回异常" : message
        case .missingResult: "直播服务未返回有效数据"
        }
    }
}

public struct HupuAPI: LiveService {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func schedule() async throws -> Schedule {
        try await get(host: "games.mobileapi.hupu.com", path: "/1/7.5.60/basketballapi/scheduleList", query: ["competitionTag": "nba"])
    }
    public func match(id: String) async throws -> Match {
        try await get(host: "games.mobileapi.hupu.com", path: "/1/7.5.60/basketballapi/singleMatch", query: ["matchId": id])
    }
    public func liveKey(matchID: String) async throws -> String {
        let result: LiveKey = try await get(host: "live-api.liangle.com", path: "/1/7.5.60/live/queryLiveActivityKey",
                                           query: ["competitionType": "basketball", "matchId": matchID])
        guard !result.liveActivityKey.isEmpty else { throw APIError.missingResult }
        return result.liveActivityKey
    }
    public func text(matchID: String, key: String) async throws -> [LiveEntry] {
        try await get(host: "live-api.liangle.com", path: "/1/7.5.60/live/queryLiveTextList",
                      query: ["matchId": matchID, "liveActivityKeyStr": key])
    }
    public func playerStats(matchID: String, teamID: String) async throws -> PlayerStatsResponse {
        try await get(host: "games.mobileapi.hupu.com", path: "/1/7.5.29/basketballapi/teamMatchRosterScoreStats",
                      query: ["matchId": matchID, "teamId": teamID, "userId": ""])
    }
    public static func url(host: String, path: String, query: [String: String]) throws -> URL {
        var c = URLComponents(); c.scheme = "https"; c.host = host; c.path = path
        c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = c.url else { throw APIError.invalidURL }
        return url
    }
    private func get<T: Decodable & Sendable>(host: String, path: String, query: [String: String]) async throws -> T {
        let url = try Self.url(host: host, path: path, query: query)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw APIError.missingResult }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return try Self.decode(T.self, from: data)
    }
    public static func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(ResponseStatus.self, from: data)
        if envelope.success == false || (envelope.status != nil && envelope.status != 200) {
            throw APIError.rejected(envelope.errorMsg ?? envelope.msg ?? "")
        }
        guard let result = try decoder.decode(Envelope<T>.self, from: data).result else { throw APIError.missingResult }
        return result
    }
}

private struct Envelope<T: Decodable>: Decodable {
    let result: T?
}

private struct ResponseStatus: Decodable {
    let status: Int?
    let success: Bool?
    let errorMsg: String?
    let msg: String?
}

public struct PlayerStatsResponse: Decodable, Sendable {
    public let players: [PlayerStatsEntry]
}
public struct PlayerStatsEntry: Decodable, Sendable {
    public let stats: PlayerGameStats?
}
public struct PlayerGameStats: Decodable, Sendable, Identifiable {
    public let playerId: String
    public let name: String
    public let mins: String?
    public let pts: Int?
    public let reb: Int?
    public let asts: Int?
    public let stl: Int?
    public let blk: Int?
    public let plusMinus: String?
    public var id: String { playerId }
    enum CodingKeys: String, CodingKey {
        case playerId, name, mins, pts, reb, asts, stl, blk, plusMinus
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.stringOrInteger(.playerId)
        name = try c.decode(String.self, forKey: .name)
        mins = try c.decodeIfPresent(String.self, forKey: .mins)
        pts = try c.decodeIfPresent(Int.self, forKey: .pts)
        reb = try c.decodeIfPresent(Int.self, forKey: .reb)
        asts = try c.decodeIfPresent(Int.self, forKey: .asts)
        stl = try c.decodeIfPresent(Int.self, forKey: .stl)
        blk = try c.decodeIfPresent(Int.self, forKey: .blk)
        plusMinus = try c.decodeIfPresent(String.self, forKey: .plusMinus)
    }
}
