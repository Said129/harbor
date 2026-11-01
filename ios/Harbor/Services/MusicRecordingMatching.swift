import Foundation

enum MusicRecordingMatching {
    static func ranked(_ candidates: [MusicTrack], for requested: MusicTrack) async throws -> [MusicTrack] {
        var ranked: [(Int, Int, MusicTrack)] = []
        for start in stride(from: 0, to: candidates.count, by: 256) {
            try Task.checkCancellation()
            let slice = Array(candidates[start..<min(start + 256, candidates.count)])
            let scores: [Int?] = try await CoreBridge().call("musicScoreCandidates", ["track": try .encoded(requested), "candidates": try .encoded(slice)])
            guard scores.count == slice.count else { throw HarborError(code: "music-matching-response") }
            for (index, score) in scores.enumerated() { if let score { ranked.append((score, start + index, slice[index])) } }
        }
        return ranked.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 > $1.0 }.map(\.2)
    }
}
