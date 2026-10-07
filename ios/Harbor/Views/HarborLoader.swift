import SwiftUI
import WebKit

struct HarborLoader: View {
    var caption: String? = nil
    var size: CGFloat = 128
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 12) {
            HarborLoaderArtwork(reduceMotion: reduceMotion).frame(width: size, height: size).accessibilityHidden(true)
            if let caption { Text(caption.uppercased()).font(HarborTheme.font(12.5, weight: .medium)).tracking(2.25).foregroundStyle(.white.opacity(0.7)) }
        }.allowsHitTesting(false)
    }
}

struct HarborLoaderArtwork: UIViewRepresentable {
    var reduceMotion = false
    static var index: URL? { Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "HarborLoader") }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false; web.backgroundColor = .clear; web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false; web.isUserInteractionEnabled = false
        web.navigationDelegate = context.coordinator
        if let index = Self.index { web.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent()) }
        return web
    }
    func makeCoordinator() -> Coordinator { Coordinator(reduceMotion: reduceMotion) }
    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.reduceMotion != reduceMotion else { return }
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.applyMotion(web)
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) { web.evaluateJavaScript("window.harborLoaderMotion?.destroy()", completionHandler: nil); web.stopLoading(); web.navigationDelegate = nil }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var reduceMotion: Bool
        init(reduceMotion: Bool) { self.reduceMotion = reduceMotion }
        func applyMotion(_ web: WKWebView) { web.evaluateJavaScript(reduceMotion ? "window.harborLoaderMotion?.stop()" : "window.harborLoaderMotion?.play()", completionHandler: nil) }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { applyMotion(webView) }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url, let folder = HarborLoaderArtwork.index?.deletingLastPathComponent(), url.isFileURL, url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/") else { return .cancel }
            return .allow
        }
    }
}

struct HarborPlaybackConnecting: View {
    let media: Media?
    var cancelIdentifier = "connecting-cancel"
    let cancel: () -> Void
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let media {
                Artwork(url: media.background, fallback: media.poster, fallbacks: [media.fallbackBackground].compactMap { $0 }, maxPixels: 1000)
                    .blur(radius: 20).overlay(.black.opacity(0.65)).ignoresSafeArea()
            }
            VStack(spacing: 20) {
                if let logo = media?.logo { Artwork(url: logo, fit: .fit, maxPixels: 650, showsPlaceholder: false).frame(maxWidth: 280).frame(height: 90) }
                else if let media { Text(media.name).font(.custom("Fraunces-9ptBlack", size: 30)).multilineTextAlignment(.center).foregroundStyle(.white) }
                HarborLoader(caption: "Conectando")
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack { Spacer(); Button("Cancelar", action: cancel).font(HarborTheme.font(13, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 20).frame(minHeight: 44).background(.white.opacity(0.12), in: .capsule).padding(.bottom, 28).accessibilityIdentifier(cancelIdentifier) }
        }.accessibilityIdentifier("player-connecting")
    }
}
