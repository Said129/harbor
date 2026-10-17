import Lottie
import SwiftUI

private struct NavigationIconPressedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var navigationIconPressed: Bool {
        get { self[NavigationIconPressedKey.self] }
        set { self[NavigationIconPressedKey.self] = newValue }
    }
}
struct HarborNavigationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.environment(\.navigationIconPressed, configuration.isPressed) }
}

enum DesktopNavigationAnimation {
    static let resources = ["home", "catalogs", "movies", "shows", "music", "anime", "manga", "ebook", "live-tv", "playlists", "calendar", "library", "collections", "downloads", "addons", "settings"]
    static func resource(for section: HarborSection) -> String? {
        switch section {
        case .live: "live-tv"
        case .vod: "playlists"
        case .downloads: "downloads"
        default: resources.contains(section.rawValue) ? section.rawValue : nil
        }
    }
    static func shouldPlay(enabled: Bool, reduceMotion: Bool, foreground: Bool, pressed: Bool, hovered: Bool) -> Bool {
        enabled && !reduceMotion && foreground && (pressed || hovered)
    }
}

struct SidebarNavigationIcon: View {
    let section: HarborSection
    let hovered: Bool
    let tint: Color
    @Environment(\.navigationIconPressed) private var pressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NativeNavigationIcon(resource: DesktopNavigationAnimation.resource(for: section), fallback: "nav-" + section.icon,
                             playing: DesktopNavigationAnimation.shouldPlay(enabled: InterfacePreferences.shared.navIconAnimations, reduceMotion: reduceMotion, foreground: scenePhase == .active, pressed: pressed, hovered: hovered),
                             loop: section == .shows, tint: UIColor(tint))
            .frame(width: 23, height: 23).accessibilityHidden(true).allowsHitTesting(false)
    }
}

private struct NativeNavigationIcon: UIViewRepresentable {
    let resource: String?
    let fallback: String
    let playing: Bool
    let loop: Bool
    let tint: UIColor
    func makeUIView(context: Context) -> NavigationIconHost { NavigationIconHost(frame: .zero) }
    func updateUIView(_ view: NavigationIconHost, context: Context) { view.configure(resource: resource, fallback: fallback, playing: playing, loop: loop, tint: tint) }
    static func dismantleUIView(_ view: NavigationIconHost, coordinator: ()) { view.stop() }
}

@MainActor private final class NavigationIconHost: UIView {
    private static var models: [String: LottieAnimation] = [:]
    private let fallback = UIImageView()
    private var animationView: LottieAnimationView?
    private var resource: String?
    private var imageName: String?
    private var wasPlaying = false
    private var color: UIColor?
    override init(frame: CGRect) {
        super.init(frame: frame)
        fallback.contentMode = .scaleAspectFit; addSubview(fallback)
        isUserInteractionEnabled = false; isAccessibilityElement = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews(); fallback.frame = bounds; animationView?.frame = bounds.insetBy(dx: 2, dy: 2)
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil { stop() }
        super.willMove(toWindow: newWindow)
    }
    func configure(resource: String?, fallback name: String, playing: Bool, loop: Bool, tint: UIColor) {
        if imageName != name { fallback.image = UIImage(named: name)?.withRenderingMode(.alwaysTemplate); imageName = name }
        fallback.tintColor = tint
        if self.resource != resource {
            stop(); animationView?.removeFromSuperview(); animationView = nil; color = nil; self.resource = resource
        }
        guard playing, let resource else { stop(); return }
        if animationView == nil {
            // Decode only the interacted icon, then share its immutable vector
            // model. Idle rows and the closed sidebar have no animation loop.
            let animation = Self.models[resource] ?? LottieAnimation.named(resource, bundle: .main, subdirectory: "DesktopAnimations/nav")
            guard let animation else { return }
            Self.models[resource] = animation
            let view = LottieAnimationView(animation: animation, configuration: LottieConfiguration(renderingEngine: .automatic))
            view.contentMode = .scaleAspectFit; view.backgroundBehavior = .stop
            view.isUserInteractionEnabled = false; view.isAccessibilityElement = false
            addSubview(view); animationView = view; setNeedsLayout()
        }
        guard let view = animationView else { return }
        if color?.isEqual(tint) != true {
            var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 1
            if tint.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                view.setValueProvider(ColorValueProvider(LottieColor(r: Double(red), g: Double(green), b: Double(blue), a: Double(alpha))), keypath: AnimationKeypath(keypath: "**.Color"))
            }
            color = tint
        }
        view.isHidden = false; fallback.isHidden = true
        if !wasPlaying {
            view.play(fromProgress: 0, toProgress: 1, loopMode: loop ? .loop : .playOnce)
            wasPlaying = true
        }
    }
    func stop() {
        if wasPlaying { animationView?.stop() }
        wasPlaying = false; animationView?.isHidden = true; fallback.isHidden = false
    }
}
