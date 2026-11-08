import Foundation

/// The chosen stream as the ad corpus needs it: Desktop's `PlayerStreamRef` fields plus the URL that plays.
/// Fields iOS does not carry for a stream stay nil, and the fingerprint falls through as Desktop does.
struct AdSkipStream: Equatable, Sendable {
    var infoHash: String?
    var fileIdx: Int?
    var releaseGroup: String?
    var size: Int64?
    var parsedTitle: String?
    var url: String

    init(infoHash: String? = nil, fileIdx: Int? = nil, releaseGroup: String? = nil, size: Int64? = nil, parsedTitle: String? = nil, url: String) {
        self.infoHash = infoHash; self.fileIdx = fileIdx; self.releaseGroup = releaseGroup
        self.size = size; self.parsedTitle = parsedTitle; self.url = url
    }

    /// Read from the addon stream object the picker chose (`StreamOffer.raw`). Desktop's `releaseGroup` is the
    /// normalised group (`stream.releaseGroupNormalized`), so that field is read here.
    init(offer raw: JSONValue, url: String) {
        self.init(infoHash: raw["infoHash"].string.flatMap { $0.isEmpty ? nil : $0 }, fileIdx: raw["fileIdx"].integer,
                  releaseGroup: raw["releaseGroupNormalized"].string, size: Self.bytes(raw["size"]), parsedTitle: raw["parsedTitle"].string, url: url)
    }

    /// A size as Desktop prints it in the release key: a whole number of bytes, or nil.
    static func bytes(_ value: JSONValue) -> Int64? {
        switch value {
        case .integer(let number): return number
        case .unsigned(let number): return Int64(exactly: number)
        case .number(let number):
            guard number.isFinite, number == number.rounded(.towardZero), abs(number) < 9e18 else { return nil }
            return Int64(number)
        case .string(let text): return Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }
}

/// Desktop's `lib/skip-intro/fingerprint.ts` as pure functions over plain values. The pair identifies the content
/// and the exact release being played; the corpus is keyed on it.
enum AdSkipFingerprint {
    struct Key: Equatable, Sendable {
        let content: String
        let source: String
    }

    /// The IMDb id when the content has one, else the meta id.
    static func contentKey(metaID: String, imdbID: String?) -> String {
        if let imdbID, imdbID.hasPrefix("tt") { return imdbID }
        return metaID
    }

    /// Desktop's `urlRip`: host and path, lowercased. A value that is not an absolute URL is cut to 120 characters.
    static func urlRip(_ url: String) -> String {
        guard let parts = URLComponents(string: url), let scheme = parts.scheme?.lowercased(), !scheme.isEmpty,
              let host = parts.host, !host.isEmpty else {
            return String(url.prefix(120)).lowercased()
        }
        // JavaScript's `URL.host` leaves out the default port of the scheme.
        let port = parts.port.flatMap { value -> Int? in
            (scheme == "https" && value == 443) || (scheme == "http" && value == 80) ? nil : value
        }
        let path = parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath
        let hostText = port.map { "\(host):\($0)" } ?? host
        return (hostText + path).lowercased()
    }

    /// Desktop's `sourceKey`: the info hash and file index, else the release group, size and parsed title, else the URL.
    static func sourceKey(infoHash: String?, fileIdx: Int?, releaseGroup: String?, size: Int64?, parsedTitle: String?, url: String) -> String {
        if let hash = infoHash?.lowercased(), !hash.isEmpty {
            return "ih_\(hash)_\(fileIdx ?? 0)"
        }
        let group = releaseGroup?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bytes = size ?? 0
        let title = parsedTitle?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !group.isEmpty || bytes != 0 || !title.isEmpty {
            return "rg_\(group)_\(bytes)_\(title)"
        }
        return "u_\(urlRip(url))"
    }

    /// Desktop's `fingerprint`: the content key and the source key of one playback.
    static func fingerprint(metaID: String, imdbID: String?, infoHash: String?, fileIdx: Int?, releaseGroup: String?,
                            size: Int64?, parsedTitle: String?, url: String) -> Key {
        Key(content: contentKey(metaID: metaID, imdbID: imdbID),
            source: sourceKey(infoHash: infoHash, fileIdx: fileIdx, releaseGroup: releaseGroup, size: size, parsedTitle: parsedTitle, url: url))
    }
}
