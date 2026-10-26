import Foundation

struct PosterCardConfiguration: Equatable, Sendable {
    enum Style: String, CaseIterable, Sendable { case poster, tv }
    enum LogoPosition: String, CaseIterable, Sendable { case bottomStart, center, bottomEnd }
    enum LoadEffect: String, CaseIterable, Sendable { case blur, fade, off }
    enum Quality: String, CaseIterable, Sendable { case balanced, high, max }
    static let sizes: [(label: String, scale: Double)] = [("Compact", 0.8), ("Dense", 0.9), ("Standard", 1), ("Balanced", 1.15), ("Comfort", 1.3), ("Large", 1.5)]
    static let radii: [(label: String, value: Double)] = [("Sharp", 0), ("Subtle", 6), ("Classic", 12), ("Rounded", 18), ("Pill", 28)]
    let style: Style
    let logoPosition: LogoPosition
    let scale: Double
    let radius: Double
    let effect: LoadEffect
    let quality: Quality
    init(style: String = "poster", logoPosition: String = "bottomStart", scale: Double = 1, radius: Double = 12, effect: String = "off", quality: String = "high") {
        self.style = Style(rawValue: style) ?? .poster
        self.logoPosition = LogoPosition(rawValue: logoPosition) ?? .bottomStart
        self.scale = scale.isFinite && scale > 0 ? scale : 1
        self.radius = radius.isFinite ? min(40, max(0, radius)) : 12
        self.effect = LoadEffect(rawValue: effect) ?? .off
        self.quality = Quality(rawValue: quality) ?? .high
    }
    var sizeIndex: Int { Self.sizes.indices.min { abs(Self.sizes[$0].scale - scale) < abs(Self.sizes[$1].scale - scale) } ?? 2 }
    var radiusLabel: String { Self.radii.min { abs($0.value - radius) < abs($1.value - radius) }?.label ?? "Classic" }
    var aspectRatio: Double { style == .tv ? 16.0 / 9 : 2.0 / 3 }
    var mobileGridMinimum: Double { style == .tv ? 318 : 106 }
    func gridMinimum(availableWidth: Double) -> Double { min(mobileGridMinimum * scale, max(1, availableWidth)) }
    func rowWidth(base: Double = 116) -> Double { (style == .tv ? 318 * base / 116 : base) * scale }
    func pixels(width: Double, displayScale: Double) -> Int {
        if quality == .max { return 0 }
        let longest = width * (style == .tv ? 1 : 1.5)
        let target = longest * max(1, displayScale) * (quality == .balanced ? 0.75 : 1)
        return Int(min(quality == .balanced ? 1_280 : 2_048, max(240, target.rounded(.up))))
    }
}
