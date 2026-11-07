import Network
import SwiftUI
import WebKit

/// The network state the trailer policy reads. It follows the live path and is never persisted.
@MainActor @Observable final class HeroTrailerNetwork {
    static let shared = HeroTrailerNetwork()
    private(set) var expensive = false
    private(set) var constrained = false
    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            Task { @MainActor in
                self?.expensive = expensive
                self?.constrained = constrained
            }
        }
        monitor.start(queue: DispatchQueue(label: "harbor.hero-trailer.network"))
    }
}

/// A YouTube trailer that sits behind a hero slide or a detail backdrop while `HeroTrailerPolicy` allows it. Nothing is
/// rendered when the policy says no, so the artwork underneath stays on screen.
struct HeroTrailerBackdrop: View {
    enum Placement: Sendable { case hero, detail }
    let videoID: String?
    let placement: Placement
    var slideActive = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let preferences = HeroTrailerPreferences.shared
    private let network = HeroTrailerNetwork.shared

    var body: some View {
        if let url = playbackURL() {
            HeroTrailerWebView(url: url).accessibilityHidden(true).allowsHitTesting(false)
        }
    }

    private var enabled: Bool {
        placement == .hero ? preferences.heroTrailers : preferences.detailTrailerAutoplay
    }

    private var audible: Bool {
        placement == .hero ? preferences.heroTrailerAudio : preferences.detailTrailerAudio
    }

    private func playbackURL() -> URL? {
        guard let videoID else { return nil }
        let conditions = HeroTrailerPolicy.Conditions(
            enabled: enabled,
            hasTrailer: true,
            sceneActive: scenePhase == .active,
            slideActive: slideActive,
            reduceMotion: reduceMotion,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            expensiveNetwork: network.expensive,
            constrainedNetwork: network.constrained
        )
        guard HeroTrailerPolicy.shouldPlay(conditions) else { return nil }
        return HeroTrailerPolicy.embedURL(videoID: videoID, muted: HeroTrailerPolicy.muted(audioEnabled: audible))
    }
}

/// Plays the embed in a non-persistent, non-interactive web view. Navigation is limited to the two YouTube hosts.
private struct HeroTrailerWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.isUserInteractionEnabled = false
        web.navigationDelegate = context.coordinator
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.requested != url else { return }
        context.coordinator.requested = url
        web.load(URLRequest(url: url))
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading()
        web.navigationDelegate = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var requested: URL?
        private static let hosts: Set<String> = ["www.youtube-nocookie.com", "www.youtube.com"]

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.targetFrame?.isMainFrame ?? true else { return .allow }
            guard let target = action.request.url, target.scheme == "https", let host = target.host else { return .cancel }
            return Self.hosts.contains(host) ? .allow : .cancel
        }
    }
}
