import Foundation

public struct ForumBoard: Identifiable, Hashable, Sendable {
    public let category: String
    public let title: String
    public let path: String
    public var id: String { path }
    public init(category: String, title: String, path: String) { self.category = category; self.title = title; self.path = path }
}
public struct ForumTopic: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let replies: Int
    public let createdAt: Double
    public let author: String
    public let time: String
}
public struct ForumPage: Sendable {
    public let topics: [ForumTopic]
    public let current: Int
    public let total: Int
}
public struct ForumComment: Identifiable, Sendable {
    public let id: String
    public let author: String
    public let html: String
    public let time: String
    public let likes: Int
    public let isHidden: Bool
}
public struct ForumDetail: Sendable {
    public let title: String
    public let html: String
    public let author: String
    public let comments: [ForumComment]
    public let current: Int
    public let total: Int
    public init(title: String, html: String, author: String, comments: [ForumComment], current: Int, total: Int) {
        self.title = title; self.html = html; self.author = author
        self.comments = Self.ranked(comments); self.current = current; self.total = total
    }
    public static func ranked(_ comments: [ForumComment]) -> [ForumComment] {
        var unique: [String: ForumComment] = [:], order: [String: Int] = [:]
        for (index, comment) in comments.enumerated() {
            if order[comment.id] == nil { order[comment.id] = index }
            if unique[comment.id]?.isHidden == true && !comment.isHidden { continue }
            unique[comment.id] = comment
        }
        return unique.values.sorted { $0.likes != $1.likes ? $0.likes > $1.likes : (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }
}
public enum ForumError: LocalizedError {
    case changedPage, invalidPath, unavailable(Int)
    public var errorDescription: String? {
        switch self {
        case .changedPage: "虎扑页面结构发生变化，或暂时需要验证。请稍后刷新，或在浏览器查看原帖。"
        case .invalidPath: "无效的虎扑地址"
        case .unavailable(let code): "虎扑暂时无法访问（HTTP \(code)），请稍后重试。"
        }
    }
}
public protocol ForumService: Sendable {
    func topics(board: ForumBoard, page: Int) async throws -> ForumPage
    func detail(id: String, page: Int) async throws -> ForumDetail
    func newsBody(id: String) async throws -> String
}
/// Reads the same public SSR data as bbs.hupu.com; no private API or login credentials.
public struct HupuForum: ForumService {
    public init() {}
    public func topics(board: ForumBoard, page: Int) async throws -> ForumPage {
        let suffix = page > 1 ? "-\(page)" : ""
        return try Self.parseTopics(await fetch(path: board.path + "-postdate" + suffix))
    }
    public func detail(id: String, page: Int) async throws -> ForumDetail {
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { throw ForumError.invalidPath }
        return try Self.parseDetail(await fetch(path: "/\(id)\(page > 1 ? "-\(page)" : "").html"))
    }
    public func newsBody(id: String) async throws -> String {
        if let cached = await NewsBodyCache.shared.value(id) { return cached }
        let text = NewsTeamFilter.plainText(try await detail(id: id, page: 1).html)
        await NewsBodyCache.shared.put(id, text: text)
        return text
    }
    private func fetch(path: String) async throws -> String {
        guard path.range(of: #"^/[A-Za-z0-9_-]+(?:\.html)?$"#, options: .regularExpression) != nil,
              let url = URL(string: "https://bbs.hupu.com" + path) else { throw ForumError.invalidPath }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw ForumError.changedPage }
        guard response.statusCode == 200 else { throw ForumError.unavailable(response.statusCode) }
        guard response.url?.host == "bbs.hupu.com", let html = String(data: data, encoding: .utf8) else { throw ForumError.changedPage }
        return html
    }
    /// Balanced extraction handles braces, quotes and escaped characters inside post content.
    public static func pageData(_ html: String) throws -> [String: Any] {
        if let marker = html.range(of: "window.$$data="), let json = balancedObject(html[marker.upperBound...]),
           let value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] { return value }
        if let marker = html.range(of: #"<script[^>]*id="__NEXT_DATA__"[^>]*>"#, options: .regularExpression),
           let end = html.range(of: "</script>", range: marker.upperBound..<html.endIndex),
           let root = try JSONSerialization.jsonObject(with: Data(html[marker.upperBound..<end.lowerBound].utf8)) as? [String: Any],
           let props = root["props"] as? [String: Any], let page = props["pageProps"] as? [String: Any] { return page }
        throw ForumError.changedPage
    }
    private static func balancedObject(_ source: Substring) -> String? {
        guard let start = source.firstIndex(of: "{") else { return nil }
        var depth = 0, quoted = false, escaped = false
        for index in source[start...].indices {
            let char = source[index]
            if quoted {
                if escaped { escaped = false } else if char == "\\" { escaped = true } else if char == "\"" { quoted = false }
            } else if char == "\"" { quoted = true }
            else if char == "{" { depth += 1 }
            else if char == "}" { depth -= 1; if depth == 0 { return String(source[start...index]) } }
        }
        return nil
    }
    public static func parseTopics(_ html: String) throws -> ForumPage {
        let root = try pageData(html)
        guard let topic = root["topic"] as? [String: Any], let threads = topic["threads"] as? [String: Any],
              let list = threads["list"] as? [[String: Any]], let current = threads["current"] as? Int, let total = threads["total"] as? Int else { throw ForumError.changedPage }
        let topics = list.compactMap { value -> ForumTopic? in
            guard let id = value["tid"] as? String, !id.isEmpty, id.allSatisfy(\.isNumber), let title = value["title"] as? String else { return nil }
            let author = value["author"] as? [String: Any]
            return ForumTopic(id: id, title: title, replies: value["replies"] as? Int ?? 0, createdAt: value["createdAt"] as? Double ?? 0, author: author?["puname"] as? String ?? "JR", time: value["createdAtFormat"] as? String ?? "")
        }
        if !list.isEmpty && topics.isEmpty { throw ForumError.changedPage }
        return ForumPage(topics: unique(topics), current: current, total: total)
    }
    public static func unique(_ topics: [ForumTopic]) -> [ForumTopic] {
        var seen = Set<String>()
        return topics.filter { seen.insert($0.id).inserted }
    }
    public static func parseDetail(_ html: String) throws -> ForumDetail {
        let root = try pageData(html)
        guard let detail = root["detail"] as? [String: Any], let thread = detail["thread"] as? [String: Any],
              let title = thread["title"] as? String, let content = thread["content"] as? String,
              let replies = detail["replies"] as? [String: Any], let list = replies["list"] as? [[String: Any]],
              let current = replies["current"] as? Int, let total = replies["total"] as? Int else { throw ForumError.changedPage }
        let combined = (detail["lights"] as? [[String: Any]] ?? []) + list
        let comments = combined.compactMap { value -> ForumComment? in
            guard let id = value["pid"] as? String else { return nil }
            let author = value["author"] as? [String: Any]
            let hidden = (value["isHidden"] as? Bool == true || value["isDelete"] as? Bool == true || value["isSelfDelete"] as? Bool == true)
            return ForumComment(id: id, author: author?["puname"] as? String ?? "JR", html: hidden ? "<p>此评论不可见</p>" : value["content"] as? String ?? "", time: value["createdAtFormat"] as? String ?? "", likes: max(0, value["allLightCount"] as? Int ?? 0), isHidden: hidden)
        }
        return ForumDetail(title: title, html: content, author: (thread["author"] as? [String: Any])?["puname"] as? String ?? "JR", comments: comments, current: current, total: total)
    }
}

extension ForumBoard {
    // Public Hupu navigation snapshot; 2026-10-23.
    public static let catalog: [ForumBoard] = [
        ForumBoard(category: "综合体育", title: "乒乓球区", path: "/pingpang"),
        ForumBoard(category: "综合体育", title: "网球场", path: "/tennis"),
        ForumBoard(category: "综合体育", title: "羽毛球", path: "/yumaoqiu"),
        ForumBoard(category: "综合体育", title: "综合体育区", path: "/sports"),
        ForumBoard(category: "综合体育", title: "台球区", path: "/billiards"),
        ForumBoard(category: "综合体育", title: "跑步区", path: "/running"),
        ForumBoard(category: "综合体育", title: "奥运会专区", path: "/753"),
        ForumBoard(category: "综合体育", title: "NFL专区", path: "/nfl"),
        ForumBoard(category: "综合体育", title: "自行车运动", path: "/cycling"),
        ForumBoard(category: "综合体育", title: "MLB棒球场", path: "/705"),
        ForumBoard(category: "综合体育", title: "花样滑冰区", path: "/773"),
        ForumBoard(category: "综合体育", title: "围棋区", path: "/832"),
        ForumBoard(category: "综合体育", title: "格斗专区", path: "/mma"),
        ForumBoard(category: "综合体育", title: "WWE专区", path: "/833"),
        ForumBoard(category: "步行街", title: "步行街主干道", path: "/topic-daily"),
        ForumBoard(category: "步行街", title: "恋爱区", path: "/love"),
        ForumBoard(category: "步行街", title: "历史区", path: "/history"),
        ForumBoard(category: "步行街", title: "股票区", path: "/stock"),
        ForumBoard(category: "步行街", title: "职场区", path: "/workplace"),
        ForumBoard(category: "步行街", title: "校园区", path: "/school"),
        ForumBoard(category: "步行街", title: "AI工坊", path: "/871"),
        ForumBoard(category: "步行街", title: "健身区", path: "/fit"),
        ForumBoard(category: "步行街", title: "家装房产区", path: "/13"),
        ForumBoard(category: "步行街", title: "自拍区", path: "/787"),
        ForumBoard(category: "步行街", title: "动物萌宠区", path: "/34"),
        ForumBoard(category: "步行街", title: "美食区", path: "/539"),
        ForumBoard(category: "步行街", title: "实战篮球区", path: "/549"),
        ForumBoard(category: "步行街", title: "旅游区", path: "/22"),
        ForumBoard(category: "步行街", title: "头像壁纸区", path: "/48"),
        ForumBoard(category: "步行街", title: "球星卡区", path: "/646"),
        ForumBoard(category: "步行街", title: "手表区", path: "/512"),
        ForumBoard(category: "步行街", title: "网络文学区", path: "/611"),
        ForumBoard(category: "步行街", title: "正能量区", path: "/483"),
        ForumBoard(category: "步行街", title: "科幻区", path: "/542"),
        ForumBoard(category: "步行街", title: "考研区", path: "/618"),
        ForumBoard(category: "步行街", title: "文学区", path: "/609"),
        ForumBoard(category: "步行街", title: "手办模玩区", path: "/755"),
        ForumBoard(category: "步行街", title: "摄影区", path: "/612"),
        ForumBoard(category: "影视娱乐", title: "娱乐圈", path: "/59"),
        ForumBoard(category: "影视娱乐", title: "影视区", path: "/ent"),
        ForumBoard(category: "影视娱乐", title: "音乐圈", path: "/63"),
        ForumBoard(category: "英雄联盟", title: "英雄联盟", path: "/lol"),
        ForumBoard(category: "英雄联盟", title: "LOL话题讨论", path: "/822"),
        ForumBoard(category: "英雄联盟", title: "IG专区", path: "/817"),
        ForumBoard(category: "英雄联盟", title: "T1专区", path: "/828"),
        ForumBoard(category: "英雄联盟", title: "BLG专区", path: "/814"),
        ForumBoard(category: "英雄联盟", title: "GEN专区", path: "/829"),
        ForumBoard(category: "英雄联盟", title: "DK专区", path: "/830"),
        ForumBoard(category: "英雄联盟", title: "TES专区", path: "/824"),
        ForumBoard(category: "英雄联盟", title: "WE专区", path: "/827"),
        ForumBoard(category: "英雄联盟", title: "AL专区", path: "/813"),
        ForumBoard(category: "英雄联盟", title: "OMG专区", path: "/821"),
        ForumBoard(category: "英雄联盟", title: "EDG专区", path: "/811"),
        ForumBoard(category: "英雄联盟", title: "RNG专区", path: "/823"),
        ForumBoard(category: "英雄联盟", title: "WBG专区", path: "/812"),
        ForumBoard(category: "英雄联盟", title: "LNG专区", path: "/815"),
        ForumBoard(category: "英雄联盟", title: "FPX专区", path: "/816"),
        ForumBoard(category: "英雄联盟", title: "JDG专区", path: "/818"),
        ForumBoard(category: "英雄联盟", title: "LGD专区", path: "/819"),
        ForumBoard(category: "英雄联盟", title: "NIP专区", path: "/820"),
        ForumBoard(category: "英雄联盟", title: "TT专区", path: "/825"),
        ForumBoard(category: "英雄联盟", title: "UP专区", path: "/826"),
        ForumBoard(category: "英雄联盟", title: "KT专区", path: "/831"),
        ForumBoard(category: "英雄联盟", title: "HLE专区", path: "/863"),
        ForumBoard(category: "游戏", title: "王者荣耀", path: "/kog"),
        ForumBoard(category: "游戏", title: "NBA2KOL2", path: "/NBA2Konline"),
        ForumBoard(category: "游戏", title: "无畏契约", path: "/803"),
        ForumBoard(category: "游戏", title: "CS2", path: "/csgo"),
        ForumBoard(category: "游戏", title: "瓦讨论区", path: "/869"),
        ForumBoard(category: "游戏", title: "绝地求生", path: "/pubg"),
        ForumBoard(category: "游戏", title: "NBA2K专区", path: "/698"),
        ForumBoard(category: "游戏", title: "和平精英", path: "/gp"),
        ForumBoard(category: "游戏", title: "游戏区", path: "/game"),
        ForumBoard(category: "游戏", title: "崩坏3", path: "/788"),
        ForumBoard(category: "游戏", title: "原神", path: "/706"),
        ForumBoard(category: "游戏", title: "LOL手游", path: "/656"),
        ForumBoard(category: "游戏", title: "三角洲行动", path: "/848"),
        ForumBoard(category: "游戏", title: "崩坏：星穹铁道", path: "/802"),
        ForumBoard(category: "游戏", title: "DOTA 2", path: "/dota2"),
        ForumBoard(category: "游戏", title: "绝区零", path: "/834"),
        ForumBoard(category: "游戏", title: "云顶之弈", path: "/508"),
        ForumBoard(category: "游戏", title: "黑神话：悟空", path: "/837"),
        ForumBoard(category: "游戏", title: "Apex英雄", path: "/781"),
        ForumBoard(category: "游戏", title: "炉石传说", path: "/hs"),
        ForumBoard(category: "游戏", title: "金铲铲之战", path: "/777"),
        ForumBoard(category: "游戏", title: "永劫无间", path: "/750"),
        ForumBoard(category: "游戏", title: "王者万象棋", path: "/870"),
        ForumBoard(category: "游戏", title: "火影忍者手游", path: "/836"),
        ForumBoard(category: "游戏", title: "JRs竞技场", path: "/752"),
        ForumBoard(category: "游戏", title: "电竞世俱杯", path: "/835"),
        ForumBoard(category: "游戏", title: "王者荣耀世界", path: "/862"),
        ForumBoard(category: "游戏", title: "最强NBA", path: "/628"),
        ForumBoard(category: "游戏", title: "游宇宙", path: "/778"),
        ForumBoard(category: "游戏", title: "三国杀", path: "/779"),
        ForumBoard(category: "游戏", title: "决胜巅峰", path: "/844"),
        ForumBoard(category: "游戏", title: "第五人格", path: "/855"),
        ForumBoard(category: "游戏", title: "格斗游戏", path: "/856"),
        ForumBoard(category: "游戏", title: "彩虹六号", path: "/861"),
        ForumBoard(category: "NBA", title: "篮球资讯", path: "/502"),
        ForumBoard(category: "NBA", title: "76人专区", path: "/sixers"),
        ForumBoard(category: "NBA", title: "骑士专区", path: "/cavaliers"),
        ForumBoard(category: "NBA", title: "勇士专区", path: "/warriors"),
        ForumBoard(category: "NBA", title: "湖人专区", path: "/lakers"),
        ForumBoard(category: "NBA", title: "火箭专区", path: "/rockets"),
        ForumBoard(category: "NBA", title: "开拓者专区", path: "/blazers"),
        ForumBoard(category: "NBA", title: "湿乎乎的话题", path: "/vote"),
        ForumBoard(category: "NBA", title: "马刺专区", path: "/spurs"),
        ForumBoard(category: "NBA", title: "独行侠专区", path: "/mavericks"),
        ForumBoard(category: "NBA", title: "太阳专区", path: "/suns"),
        ForumBoard(category: "NBA", title: "雷霆专区", path: "/thunder"),
        ForumBoard(category: "NBA", title: "凯尔特人专区", path: "/celtics"),
        ForumBoard(category: "NBA", title: "热火专区", path: "/heat"),
        ForumBoard(category: "NBA", title: "森林狼专区", path: "/timberwolves"),
        ForumBoard(category: "NBA", title: "猛龙专区", path: "/raptors"),
        ForumBoard(category: "NBA", title: "尼克斯专区", path: "/knicks"),
        ForumBoard(category: "NBA", title: "掘金专区", path: "/nuggets"),
        ForumBoard(category: "NBA", title: "快船专区", path: "/clippers"),
        ForumBoard(category: "NBA", title: "爵士专区", path: "/jazz"),
        ForumBoard(category: "NBA", title: "篮网专区", path: "/nets"),
        ForumBoard(category: "NBA", title: "奇才专区", path: "/wizards"),
        ForumBoard(category: "NBA", title: "公牛专区", path: "/bulls"),
        ForumBoard(category: "NBA", title: "鹈鹕专区", path: "/pelicans"),
        ForumBoard(category: "NBA", title: "国王专区", path: "/kings"),
        ForumBoard(category: "NBA", title: "雄鹿专区", path: "/bucks"),
        ForumBoard(category: "NBA", title: "篮球场", path: "/nba"),
        ForumBoard(category: "NBA", title: "活塞专区", path: "/pistons"),
        ForumBoard(category: "NBA", title: "NBA选秀—NCAA", path: "/nba-draft-ncaa"),
        ForumBoard(category: "NBA", title: "灰熊专区", path: "/grizzlies"),
        ForumBoard(category: "NBA", title: "步行者专区", path: "/pacers"),
        ForumBoard(category: "NBA", title: "魔术专区", path: "/magic"),
        ForumBoard(category: "NBA", title: "女子篮球-WNBA", path: "/wnba"),
        ForumBoard(category: "NBA", title: "老鹰专区", path: "/hawks"),
        ForumBoard(category: "NBA", title: "黄蜂专区", path: "/hornets"),
        ForumBoard(category: "NBA", title: "篮彩明灯区", path: "/647"),
        ForumBoard(category: "NBA", title: "詹姆斯专区", path: "/838"),
        ForumBoard(category: "NBA", title: "杜兰特专区", path: "/841"),
        ForumBoard(category: "NBA", title: "科比专区", path: "/840"),
        ForumBoard(category: "NBA", title: "街球实战", path: "/streetball"),
        ForumBoard(category: "NBA", title: "库里专区", path: "/839"),
        ForumBoard(category: "NBA", title: "FIBA-国际篮球", path: "/fiba"),
        ForumBoard(category: "NBA", title: "哈登专区", path: "/843"),
        ForumBoard(category: "NBA", title: "篮球视频", path: "/509"),
        ForumBoard(category: "装备", title: "运动装备", path: "/gear"),
        ForumBoard(category: "装备", title: "潮流区", path: "/in"),
        ForumBoard(category: "装备", title: "球衣区", path: "/jersey"),
        ForumBoard(category: "CBA", title: "CBA专区", path: "/cba"),
        ForumBoard(category: "CBA", title: "广东华南虎", path: "/guangdong"),
        ForumBoard(category: "CBA", title: "上海大鲨鱼", path: "/shanghai"),
        ForumBoard(category: "CBA", title: "北京首钢", path: "/beijing"),
        ForumBoard(category: "CBA", title: "辽宁飞豹", path: "/liaoning"),
        ForumBoard(category: "CBA", title: "山西猛龙", path: "/shanxi"),
        ForumBoard(category: "CBA", title: "留洋球员区", path: "/764"),
        ForumBoard(category: "CBA", title: "新疆飞虎", path: "/xinjiang"),
        ForumBoard(category: "CBA", title: "山东麒麟", path: "/shandong"),
        ForumBoard(category: "CBA", title: "浙江雄狮", path: "/guangsha"),
        ForumBoard(category: "CBA", title: "吉林东北虎", path: "/jilin"),
        ForumBoard(category: "CBA", title: "宁波火箭", path: "/757"),
        ForumBoard(category: "CBA", title: "深圳烈豹", path: "/shenzhen"),
        ForumBoard(category: "CBA", title: "福建中华鲟", path: "/fujian"),
        ForumBoard(category: "CBA", title: "广州龙狮", path: "/longshi"),
        ForumBoard(category: "CBA", title: "南京大圣", path: "/dasheng"),
        ForumBoard(category: "CBA", title: "浙江金牛", path: "/zhejiang"),
        ForumBoard(category: "CBA", title: "江苏龙", path: "/jiangsu"),
        ForumBoard(category: "CBA", title: "北京紫禁勇士", path: "/beikong"),
        ForumBoard(category: "CBA", title: "四川蓝鲸", path: "/sichuan"),
        ForumBoard(category: "CBA", title: "青岛雄鹰", path: "/qingdao"),
        ForumBoard(category: "CBA", title: "CUBAL专区", path: "/cuba"),
        ForumBoard(category: "CBA", title: "天津先行者", path: "/tianjin"),
        ForumBoard(category: "CBA", title: "NBL", path: "/nbl"),
        ForumBoard(category: "CBA", title: "亚洲篮球", path: "/asiabasket"),
        ForumBoard(category: "CBA", title: "WCBA", path: "/wcba"),
        ForumBoard(category: "CBA", title: "林书豪专区", path: "/jeremylin"),
        ForumBoard(category: "CBA", title: "中国篮球视频区", path: "/480"),
        ForumBoard(category: "国际足球", title: "国际足球资讯", path: "/482"),
        ForumBoard(category: "国际足球", title: "足球话题区", path: "/topic"),
        ForumBoard(category: "国际足球", title: "曼联专区", path: "/manutd"),
        ForumBoard(category: "国际足球", title: "皇马专区", path: "/realmadrid"),
        ForumBoard(category: "国际足球", title: "巴萨专区", path: "/barcelona"),
        ForumBoard(category: "国际足球", title: "阿森纳专区", path: "/arsenal"),
        ForumBoard(category: "国际足球", title: "米兰专区", path: "/acmilan"),
        ForumBoard(category: "国际足球", title: "拜仁专区", path: "/bayern"),
        ForumBoard(category: "国际足球", title: "利物浦专区", path: "/liverpool"),
        ForumBoard(category: "国际足球", title: "曼城专区", path: "/mancity"),
        ForumBoard(category: "国际足球", title: "切尔西专区", path: "/chelsea"),
        ForumBoard(category: "国际足球", title: "国米专区", path: "/inter"),
        ForumBoard(category: "国际足球", title: "尤文专区", path: "/juventus"),
        ForumBoard(category: "国际足球", title: "足球财富区", path: "/648"),
        ForumBoard(category: "国际足球", title: "FM专区", path: "/FM"),
        ForumBoard(category: "国际足球", title: "阿根廷足球", path: "/797"),
        ForumBoard(category: "国际足球", title: "巴黎专区", path: "/PSG"),
        ForumBoard(category: "国际足球", title: "穆里尼奥专区", path: "/Mourinho"),
        ForumBoard(category: "国际足球", title: "热刺专区", path: "/hotspur"),
        ForumBoard(category: "国际足球", title: "罗马专区", path: "/asroma"),
        ForumBoard(category: "国际足球", title: "德国足球", path: "/dejia"),
        ForumBoard(category: "国际足球", title: "马竞专区", path: "/atleticodemadrid"),
        ForumBoard(category: "国际足球", title: "纽卡斯尔专区", path: "/808"),
        ForumBoard(category: "国际足球", title: "意大利足球", path: "/yijia"),
        ForumBoard(category: "国际足球", title: "沙特联专区", path: "/810"),
        ForumBoard(category: "国际足球", title: "多特蒙德专区", path: "/bvb"),
        ForumBoard(category: "国际足球", title: "阿贾克斯专区", path: "/afcajax"),
        ForumBoard(category: "国际足球", title: "巴西足球", path: "/798"),
        ForumBoard(category: "国际足球", title: "实况足球", path: "/589"),
        ForumBoard(category: "国际足球", title: "西班牙足球", path: "/xijia"),
        ForumBoard(category: "国际足球", title: "FIFA Online 4", path: "/627"),
        ForumBoard(category: "国际足球", title: "阿斯顿维拉专区", path: "/853"),
        ForumBoard(category: "国际足球", title: "法国足球", path: "/frfootball"),
        ForumBoard(category: "国际足球", title: "英格兰足球", path: "/yingchao"),
        ForumBoard(category: "国际足球", title: "西班牙人官方专区", path: "/468"),
        ForumBoard(category: "国际足球", title: "莱斯特城专区", path: "/571"),
        ForumBoard(category: "国际足球", title: "荷兰足球", path: "/709"),
        ForumBoard(category: "国际足球", title: "葡萄牙足球", path: "/710"),
        ForumBoard(category: "国际足球", title: "那不勒斯专区", path: "/852"),
        ForumBoard(category: "国际足球", title: "美职联专区", path: "/809"),
        ForumBoard(category: "国际足球", title: "诺丁汉森林专区", path: "/854"),
        ForumBoard(category: "国际足球", title: "日本足球", path: "/864"),
        ForumBoard(category: "国际足球", title: "比利时足球", path: "/868"),
        ForumBoard(category: "国际足球", title: "足球场", path: "/soccer"),
        ForumBoard(category: "国际足球", title: "妖人银河系", path: "/yaoren"),
        ForumBoard(category: "国际足球", title: "埃瓦尔官方专区", path: "/199"),
        ForumBoard(category: "国际足球", title: "翻译团", path: "/fyt-soccer"),
        ForumBoard(category: "国际足球", title: "FC足球世界", path: "/599"),
        ForumBoard(category: "国际足球", title: "EAFC专区", path: "/780"),
        ForumBoard(category: "国际足球", title: "韩国足球", path: "/865"),
        ForumBoard(category: "国际足球", title: "挪威足球", path: "/866"),
        ForumBoard(category: "国际足球", title: "克罗地亚足球", path: "/867"),
        ForumBoard(category: "中国足球", title: "中国足球", path: "/china-soccer"),
        ForumBoard(category: "中国足球", title: "青少年足球", path: "/221"),
        ForumBoard(category: "中国足球", title: "上海申花", path: "/shenhua"),
        ForumBoard(category: "中国足球", title: "上海海港", path: "/sipgfc"),
        ForumBoard(category: "中国足球", title: "山东泰山", path: "/luneng"),
        ForumBoard(category: "中国足球", title: "江苏联专区", path: "/849"),
        ForumBoard(category: "中国足球", title: "北京国安", path: "/guoan"),
        ForumBoard(category: "中国足球", title: "成都蓉城", path: "/783"),
        ForumBoard(category: "中国足球", title: "大连英博", path: "/dalian"),
        ForumBoard(category: "中国足球", title: "浙江队", path: "/786"),
        ForumBoard(category: "中国足球", title: "广州队", path: "/hengda"),
        ForumBoard(category: "中国足球", title: "中甲联赛", path: "/238"),
        ForumBoard(category: "中国足球", title: "辽宁铁人", path: "/851"),
        ForumBoard(category: "中国足球", title: "河南队", path: "/jianye"),
        ForumBoard(category: "中国足球", title: "天津津门虎", path: "/teda"),
        ForumBoard(category: "中国足球", title: "长春亚泰", path: "/692"),
        ForumBoard(category: "中国足球", title: "武汉三镇", path: "/784"),
        ForumBoard(category: "中国足球", title: "青岛海牛", path: "/807"),
        ForumBoard(category: "中国足球", title: "亚洲足球", path: "/asia-soccer"),
        ForumBoard(category: "中国足球", title: "梅州客家", path: "/785"),
        ForumBoard(category: "中国足球", title: "云南玉昆", path: "/845"),
        ForumBoard(category: "中国足球", title: "青岛西海岸", path: "/846"),
        ForumBoard(category: "中国足球", title: "深圳新鹏城", path: "/847"),
        ForumBoard(category: "中国足球", title: "重庆铜梁龙", path: "/850"),
        ForumBoard(category: "数码", title: "数码综合讨论", path: "/digital"),
        ForumBoard(category: "数码", title: "PC区", path: "/74"),
        ForumBoard(category: "汽车", title: "汽车区", path: "/cars"),
        ForumBoard(category: "汽车", title: "F1赛车区", path: "/f1"),
        ForumBoard(category: "汽车", title: "机车区", path: "/619"),
        ForumBoard(category: "站务管理", title: "产品吐槽区", path: "/476"),
    ]
}
