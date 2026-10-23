import SwiftUI
import WebKit
import YuguangCore

struct ForumView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var forum: ForumModel { model.forum }
    private var secondary: Color { Color(white: scheme == .dark ? 0.60 : 0.48) }
    var body: some View {
        VStack(spacing: 0) {
            toolbar.frame(height: 32).padding(.horizontal, 12)
            ZStack {
                topicList.opacity(forum.selected == nil ? 1 : 0)
                    .allowsHitTesting(forum.selected == nil).disabled(forum.selected != nil).accessibilityHidden(forum.selected != nil)
                if forum.selected != nil { detailView }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.font(.system(size: 12))
        .contextMenu {
            Menu("显示行数") {
                ForEach(1...6, id: \.self) { count in Button("\(count) 条") { model.compactRows = count } }
            }
            if forum.selected != nil && model.compact {
                Toggle("精简阅读显示图片", isOn: Binding(get: { forum.showCompactImages }, set: { forum.showCompactImages = $0 }))
            }
            if let topic = forum.selected, let url = URL(string: "https://bbs.hupu.com/\(topic.id).html") {
                Link("浏览器查看原帖", destination: url)
            }
            Button("偏好设置…") {
                if model.compact { model.onToggleCompact?() }
                model.page = .settings
            }
            Button("隐藏窗口") { model.onHide?() }
        }
    }
    private var toolbar: some View {
        HStack(spacing: 8) {
            if forum.selected != nil {
                tool("chevron.left", "返回帖子列表", action: forum.back)
                    .opacity(model.compactChromeVisible ? 1 : 0).allowsHitTesting(model.compactChromeVisible)
            }
            Text(forum.selected == nil ? forum.board?.title ?? "社区板块" : forum.selected?.title ?? "帖子")
                .fontWeight(.medium).lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .overlay { DragArea().accessibilityHidden(true) }
            Group {
                if forum.selected == nil {
                    if forum.board?.path == "/502" {
                        Menu {
                            Toggle("只看主队新闻", isOn: $model.onlyFavoriteNews)
                            Text(model.favoriteTeams.isEmpty ? "尚未选择主队" : model.favoriteTeams.sorted().joined(separator: "、"))
                            if forum.unavailableNews > 0 { Text("\(forum.unavailableNews) 条资讯暂无法识别，刷新可重试") }
                        } label: {
                            Text(model.onlyFavoriteNews ? "主队" : "全部").font(.system(size: 10))
                        }.menuStyle(.borderlessButton).fixedSize().help("筛选篮球资讯")
                    }
                    Menu {
                        ForEach(ForumModel.Sort.allCases, id: \.self) { sort in
                            Button { forum.changeSort(sort) } label: {
                                if sort == forum.sort { Label(sort.rawValue, systemImage: "checkmark") } else { Text(sort.rawValue) }
                            }
                        }
                        Text("回复排序只比较已加载的 \(forum.topics.count) 条帖子")
                    } label: {
                        HStack(spacing: 3) {
                            Text(forum.sort == .latest ? "最新" : "回复").font(.system(size: 10))
                            Image(systemName: "arrow.up.arrow.down")
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize().help(forum.sort.rawValue)
                    tool("arrow.clockwise", "刷新列表") { forum.refresh() }.disabled(forum.loading)
                } else {
                    if let detail = forum.detail, detail.total > 1 {
                        Menu {
                            Text("已加载 \(detail.comments.count) 条 · 按高亮数降序")
                            Text("包含虎扑返回的高亮评论")
                            Button("加载更多评论并重排") { forum.fetchDetail(page: detail.current + 1) }
                                .disabled(detail.current >= detail.total || forum.detailLoading)
                            Text("已读取 \(detail.current) / \(detail.total) 页")
                            if let error = forum.detailError { Text(error) }
                        } label: { Image(systemName: "text.bubble") }
                        .menuStyle(.borderlessButton).fixedSize().help("按高亮数排序 · 已加载 \(detail.comments.count) 条评论")
                    }
                    tool("arrow.clockwise", "刷新帖子") { forum.fetchDetail(page: 1) }.disabled(forum.detailLoading)
                }
                if model.compact {
                    tool("arrow.up.left.and.arrow.down.right", "展开阅读") { model.onToggleCompact?() }
                }
                QuickMatchButton(model: model).frame(width: 24, height: 26)
            }
            .opacity(model.compactChromeVisible ? 1 : 0)
            .allowsHitTesting(model.compactChromeVisible)
            .accessibilityHidden(!model.compactChromeVisible)
        }
    }
    private var topicList: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(forum.ordered) { topic in
                        Button { forum.open(topic) } label: {
                            HStack(spacing: 12) {
                                Text(topic.title).lineLimit(1).truncationMode(.tail)
                                    .foregroundStyle(forum.readIDs.contains(topic.id) ? secondary : Color.primary)
                                Spacer(minLength: 0)
                                Text("\(topic.replies)").monospacedDigit().foregroundStyle(secondary)
                                    .font(.system(size: 10))
                            }.padding(.horizontal, 12).frame(height: 32).contentShape(Rectangle())
                        }.buttonStyle(.plain).id(topic.id)
                            .help("\(topic.title)\n\(topic.author) · \(topic.time) · \(topic.replies) 回复")
                    }
                    if forum.needsFavoriteTeams {
                        Button("先设置我的主队") {
                            if model.compact { model.onToggleCompact?() }
                            model.page = .settings
                        }.buttonStyle(.plain).foregroundStyle(secondary).frame(height: 32)
                    } else if let error = forum.error {
                        Button { forum.loadMore() } label: { Label("加载失败，点击重试", systemImage: "arrow.clockwise") }
                            .buttonStyle(.plain).frame(height: 32).help(error)
                    } else if forum.hasMore {
                        Button { forum.loadMore() } label: {
                            HStack {
                                if forum.loading { ProgressView().controlSize(.mini) }
                                Text(forum.loading ? (forum.filteringNews ? "正在筛选主队资讯…" : "正在加载…") : "加载更多 · 继续向下滚动")
                            }.frame(maxWidth: .infinity).frame(height: 32).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(secondary).disabled(forum.loading)
                            .onAppear {
                                if #unavailable(macOS 15.0) { forum.updateListBoundary(nearEnd: true) }
                            }
                            .onDisappear {
                                if #unavailable(macOS 15.0) { forum.updateListBoundary(nearEnd: false) }
                            }
                    } else {
                        Text(forum.topics.isEmpty ? (forum.filteringNews ? "暂无相关主队资讯" : "暂无帖子") : "已加载 \(forum.topics.count) 条")
                            .foregroundStyle(secondary).frame(height: 32)
                    }
                }.scrollTargetLayout()
            }
            .modifier(ForumScrollBoundary(forum: forum))
            .onDisappear { forum.updateListBoundary(nearEnd: false) }
            .scrollPosition(id: Binding(get: { forum.scrollID }, set: { forum.scrollID = $0 }), anchor: .top)
            .onChange(of: forum.sort) { _, _ in
                if let first = forum.ordered.first { reader.scrollTo(first.id, anchor: .top) }
            }
        }
    }
    @ViewBuilder private var detailView: some View {
        if let detail = forum.detail {
            ForumArticle(detail: detail, dark: scheme == .dark, compact: model.compact, showImages: !model.compact || forum.showCompactImages)
                .overlay(alignment: .topTrailing) { if forum.detailLoading { ProgressView().controlSize(.mini).padding(6) } }
        } else if forum.detailLoading {
            HStack { ProgressView().controlSize(.small); Text("正在读取正文和评论…") }
        } else {
            VStack(spacing: 6) {
                Text(forum.detailError ?? "无法读取帖子").lineLimit(2).foregroundStyle(secondary)
                Button("重试") { forum.fetchDetail(page: 1) }
            }.padding(.horizontal, 12)
        }
    }
    private func tool(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 20, height: 26) }
            .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
}

/// Displays only public post content, with no page chrome, scripts, frames or trackers.
private struct ForumArticle: NSViewRepresentable {
    let detail: ForumDetail
    let dark: Bool
    let compact: Bool
    let showImages: Bool
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateNSView(_ view: WKWebView, context: Context) {
        let key = "\(detail.title)|\(detail.current)|\(dark)|\(compact)|\(showImages)|\(detail.html)|\(detail.comments.map { "\($0.id):\($0.likes):\($0.author):\($0.time):\($0.html)" })"
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key
        context.coordinator.allowInitialDocument = true
        let comments = detail.comments.map { comment in
            "<section><div class='meta'>\(escape(comment.author)) · \(escape(comment.time))<span class='likes'>亮了 \(comment.likes)</span></div>\(clean(comment.html))</section>"
        }.joined()
        let body = "<h1>\(escape(detail.title))</h1><div class='meta'>\(escape(detail.author)) · 虎扑</div>\(clean(detail.html))<h2>评论 · 按高亮数降序 · 已加载 \(detail.comments.count) 条</h2>"
        let html = """
        <!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>
        <meta http-equiv='Content-Security-Policy' content="default-src 'none'; img-src https://*.hoopchina.com.cn https://*.hupu.com; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
        <style>:root{color-scheme:\(dark ? "dark" : "light")}*{box-sizing:border-box}html,body{background:transparent!important}body{margin:0;padding:8px 12px 24px;font:13px/1.75 -apple-system,BlinkMacSystemFont,sans-serif;color:\(dark ? "#ececec" : "#252525");overflow-wrap:anywhere}h1{font-size:16px;line-height:1.5;margin:0 0 6px}h2{font-size:12px;font-weight:500;margin:20px 0 8px;color:#888}.meta{font-size:10px;color:#888;margin:0 0 8px}p{margin:6px 0}img,video{max-width:100%!important;height:auto!important}.likes{float:right;font-weight:600;font-variant-numeric:tabular-nums}section{border-top:1px solid \(dark ? "#333" : "#ddd");padding:12px 0}blockquote{margin:8px 0;padding-left:10px;border-left:2px solid #888;color:#888}a{color:inherit}iframe,script,form,object,embed{display:none}\(compact ? "body{padding-top:2px;font-size:12px;line-height:1.65}body>h1,body>.meta{display:none}" : "")\(showImages ? "" : "img{display:none!important}")</style></head><body>\(body)\(comments.isEmpty ? "<p class='meta'>暂无公开评论</p>" : comments)</body></html>
        """
        view.loadHTMLString(html, baseURL: URL(string: "https://bbs.hupu.com"))
    }
    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    private func clean(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<(script|style|iframe|object|form)[^>]*>.*?</\1\s*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s(?:on[a-z]+|style|srcdoc)\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#, with: "", options: .regularExpression)
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var key = ""
        var allowInitialDocument = false
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let index = CommandLine.arguments.firstIndex(of: "--forum-capture"), CommandLine.arguments.count > index + 1 else { return }
            let directory = CommandLine.arguments[index + 1]
            webView.evaluateJavaScript("document.body.innerText") { result, error in
                print("WebKit 正文：\((result as? String)?.count ?? 0) 字符；\(error?.localizedDescription ?? "正常")")
            }
            webView.takeSnapshot(with: nil) { image, _ in
                guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else { return }
                try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("forum-web-content.png"))
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if action.navigationType == .linkActivated {
                if let url = action.request.url, url.scheme == "https" { NSWorkspace.shared.open(url) }
                return .cancel
            } else { if allowInitialDocument, action.navigationType == .other, action.targetFrame?.isMainFrame != false,
                   let url = action.request.url, url.scheme == "about" || (url.scheme == "https" && url.host == "bbs.hupu.com") {
                    allowInitialDocument = false
                    return .allow
                }
                return .cancel }
        }
    }
}

private struct ForumScrollBoundary: ViewModifier {
    let forum: ForumModel
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 64
            } action: { _, nearEnd in
                forum.updateListBoundary(nearEnd: nearEnd)
            }
        } else {
            // On macOS 14 the persistent footer tracks appearance. Completion in
            // ForumModel rechecks it even when a filtered batch adds no rows.
            content
        }
    }
}
