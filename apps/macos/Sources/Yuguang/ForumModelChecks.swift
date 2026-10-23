import Foundation
import YuguangCore

/// Deterministic model checks, independent of Hupu availability.
@MainActor enum ForumModelChecks {
    static func run() async throws {
        let keys = ["forumReadIDs", "favoriteTeams", "onlyFavoriteNews"]
        let saved = Dictionary(uniqueKeysWithValues: keys.compactMap { key in UserDefaults.standard.object(forKey: key).map { (key, $0) } })
        defer {
            for key in keys {
                if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let service = FixtureForumService()
        let model = ForumModel(service: service)
        let slow = ForumBoard(category: "test", title: "slow", path: "/slow")
        let fast = ForumBoard(category: "test", title: "fast", path: "/fast")
        func check(_ value: Bool, _ title: String) throws {
            guard value else { throw NSError(domain: "ForumModelChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: title]) }
            print("PASS: \(title)")
        }
        func waitList() async { while model.loading { try? await Task.sleep(for: .milliseconds(10)) } }
        model.choose(slow)
        try? await Task.sleep(for: .milliseconds(10))
        model.choose(fast)
        await waitList()
        try? await Task.sleep(for: .milliseconds(100))
        try check(model.board == fast && model.topics.first?.id == "2", "切换板块后忽略旧请求")
        model.loadMore(); model.loadMore(); await waitList()
        try check(model.current == 2 && model.topics.map(\.id) == ["2", "3", "4"], "重叠分页去重，同一页只请求一次")
        let count = await service.calls
        try check(count == 3, "分页请求 single flight")
        model.changeSort(.replies)
        try check(model.ordered.first?.id == "4", "回复最多使用已加载数据")
        model.scrollID = "3"
        if let topic = model.topics.first {
            model.open(topic)
            while model.detailLoading { try? await Task.sleep(for: .milliseconds(10)) }
            try check(model.detail != nil && model.readIDs.contains(topic.id), "成功打开后标记已读")
            model.back()
            try check(model.selected == nil && model.scrollID == "3" && model.topics.count == 3, "返回列表保留位置和数据")
        }
        model.refresh(); await waitList()
        try check(model.current == 1 && model.scrollID == nil && model.topics.count == 2, "刷新重新从第一页开始")
        let news = ForumBoard(category: "NBA", title: "篮球资讯", path: "/502")
        model.configureFavorites(["湖人", "勇士"], onlyNews: true)
        model.choose(news); await waitList()
        try check(model.topics.map(\.id) == ["2"], "主队新闻通过正文识别，排除无关球队")
        model.loadMore(); await waitList()
        try check(model.topics.map(\.id) == ["2", "4"], "多个主队按任意匹配，分页不重复")
        if let topic = model.topics.first {
            model.open(topic)
            while model.detailLoading { try? await Task.sleep(for: .milliseconds(10)) }
            try check(model.detail?.comments.map(\.likes) == [20, 5], "评论初始按高亮数降序")
            model.fetchDetail(page: 2)
            while model.detailLoading { try? await Task.sleep(for: .milliseconds(10)) }
            try check(model.detail?.comments.map(\.likes) == [30, 20, 8], "更多评论累计去重并更新高亮数、重排")
        }
        model.configureFavorites([], onlyNews: true)
        try check(model.needsFavoriteTeams && !model.loading && model.topics.isEmpty, "未选主队时明确提示设置，不回退为全部资讯")
        model.configureFavorites([], onlyNews: false); await waitList()
        try check(model.topics.map(\.id) == ["2", "3"], "关闭主队筛选后显示全部资讯")
        model.stop()
        let batched = ForumModel(service: BatchNewsFixture(), favoriteTeams: ["湖人"], onlyFavoriteNews: true)
        batched.choose(news)
        while batched.loading { try? await Task.sleep(for: .milliseconds(10)) }
        try check(batched.topics.count == 12 && batched.hasMore && batched.current == 1, "主队资讯分小批筛选，未处理记录不会丢失")
        batched.loadMore()
        while batched.loading { try? await Task.sleep(for: .milliseconds(10)) }
        try check(batched.topics.count == 24 && !batched.hasMore && batched.current == 1, "同一来源页的剩余资讯能继续加载且不重复")
        batched.stop()
        let scrolling = ForumModel(service: ScrollNewsFixture(), favoriteTeams: ["湖人"], onlyFavoriteNews: true)
        scrolling.choose(news)
        while scrolling.loading { try? await Task.sleep(for: .milliseconds(10)) }
        try? await Task.sleep(for: .milliseconds(150))
        try check(scrolling.topics.count == 12 && scrolling.processedNews == 12, "离开底部时不自动遍历后续批次")
        scrolling.updateListBoundary(nearEnd: true)
        if let topic = scrolling.topics.first { scrolling.open(topic) }
        try? await Task.sleep(for: .milliseconds(150))
        try check(scrolling.processedNews == 12, "阅读详情时停止列表自动加载")
        scrolling.back()
        let deadline = Date(timeIntervalSinceNow: 4)
        while (scrolling.hasMore || scrolling.loading) && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        try check(scrolling.current == 3 && !scrolling.hasMore && scrolling.topics.count == 36,
                  "底部保持可见时连续跨页加载，穿过多个无匹配批次")
        try check(Set(scrolling.topics.map(\.id)).count == scrolling.topics.count,
                  "连续自动加载时重叠帖子仍去重")
        scrolling.stop()
        UserDefaults.standard.removeObject(forKey: "onlyFavoriteNews")
        let settings = AppModel()
        try check(settings.onlyFavoriteNews, "首次使用默认只看主队新闻")
        settings.favoriteTeams = ["湖人", "骑士"]; settings.onlyFavoriteNews = false
        let restored = AppModel()
        try check(restored.favoriteTeams == ["湖人", "骑士"] && !restored.onlyFavoriteNews, "多个主队和资讯筛选偏好可保存、恢复")
        settings.onlyFavoriteNews = true
        try check(settings.forum.onlyFavoriteNews && settings.forum.favoriteTeams == settings.favoriteTeams, "设置修改即时同步社区筛选")
        let before = settings.favoriteTeams
        settings.beginTeamSelection(); settings.toggleDraftTeam("勇士")
        try check(settings.choosingFavoriteTeams && settings.favoriteTeamDraft.contains("勇士") && settings.favoriteTeams == before,
                  "主队弹窗使用草稿，多选时不立即改变已保存主队")
        settings.cancelTeamSelection()
        try check(!settings.choosingFavoriteTeams && settings.favoriteTeams == before, "取消主队弹窗保留原选择")
        settings.beginTeamSelection(); settings.toggleDraftTeam("勇士"); settings.saveTeamSelection()
        try check(!settings.choosingFavoriteTeams && settings.favoriteTeams == before.union(["勇士"]) && AppModel().favoriteTeams == settings.favoriteTeams,
                  "完成主队弹窗后统一保存多个选择")
    }
}

private actor FixtureForumService: ForumService {
    var calls = 0
    func topics(board: ForumBoard, page: Int) async throws -> ForumPage {
        calls += 1
        // Deliberately ignore cancellation to exercise generation protection.
        try? await Task.sleep(for: .milliseconds(board.path == "/slow" ? 80 : 20))
        let ids = board.path == "/slow" ? ["1"] : (page == 1 ? ["2", "3"] : ["3", "4"])
        let list = ids.map { "{\"tid\":\"\($0)\",\"title\":\"fixture \($0)\",\"replies\":\($0),\"createdAt\":1}" }.joined(separator: ",")
        return try HupuForum.parseTopics("<script>window.$$data={\"topic\":{\"threads\":{\"current\":\(page),\"total\":2,\"list\":[\(list)]}}}</script>")
    }
    func newsBody(id: String) async throws -> String {
        id == "2" ? "湖人比赛" : (id == "4" ? "勇士比赛" : "热火比赛")
    }
    func detail(id: String, page: Int) async throws -> ForumDetail {
        let comments = page == 1 ? #"[{"pid":"a","allLightCount":5},{"pid":"b","allLightCount":20}]"# : #"[{"pid":"a","allLightCount":8},{"pid":"c","allLightCount":30}]"#
        return try HupuForum.parseDetail("<script id=\"__NEXT_DATA__\">{\"props\":{\"pageProps\":{\"detail\":{\"thread\":{\"title\":\"fixture\",\"content\":\"<p>test</p>\"},\"replies\":{\"current\":\(page),\"total\":2,\"list\":\(comments)}}}}}</script>")
    }
}

private struct BatchNewsFixture: ForumService {
    func topics(board: ForumBoard, page: Int) async throws -> ForumPage {
        let list = (1...24).map { "{\"tid\":\"\($0)\",\"title\":\"fixture\"}" }.joined(separator: ",")
        return try HupuForum.parseTopics("<script>window.$$data={\"topic\":{\"threads\":{\"current\":1,\"total\":1,\"list\":[\(list)]}}}</script>")
    }
    func newsBody(id: String) async throws -> String { "湖人比赛" }
    func detail(id: String, page: Int) async throws -> ForumDetail { throw ForumError.changedPage }
}

/// The middle source page contains no matching news; neighbouring pages overlap.
private struct ScrollNewsFixture: ForumService {
    func topics(board: ForumBoard, page: Int) async throws -> ForumPage {
        let ids = page == 1 ? Array(1...24) : (page == 2 ? Array(24...48) : Array(48...72))
        let list = ids.map { "{\"tid\":\"\($0)\",\"title\":\"fixture\"}" }.joined(separator: ",")
        return try HupuForum.parseTopics("<script>window.$$data={\"topic\":{\"threads\":{\"current\":\(page),\"total\":3,\"list\":[\(list)]}}}</script>")
    }
    func newsBody(id: String) async throws -> String {
        let number = Int(id) ?? 0
        return number <= 12 || number >= 49 ? "湖人比赛" : "热火比赛"
    }
    func detail(id: String, page: Int) async throws -> ForumDetail { throw ForumError.changedPage }
}
