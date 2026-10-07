import SwiftUI
import WebKit
import Observation

@MainActor @Observable
final class SubmanhwaSession {
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
    private init(owner: String) {
        let hex = Array(EBookShelf.hash("submanhwa|" + owner).prefix(32))
        let identifier = UUID(uuidString: String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-" + String(hex[12..<16]) + "-" + String(hex[16..<20]) + "-" + String(hex[20..<32]))!
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: identifier)
        web = WKWebView(frame: .zero, configuration: configuration)
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
    }
    func openIfNeeded() {
        guard web.url == nil, let url = URL(string: "https://submanhwa.com/") else { return }
        error = nil; web.load(URLRequest(url: url))
    }
}

private struct SubmanhwaBrowser: UIViewControllerRepresentable {
    let session: SubmanhwaSession
    func makeUIViewController(context: Context) -> WebPageController {
        let controller = WebPageController(webView: session.web)
        controller.openWindow = { web, action in _ = web.load(action.request) }
        context.coordinator.controller = controller
        session.web.navigationDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: WebPageController, context: Context) { }
    static func dismantleUIViewController(_ controller: WebPageController, coordinator: Coordinator) { controller.close() }
    func makeCoordinator() -> Coordinator { Coordinator(session) }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let session: SubmanhwaSession
        weak var controller: WebPageController?
        init(_ session: SubmanhwaSession) { self.session = session }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { controller?.cancelSiteDialog(); session.loading = true; session.error = nil }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
        private func finish() { session.loading = false; session.canGoBack = session.web.canGoBack; session.canGoForward = session.web.canGoForward }
        private func fail(_ error: Error) { finish(); if (error as NSError).code != NSURLErrorCancelled { session.error = "No se pudo cargar Submanhwa. Puedes reintentar." } }
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
                if let error = session.error { HStack { Text(error).font(.caption); Button("Reintentar") { session.web.reload() } }.padding(10).foregroundStyle(.orange) }
                SubmanhwaBrowser(session: session)
                HStack {
                    Button { session.web.goBack() } label: { Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 18, height: 18).rotationEffect(.degrees(180)).frame(width: 44, height: 44) }.disabled(!session.canGoBack).accessibilityLabel("Página anterior")
                    Button { session.web.goForward() } label: { Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 18, height: 18).frame(width: 44, height: 44) }.disabled(!session.canGoForward).accessibilityLabel("Página siguiente")
                    Spacer()
                    Button("Cerrar") { dismiss() }.font(HarborTheme.font(14, weight: .medium)).frame(minHeight: 44)
                }.padding(.horizontal, 12)
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).toolbar(.hidden, for: .navigationBar)
        }.task { session.openIfNeeded() }.onDisappear { session.web.stopLoading(); session.loading = false }
    }
}
