import Testing
import Foundation
@testable import YuguangCore

struct ForumTests {
    private let topic = #"{"tid":"643170471","title":"a } brace and \"quote\"","replies":305,"createdAt":1792721635000,"author":{"puname":"JR"},"createdAtFormat":"刚刚"}"#
    @Test func publicSSRExtractionAndDuplicatePosts() throws {
        let html = "<script>window.$$data={\"topic\":{\"threads\":{\"current\":2,\"total\":20,\"list\":[\(topic),\(topic)]}}}; console.log(1)</script>"
        let result = try HupuForum.parseTopics(html)
        #expect(result.current == 2 && result.total == 20)
        #expect(result.topics.count == 1)
        #expect(result.topics.first?.title == "a } brace and \"quote\"")
        #expect(result.topics.first?.replies == 305)
        #expect(result.topics.first?.createdAt == 1792721635000)
        #expect(HupuForum.unique(result.topics + result.topics).count == 1)
    }
    @Test func nextDataCommentsRespectHiddenAndDuplicateFlags() throws {
        let html = #"<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"detail":{"thread":{"title":"test","content":"<p>body</p>","author":{"puname":"author"}},"replies":{"current":2,"total":16,"list":[{"pid":"a","content":"secret","isHidden":true},{"pid":"a","content":"duplicate"},{"pid":"b","content":"<p>reply</p>","author":{"puname":"JR"}}]}}}}}</script>"#
        let detail = try HupuForum.parseDetail(html)
        #expect(detail.current == 2 && detail.total == 16)
        #expect(detail.comments.count == 2)
        #expect(detail.comments.first?.html == "<p>此评论不可见</p>")
        #expect(detail.comments.last?.author == "JR")
    }
    @Test func challengeAndUnexpectedPagesFailInsteadOfEmptySuccess() {
        #expect(throws: (any Error).self) { try HupuForum.parseTopics("<html>请验证</html>") }
        #expect(throws: (any Error).self) { try HupuForum.parseDetail("<script>window.$$data={\"topic\":{}};</script>") }
        #expect(throws: (any Error).self) { try HupuForum.parseTopics("<script>window.$$data={broken</script>") }
    }
    @Test func catalogIncludesRequestedBoardsWithUniquePaths() {
        #expect(ForumBoard.catalog.contains { $0.title == "篮球资讯" && $0.path == "/502" })
        #expect(ForumBoard.catalog.contains { $0.title == "骑士专区" && $0.path == "/cavaliers" })
        #expect(ForumBoard.catalog.contains { $0.title == "步行街主干道" })
        #expect(Set(ForumBoard.catalog.map(\.id)).count == ForumBoard.catalog.count)
    }
    @Test func teamMatchingUsesMultipleTeamsAndKnownAliases() {
        #expect(NewsTeamFilter.matches("独行侠逆转", teams: ["湖人", "独行侠"]))
        #expect(NewsTeamFilter.matches("小牛赢球", teams: ["独行侠"]))
        #expect(!NewsTeamFilter.matches("湖人比赛", teams: []))
        #expect(!NewsTeamFilter.matches("湖人比赛", teams: ["骑士"]))
        #expect(!NewsTeamFilter.matches(NewsTeamFilter.plainText("<img src='湖人.jpg'><p>骑士比赛</p>"), teams: ["湖人"]))
    }
    @Test func highlightedAndNormalCommentsAreMergedAndRanked() throws {
        let html = #"<script id="__NEXT_DATA__">{"props":{"pageProps":{"detail":{"thread":{"title":"test","content":"body"},"lights":[{"pid":"hot","allLightCount":42},{"pid":"overlap","allLightCount":20}],"replies":{"current":1,"total":2,"list":[{"pid":"overlap","allLightCount":25},{"pid":"low","allLightCount":0},{"pid":"missing"}]}}}}}</script>"#
        let detail = try HupuForum.parseDetail(html)
        #expect(detail.comments.map(\.id) == ["hot", "overlap", "low", "missing"])
        #expect(detail.comments.map(\.likes) == [42, 25, 0, 0])
    }

}
