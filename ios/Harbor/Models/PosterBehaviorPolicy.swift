import Foundation

struct PosterDockTransform: Equatable, Sendable {
    enum Origin: String, Sendable { case left, center, right }
    var x: Double = 0
    var y: Double = 0
    var scale: Double = 1
    var origin: Origin = .center
    var zIndex: Double = 0
}

enum PosterBehaviorPolicy {
    static func transitionMilliseconds(_ value: Double) -> Double { value.isFinite ? min(1_500, max(250, value.rounded())) : 760 }
    static func dock(pointerX: Double?, frame: CGRect, viewport: CGRect, first: Bool, last: Bool, rtl: Bool) -> PosterDockTransform {
        guard let pointerX, pointerX.isFinite, frame.width > 0, viewport.width > 0 else { return .init() }
        let distance = pointerX - frame.midX
        let influence = max(0, 1 - abs(distance) / 190)
        guard influence > 0 else { return .init() }
        let smooth = sin(influence * .pi / 2), normalized = max(-1, min(1, distance / 190))
        var x = -normalized * 26 * smooth
        let left = frame.minX - viewport.minX, right = viewport.maxX - frame.maxX
        let rightEdge = right <= 36 || (last && !rtl && right <= 80) || (first && rtl && right <= 80)
        let leftEdge = left <= 36 || (last && rtl && left <= 80) || (first && !rtl && left <= 80)
        var origin: PosterDockTransform.Origin = .center
        if rightEdge && !leftEdge { origin = .right; x = min(0, x) }
        else if leftEdge && !rightEdge { origin = .left; x = max(0, x) }
        else if leftEdge && rightEdge { x = 0 }
        return .init(x: x, y: -7 * smooth, scale: 1 + 0.12 * smooth, origin: origin, zIndex: (1 + smooth * 99).rounded())
    }
    static func expandedWidth(posterHeight: Double) -> Double { posterHeight * 16 / 9 }
    static func suitableWideImage(width: Double, height: Double) -> Bool {
        let ratio = height > 0 ? width / height : 0
        return width >= 640 && height >= 360 && ratio >= 1.45 && ratio <= 2.2
    }
    static func scrollDelta(card: CGRect, viewport: CGRect, gutter: Double = 0) -> Double {
        let left = viewport.minX + max(0, gutter), right = viewport.maxX - max(0, gutter)
        if card.minX < left && card.maxX > right { return 0 }
        if card.maxX > right { return card.maxX - right }
        if card.minX < left { return card.minX - left }
        return 0
    }
    static func wideRung(_ value: String) -> String {
        value.replacingOccurrences(of: #"/t/p/[^/]+/"#, with: "/t/p/w1280/", options: .regularExpression)
    }
    static func artworkIdentity(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let components = URLComponents(string: value), let scheme = components.scheme, let host = components.host {
            var path = components.percentEncodedPath.replacingOccurrences(of: "\\", with: "/")
            if host.lowercased() == "image.tmdb.org" { path = path.replacingOccurrences(of: #"^/t/p/[^/]+/"#, with: "/t/p/{size}/", options: [.regularExpression, .caseInsensitive]) }
            let port = components.port.flatMap { ($0 == 80 && scheme.lowercased() == "http") || ($0 == 443 && scheme.lowercased() == "https") ? nil : ":\($0)" } ?? ""
            return scheme.lowercased() + "://" + host.lowercased() + port + path
        }
        return value.components(separatedBy: CharacterSet(charactersIn: "?#")).first?.replacingOccurrences(of: "\\", with: "/")
    }
    static func alternatives(_ values: [String], poster: String?, failed: Set<String> = []) -> [String] {
        let original = artworkIdentity(poster); var seen = Set<String>()
        return values.compactMap { raw in
            guard CardArtworkPolicy.image(raw) != nil, artworkIdentity(raw) != original else { return nil }
            let url = wideRung(raw)
            return !failed.contains(url) && seen.insert(url).inserted ? url : nil
        }
    }
}
