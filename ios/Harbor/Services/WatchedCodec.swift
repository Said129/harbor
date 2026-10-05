import Foundation

// Stremio indexes the bitfield by season, episode and release date, with an
// anchor into that order. The zlib wrapper is shared with the desktop client.
enum WatchedCodec {
    static func ordered(_ videos: [Episode]) -> [Episode] {
        videos.enumerated().sorted { a, b in
            if a.element.season != b.element.season { return (a.element.season ?? Int.min) < (b.element.season ?? Int.min) }
            if a.element.episode != b.element.episode { return (a.element.episode ?? Int.min) < (b.element.episode ?? Int.min) }
            let first = a.element.releaseDate ?? .distantPast, second = b.element.releaseDate ?? .distantPast
            return first == second ? a.offset < b.offset : first < second
        }.map(\.element)
    }
    static func decode(_ field: String?, videos: [Episode]) throws -> Set<String> {
        guard let field, !field.isEmpty else { return [] }
        let parts = field.components(separatedBy: ":")
        guard parts.count >= 3, let length = Int(parts[parts.count - 2]), length > 0, length <= 1_000_000,
              let compressed = Data(base64Encoded: parts.last ?? ""), compressed.count <= 128 * 1024 else { throw HarborError(code: "invalid-watched-state") }
        let anchor = parts.dropLast(2).joined(separator: ":")
        var bytes = [UInt8](repeating: 0, count: 128 * 1024)
        var count = uLongf(bytes.count)
        let status = bytes.withUnsafeMutableBufferPointer { output in
            compressed.withUnsafeBytes { input in
                uncompress(output.baseAddress, &count, input.bindMemory(to: UInt8.self).baseAddress, uLong(compressed.count))
            }
        }
        guard status == Z_OK else { throw HarborError(code: "invalid-watched-state") }
        let sorted = ordered(videos)
        let offset = length - (sorted.firstIndex { $0.id == anchor } ?? -1) - 1
        var watched = Set<String>()
        for (position, video) in sorted.enumerated() {
            let bit = position + offset
            if video.season != nil && video.episode != nil && bit >= 0 && bit < Int(count) * 8 && bytes[bit >> 3] & (1 << (bit & 7)) != 0 { watched.insert(video.watchedKey) }
        }
        return watched
    }
    static func encode(_ watched: Set<String>, videos: [Episode]) throws -> String {
        guard !videos.isEmpty, videos.count <= 1_000_000 else { throw HarborError(code: "invalid-watched-state") }
        let sorted = ordered(videos)
        var bytes = [UInt8](repeating: 0, count: (sorted.count + 7) / 8)
        var anchor = 0
        for (index, video) in sorted.enumerated() where video.season != nil && video.episode != nil && watched.contains(video.watchedKey) {
            bytes[index >> 3] |= 1 << (index & 7); anchor = index
        }
        var buffer = [UInt8](repeating: 0, count: Int(compressBound(uLong(bytes.count))))
        var count = uLongf(buffer.count)
        let status = buffer.withUnsafeMutableBufferPointer { output in
            bytes.withUnsafeBufferPointer { input in
                compress2(output.baseAddress, &count, input.baseAddress, uLong(bytes.count), Z_DEFAULT_COMPRESSION)
            }
        }
        guard status == Z_OK else { throw HarborError(code: "invalid-watched-state") }
        return "\(sorted[anchor].id):\(anchor + 1):\(Data(buffer.prefix(Int(count))).base64EncodedString())"
    }
}
