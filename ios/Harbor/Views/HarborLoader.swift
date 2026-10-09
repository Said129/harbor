import SwiftUI
import WebKit
import QuartzCore

struct HarborLoader: View {
    var caption: String? = nil
    var size: CGFloat = 128
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: 12) {
            HarborLoaderArtwork(reduceMotion: reduceMotion, isActive: scenePhase == .active).frame(width: size, height: size).accessibilityHidden(true)
            if let caption { Text(caption.uppercased()).font(HarborTheme.font(12.5, weight: .medium)).tracking(2.25).foregroundStyle(.white.opacity(0.7)) }
        }.allowsHitTesting(false)
    }
}

struct HarborLoaderArtwork: UIViewRepresentable {
    var reduceMotion = false
    var isActive = true
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
    func makeCoordinator() -> Coordinator { Coordinator(reduceMotion: reduceMotion, isActive: isActive) }
    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.reduceMotion != reduceMotion || context.coordinator.isActive != isActive else { return }
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.isActive = isActive
        context.coordinator.applyMotion(web)
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) { coordinator.stopClock(); web.evaluateJavaScript("window.harborLoaderMotion?.destroy()", completionHandler: nil); web.stopLoading(); web.navigationDelegate = nil }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var reduceMotion: Bool
        var isActive: Bool
        private weak var web: WKWebView?
        private var displayLink: CADisplayLink?
        private var started: CFTimeInterval = 0
        private var renderPending = false
        private var generation = 0
        init(reduceMotion: Bool, isActive: Bool) { self.reduceMotion = reduceMotion; self.isActive = isActive }
        func applyMotion(_ web: WKWebView) {
            stopClock()
            self.web = web
            guard !reduceMotion, isActive else {
                web.evaluateJavaScript("window.harborLoaderMotion?.stop()", completionHandler: nil)
                return
            }
            web.evaluateJavaScript("window.harborLoaderMotion?.play()", completionHandler: nil)
            started = CACurrentMediaTime()
            let link = CADisplayLink(target: ClockTarget(self), selector: #selector(ClockTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            displayLink = link
            link.add(to: .main, forMode: .common)
        }
        func stopClock() {
            displayLink?.invalidate(); displayLink = nil
            generation += 1; renderPending = false
        }
        fileprivate func render(_ link: CADisplayLink) {
            guard !renderPending, !reduceMotion, isActive, let web,
                  let window = web.window, !window.isHidden, !web.isHidden else { return }
            renderPending = true
            let current = generation
            let elapsed = max(0, link.timestamp - started)
            web.evaluateJavaScript("window.harborLoaderMotion?.render(\(elapsed))") { [weak self] _, _ in
                guard let self, self.generation == current else { return }
                self.renderPending = false
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { applyMotion(webView) }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url, let folder = HarborLoaderArtwork.index?.deletingLastPathComponent(), url.isFileURL, url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/") else { return .cancel }
            return .allow
        }
    }
    @MainActor private final class ClockTarget: NSObject {
        weak var coordinator: Coordinator?
        init(_ coordinator: Coordinator) { self.coordinator = coordinator }
        @objc func tick(_ link: CADisplayLink) { coordinator?.render(link) }
    }
}

struct HarborPlaybackConnecting: View {
    let media: Media?
    var cancelIdentifier = "connecting-cancel"
    let cancel: () -> Void
    @State private var logoLoaded = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                if let media {
                    Artwork(url: media.background, fallback: media.poster, fallbacks: [media.fallbackBackground].compactMap { $0 }, maxPixels: 1000)
                        .blur(radius: 20).overlay(.black.opacity(0.65)).ignoresSafeArea()
                }
                if geometry.size.width > geometry.size.height {
                    VStack(spacing: min(28, geometry.size.height * 0.055)) {
                        if let media {
                            ZStack {
                                if media.logo == nil || !logoLoaded {
                                    Text(media.name).font(HarborTheme.displayFont(32)).lineLimit(2).minimumScaleFactor(0.7)
                                        .multilineTextAlignment(.center).foregroundStyle(.white)
                                }
                                if let logo = media.logo {
                                    Artwork(url: logo, fit: .fit, maxPixels: 650, showsPlaceholder: false, onImageAvailability: { logoLoaded = $0 })
                                }
                            }.frame(maxWidth: min(400, geometry.size.width * 0.72)).frame(height: min(90, max(44, geometry.size.height * 0.22)))
                        }
                        HarborLoader(caption: DesktopInterfaceText.value("Connecting"), size: min(128, max(56, geometry.size.height * 0.25)))
                    }.padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 76)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                VStack {
                    Spacer()
                    Button(action: cancel) {
                        HStack(spacing: 8) {
                            Image("player-connecting-cancel").resizable().scaledToFit().frame(width: 14, height: 14).accessibilityHidden(true)
                            Text(DesktopInterfaceText.value("Cancel"))
                        }.font(HarborTheme.font(13.5, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 24).frame(minHeight: 44).background(Color(red: 52 / 255, green: 52 / 255, blue: 59 / 255), in: .capsule)
                    }.buttonStyle(.plain).padding(.bottom, 16).accessibilityIdentifier(cancelIdentifier)
                }
            }.accessibilityIdentifier("player-connecting")
        }.background { PlayerOrientationAnchor().allowsHitTesting(false) }
            .onChange(of: media?.logo) { _, _ in logoLoaded = false }
    }
}
