import Testing
import Foundation
@testable import YuguangCore

struct CoreTests {
    @Test func compactHistoryKeepsPositionAcrossNewBatches() {
        let original = (0..<5).map { LiveEntry(id: "\($0)", content: "message \($0)", time: "", nickName: "") }
        var history = CompactHistory()
        history.move(1, live: original)
        #expect(history.isReading)
        #expect(history.visibleEntries(original).first?.id == "1")
        let incoming = [LiveEntry(id: "new", content: "new message", time: "", nickName: "")] + original
        #expect(history.visibleEntries(incoming).first?.id == "1")
        #expect(history.unreadCount(incoming) == 1)
        history.move(500, live: incoming)
        #expect(history.visibleEntries(incoming).first?.id == "4")
        history.move(-500, live: incoming)
        #expect(!history.isReading)
        #expect(history.visibleEntries(incoming).first?.id == "new")
        #expect(history.unreadCount(incoming) == 0)
        history.scroll(5.5, live: original, visibleRows: 3)
        #expect(history.position == 5.5 && history.offset == 0 && history.remainder == 5.5)
        #expect(history.visibleEntries(incoming).first?.id == "0")
        history.scroll(500, live: incoming, visibleRows: 3)
        #expect(history.position == 64 && history.visibleEntries(incoming).count == 3)
        history.scroll(-500, live: incoming, visibleRows: 3)
        #expect(!history.isReading)
        history.scroll(10, live: original, visibleRows: 6)
        #expect(!history.isReading)
        history.move(1, live: [])
        #expect(!history.isReading)
        history.move(1, live: Array(original.prefix(1)))
        #expect(!history.isReading)
    }
    @Test func testTeamVisualIdentityFromAPI() throws {
        let data = Data(#"{"result":{"matchId":"123","matchStatus":"INPROGRESS","homeTeamName":"勇士","awayTeamName":"湖人","homeTeamLogo":"http://example.com/warriors.png","awayTeamDayColor":"552583","homeTeamNightColor":"FFC72C","competitionStageDesc":"常规赛"}}"#.utf8)
        let match = try HupuAPI.decode(Match.self, from: data)
        #expect(match.homeTeamLogo == "http://example.com/warriors.png")
        #expect(match.awayTeamDayColor == "552583")
        #expect(match.homeTeamNightColor == "FFC72C")
        #expect(match.competitionStageDesc == "常规赛")
    }
    @Test func testCurrentEnvelopeAndLargeNumericIDs() throws {
        let json = #"{"status":200,"success":true,"result":{"matchId":1537445624050352128,"matchStatus":"INPROGRESS","homeTeamName":"尼克斯","awayTeamName":"76人","homeScore":86,"awayScore":93,"frontEndMatchStatus":{"desc":"第四节 剩6:49"}}}"#
        let match = try HupuAPI.decode(Match.self, from: Data(json.utf8))
        #expect(match.id == "1537445624050352128")
        #expect(match.score == "93 : 86")
        #expect(match.status == "第四节 剩6:49")
    }
    @Test func testUpcomingDoesNotInventZeroScores() {
        let upcoming = Match(matchId: "1", matchStatus: "NOTSTARTED", homeTeamName: "湖人", awayTeamName: "勇士")
        #expect(upcoming.score == "vs")
        let live = Match(matchId: "1", matchStatus: "INPROGRESS", homeTeamName: "湖人", awayTeamName: "勇士", awayScore: 0)
        #expect(live.score == "0 : —")
    }
    @Test func testRoomKeyEncodesExactlyOnce() throws {
        let key = "79668677:1495229:1034001&x=+/?"
        let url = try HupuAPI.url(host: "live-api.liangle.com", path: "/live", query: ["liveActivityKeyStr": key, "matchId": "123"])
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first(where: { $0.name == "liveActivityKeyStr" })?.value == key)
        #expect(items?.count == 2)
    }
    @Test func testFailureEnvelopeIsNotAnEmptySuccess() {
        let json = #"{"status":403,"success":false,"errorMsg":"直播参数失效","result":null}"#
        do {
            _ = try HupuAPI.decode(LiveKey.self, from: Data(json.utf8))
            Issue.record("A rejected room key must throw")
        } catch { #expect(error.localizedDescription == "直播参数失效") }
    }
    @Test func testMissingResultFails() {
        #expect(throws: (any Error).self) { try HupuAPI.decode(LiveKey.self, from: Data(#"{"status":200,"result":null}"#.utf8)) }
    }
    @Test func testRejectionMessageSurvivesDifferentResultShape() {
        let json = #"{"status":403,"success":false,"msg":"直播参数已过期","result":{"reason":"expired"}}"#
        do {
            _ = try HupuAPI.decode([LiveEntry].self, from: Data(json.utf8))
            Issue.record("A rejected response must throw")
        } catch { #expect(error.localizedDescription == "直播参数已过期") }
    }
    @Test func testEmptyTextBatchIsValid() throws {
        let entries = try HupuAPI.decode([LiveEntry].self, from: Data(#"{"result":[],"status":200}"#.utf8))
        #expect(entries.isEmpty)
    }
    @Test func testCommentIDsDoNotDetermineChronologyAndOverlapIsDeduplicated() {
        func entry(_ id: String) -> LiveEntry { LiveEntry(id: id, content: id, time: "") }
        let merged = LiveEntry.merge([entry("2"), entry("99"), entry("7")], into: [entry("7"), entry("30")])
        #expect(merged.map(\.id) == ["2", "99", "7", "30"])
        #expect(LiveEntry.merge([], into: merged, limit: 2).map(\.id) == ["2", "99"])
    }
    @Test func testPlainTextRemovesMarkupWithoutInterpretingScripts() throws {
        let data = Data(#"{"commentId":3009442805,"content":"<b>三分</b><br/>命中 &amp; 得分","time":"2026-10-21 09:36:55","nickName":"解说"}"#.utf8)
        let entry = try JSONDecoder().decode(LiveEntry.self, from: data)
        #expect(entry.id == "3009442805")
        #expect(entry.content == "三分 命中 & 得分")
        #expect(entry.clock == "09:36:55")
    }
    @Test func testScheduleWithOptionalMetadata() throws {
        let schedule = try HupuAPI.decode(Schedule.self, from: Data(#"{"result":{"gameList":[{"day":"20261021","matchList":[]}]}}"#.utf8))
        #expect(schedule.gameList.count == 1)
        #expect(schedule.matches.isEmpty)
    }
}
