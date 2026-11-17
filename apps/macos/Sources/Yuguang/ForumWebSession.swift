import SwiftUI
import WebKit
import YuguangCore

/// Verification and subsequent public-page loads use WebKit's own persistent session.
/// No browser cookies are exported and no native message bridge is exposed to pages.
@MainActor final class ForumWebSession: NSObject, NSWindowDelegate {
    static let shared = ForumWebSession()
    private var usesWebSession = UserDefaults.standard.bool(forKey: "forumWebSessionEnabled")
    private var window: NSWindow?
    private var verificationWeb: WKWebView?
    private var onVerified: (@MainActor () -> Void)?

    func fetch(_ url: URL) async throws -> String {
        guard usesWebSession else { return try await HupuForum.fetchPage(url: url) }
        let load = ForumPageLoad()
        return try await load.fetch(url)
    }

    func showVerification(url: URL, completion: @escaping @MainActor () -> Void) {
        onVerified = completion
        if let window, window.isVisible { window.makeKeyAndOrderFront(nil); return }
        usesWebSession = true
        UserDefaults.standard.set(true, forKey: "forumWebSessionEnabled")
        let web = WKWebView(frame: .zero, configuration: Self.configuration())
        verificationWeb = web
        web.load(URLRequest(url: url))
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 660),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.delegate = self
        panel.title = "虎扑安全验证"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: VStack(alignment: .leading, spacing: 12) {
            Text("请在下方完成虎扑安全验证，看到正常网页后点击“完成并重试”。").padding(.horizontal)
            ForumVerificationWebView(web: web)
            HStack {
                Button("取消") { [weak panel] in panel?.close() }
                Spacer()
                Button("重新加载") { web.reload() }
                Button("完成并重试") { [weak self] in self?.completeVerification() }
                    .keyboardShortcut(.defaultAction)
            }.padding(.horizontal)
        }.padding(.vertical, 12))
        window?.contentView = nil
        window = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func completeVerification() {
        let completion = onVerified
        window?.close()
        completion?()
    }
    func windowWillClose(_ notification: Notification) {
        verificationWeb?.stopLoading()
        onVerified = nil
    }

    static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        return configuration
    }
}

private struct ForumVerificationWebView: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

@MainActor private final class ForumPageLoad: NSObject, WKNavigationDelegate {
    private let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 820, height: 580), configuration: ForumWebSession.configuration())
    private var continuation: CheckedContinuation<String, any Error>?
    private var timeout: Task<Void, Never>?

    func fetch(_ url: URL) async throws -> String {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                web.navigationDelegate = self
                web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(25)) } catch { return }
                    self?.finish(.failure(URLError(.timedOut)))
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<String, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        web.navigationDelegate = nil
        web.stopLoading()
        continuation.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.host == "bbs.hupu.com" else { finish(.failure(ForumError.changedPage)); return }
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] value, error in
            if let error { self?.finish(.failure(error)) }
            else if let html = value as? String { self?.finish(.success(html)) }
            else { self?.finish(.failure(ForumError.changedPage)) }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(URLError(.networkConnectionLost))) }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode != 200 {
            finish(.failure(ForumError.unavailable(http.statusCode)))
            return .cancel
        }
        return .allow
    }
}
