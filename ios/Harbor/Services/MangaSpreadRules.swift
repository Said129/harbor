import Foundation

/// Desktop's book-mode spread rule (manga-reader/book-view.tsx and reader-utils.ts).
/// An aspect is page height over page width. Desktop samples a few pages, takes the lower median
/// and opens a page alone when that aspect is below 1.2 or above 1.9; mobile always opens single pages.
enum MangaSpreadRules {
    static let fallbackAspect = 1.4

    /// Desktop's sample positions: the first page and the 25%, 50% and 75% positions, without duplicates.
    static func sampleIndices(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var seen = Set<Int>()
        var indices: [Int] = []
        for index in [0, Int(Double(count) * 0.25), Int(Double(count) * 0.5), Int(Double(count) * 0.75)] where index < count {
            if seen.insert(index).inserted { indices.append(index) }
        }
        return indices
    }

    /// Desktop's sampledAspect: keep measured aspects above 0.2 and below 6, then take the lower median.
    static func representativeAspect(_ measured: [Double]) -> Double {
        let valid = measured.filter { $0 > 0.2 && $0 < 6 }.sorted()
        guard !valid.isEmpty else { return fallbackAspect }
        return valid[(valid.count - 1) / 2]
    }

    /// Desktop's singlePageMode, combined with singlePageModeIfMobile.
    static func singlePageMode(aspect: Double, isMobile: Bool) -> Bool {
        isMobile || aspect < 1.2 || aspect > 1.9
    }
}
