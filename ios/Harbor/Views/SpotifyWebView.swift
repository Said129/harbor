import AVFoundation
import Observation
import SwiftUI
import WebKit

/// Spotify's own web player inside Harbor. Signing in happens on Spotify's page and is typed by
/// the person using it, so Harbor never handles the password; the page is not scripted or read.
@MainActor @Observable
final class SpotifyWebSession: NSObject, WKNavigationDelegate {
    private static var sessions: [String: SpotifyWebSession] = [:]
    static func forOwner(_ owner: String) -> SpotifyWebSession {
        if let session = sessions[owner] { return session }
        let session = SpotifyWebSession(owner: owner)
        sessions[owner] = session
        return session
    }
    static let home = URL(string: "https://open.spotify.com/")!
    /// The mobile page only offers "open in the app"; the desktop one is the player.
    static let desktopAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    /// Spotify pages and the sign-in providers it hands over to are all https; deep links are not followed.
    static func allows(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" || url.absoluteString == "about:blank"
    }
    let web: WKWebView
    var loading = false
    var error: String?
    var canGoBack = false
    var canGoForward = false
    private convenience init(owner: String) {
        let hex = Array(EBookShelf.hash("spotify-web|" + owner).prefix(32))
        let identifier = UUID(uuidString: String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-" + String(hex[12..<16]) + "-" + String(hex[16..<20]) + "-" + String(hex[20..<32]))!
        let configuration = WKWebViewConfiguration()
        // A store of its own keeps the Spotify login across launches without sharing it with other pages.
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: identifier)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        self.init(configuration: configuration)
    }
    init(configuration: WKWebViewConfiguration) {
        web = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        web.customUserAgent = Self.desktopAgent
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
    }
    func openIfNeeded() async {
        // Music keeps playing when the screen is left, so the session needs the playback category.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let blank = web.url == nil || web.url?.absoluteString == "about:blank"
        guard blank, !loading else { return }
        loading = true; error = nil
        web.load(URLRequest(url: Self.home))
    }
    func retry() async {
        if web.url == nil || web.url?.absoluteString == "about:blank" { await openIfNeeded() }
        else { error = nil; web.reload() }
    }
    /// Leaves the page, which also stops what it was playing.
    func stop() { web.load(URLRequest(url: URL(string: "about:blank")!)); loading = false }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        Self.allows(action.request.url) ? .allow : .cancel
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        (webView.uiDelegate as? WebPageController)?.cancelSiteDialog()
        loading = true; error = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func finish() { loading = false; canGoBack = web.canGoBack; canGoForward = web.canGoForward }
    private func fail(_ failure: Error) {
        finish()
        if (failure as NSError).code != NSURLErrorCancelled { error = DesktopInterfaceText.value("music.mobile.spotify.webError") }
    }
}

private struct SpotifyWebBrowser: UIViewControllerRepresentable {
    let session: SpotifyWebSession
    func makeUIViewController(context: Context) -> WebPageController {
        let controller = WebPageController(webView: session.web)
        controller.openWindow = { web, action in
            guard SpotifyWebSession.allows(action.request.url) else { return }
            _ = web.load(action.request)
        }
        return controller
    }
    func updateUIViewController(_ controller: WebPageController, context: Context) { }
    static func dismantleUIViewController(_ controller: WebPageController, coordinator: ()) {
        // The page outlives the screen so a song keeps playing; only the view is released.
        controller.detach()
    }
}

struct SpotifyWebView: View {
    @State private var session: SpotifyWebSession
    @MainActor init(owner: String) { _session = State(initialValue: SpotifyWebSession.forOwner(owner)) }
    var body: some View {
        VStack(spacing: 0) {
            if session.loading { ProgressView().progressViewStyle(.linear) }
            if let error = session.error {
                HStack { Text(error).font(.caption); Button(DesktopInterfaceText.value("Retry")) { Task { await session.retry() } } }.padding(10).foregroundStyle(.orange)
            }
            SpotifyWebBrowser(session: session)
            HStack(spacing: 4) {
                Button { session.web.goBack() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(!session.canGoBack).accessibilityLabel("Back")
                Button { session.web.goForward() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(!session.canGoForward).accessibilityLabel("Forward")
                Button { Task { await session.retry() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("Reload")
                Spacer()
                Button(role: .destructive) { session.stop() } label: { Image(systemName: "stop.circle").frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value("music.pause"))
            }.padding(.horizontal, 12)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle("Spotify").navigationBarTitleDisplayMode(.inline)
            .task { await session.openIfNeeded() }
            .accessibilityIdentifier("music-spotify-web")
    }
}
