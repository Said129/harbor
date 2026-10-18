import SwiftUI
import WebKit
import Observation

@MainActor @Observable
final class SubmanhwaSession: NSObject, WKNavigationDelegate {
    private static var sessions: [String: SubmanhwaSession] = [:]
    static func forOwner(_ owner: String) -> SubmanhwaSession {
        if let session = sessions[owner] { return session }
        let session = SubmanhwaSession(owner: owner)
        sessions[owner] = session
        return session
    }
    let web: WKWebView
    var loading = false
    var error: String?
    var canGoBack = false
    var canGoForward = false
    private var contentRulesInstalled = false
    private convenience init(owner: String) {
        let hex = Array(EBookShelf.hash("submanhwa|" + owner).prefix(32))
        let identifier = UUID(uuidString: String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-" + String(hex[12..<16]) + "-" + String(hex[16..<20]) + "-" + String(hex[20..<32]))!
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: identifier)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        self.init(configuration: configuration)
    }
    init(configuration: WKWebViewConfiguration) {
        web = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
    }
    func openIfNeeded() async {
        guard web.url == nil, !loading, let url = URL(string: "https://submanhwa.com/") else { return }
        loading = true; error = nil
        do {
            if !contentRulesInstalled {
                let rules = try await SubmanhwaAdBlocker.contentRules()
                try Task.checkCancellation()
                web.configuration.userContentController.add(rules)
                contentRulesInstalled = true
            }
            try Task.checkCancellation()
            web.load(URLRequest(url: url))
        } catch is CancellationError { loading = false }
        catch { loading = false; self.error = safeMessage(error); Diagnostics.shared.recordFailure(error) }
    }
    func retry() async {
        if web.url == nil { await openIfNeeded() }
        else { error = nil; web.reload() }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        SubmanhwaAdBlocker.blocks(action.request.url) ? .cancel : .allow
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        (webView.uiDelegate as? WebPageController)?.cancelSiteDialog()
        loading = true; error = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func finish() { loading = false; canGoBack = web.canGoBack; canGoForward = web.canGoForward }
    private func fail(_ error: Error) { finish(); if (error as NSError).code != NSURLErrorCancelled { self.error = "No se pudo cargar Submanhwa. Puedes reintentar." } }
}

private struct SubmanhwaBrowser: UIViewControllerRepresentable {
    let session: SubmanhwaSession
    func makeUIViewController(context: Context) -> WebPageController {
        let controller = WebPageController(webView: session.web)
        controller.openWindow = { web, action in
            guard SubmanhwaAdBlocker.allowsNewWindow(action.request.url, navigation: action.navigationType) else { return }
            _ = web.load(action.request)
        }
        return controller
    }
    func updateUIViewController(_ controller: WebPageController, context: Context) { }
    static func dismantleUIViewController(_ controller: WebPageController, coordinator: ()) {
        // The account owns the page and its in-flight navigation. Closing its
        // presentation must not leave a partial page or replay a submitted form.
        controller.detach()
    }
}

struct SubmanhwaView: View {
    @State private var session: SubmanhwaSession
    @Environment(\.dismiss) private var dismiss
    @MainActor init(owner: String) { _session = State(initialValue: SubmanhwaSession.forOwner(owner)) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if session.loading { ProgressView().progressViewStyle(.linear).accessibilityLabel("Cargando Submanhwa") }
                if let error = session.error { HStack { Text(error).font(.caption); Button("Reintentar") { Task { await session.retry() } } }.padding(10).foregroundStyle(.orange) }
                SubmanhwaBrowser(session: session)
                HStack {
                    Button { session.web.goBack() } label: { Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 18, height: 18).rotationEffect(.degrees(180)).frame(width: 44, height: 44) }.disabled(!session.canGoBack).accessibilityLabel("Página anterior")
                    Button { session.web.goForward() } label: { Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 18, height: 18).frame(width: 44, height: 44) }.disabled(!session.canGoForward).accessibilityLabel("Página siguiente")
                    Spacer()
                    Button("Cerrar") { dismiss() }.font(HarborTheme.font(14, weight: .medium)).frame(minHeight: 44)
                }.padding(.horizontal, 12)
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).toolbar(.hidden, for: .navigationBar)
        }.task { await session.openIfNeeded() }
    }
}
