import Foundation

struct MusicArtworkColour: Codable, Equatable, Sendable {
    let rgb: [Double]
    let darkInk: Bool
    var valid: Bool { Self.valid(rgb) }
    static func valid(_ values: [Double]) -> Bool {
        values.count == 3 && values.allSatisfy { $0.isFinite && (0...255).contains($0) }
    }
}

struct MusicArtworkPalette: Codable, Equatable, Sendable {
    let dominant: MusicArtworkColour?
    let palette: [[Double]]
    var valid: Bool {
        (dominant?.valid ?? true) && palette.count <= 3 && palette.allSatisfy(MusicArtworkColour.valid)
    }
}
