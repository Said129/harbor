import CryptoKit
import Foundation

struct SubsonicPairing: Codable, Equatable, Sendable {
    let baseUrl: String
    let username: String
    let salt: String
    let token: String
    static func salted(baseUrl: String, username: String, password: String, salt: String) -> Self {
        let token = Insecure.MD5.hash(data: Data((password + salt).utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(baseUrl: baseUrl, username: username, salt: salt, token: token)
    }
    func loaded() -> Self? {
        let values = [baseUrl,username,salt,token].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard values.allSatisfy({ !$0.isEmpty }) else { return nil }
        return .init(baseUrl: values[0], username: values[1], salt: values[2], token: values[3])
    }
    func endpoint(_ method: String, parameters: [(String,String)] = [], json: Bool = false) throws -> URL {
        guard var url = URLComponents(string: baseUrl + "/rest/" + method), ["http","https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { throw SubsonicMusicError.address }
        var pairs = [("u",username),("t",token),("s",salt),("v","1.16.1"),("c","Harbor")]
        if json { pairs.append(("f","json")) }; pairs += parameters
        let encoded = pairs.map { Self.form($0.0) + "=" + Self.form($0.1) }.joined(separator: "&")
        url.percentEncodedQuery = url.percentEncodedQuery.map { $0.isEmpty ? encoded : $0 + "&" + encoded } ?? encoded
        guard let result = url.url else { throw SubsonicMusicError.address }; return result
    }
    func cover(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "" }
        return (try? endpoint("getCoverArt", parameters: [("id",id),("size","512")]).absoluteString) ?? ""
    }
    static func bases(_ raw: String) throws -> [String] {
        var raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        guard !raw.isEmpty else { throw SubsonicMusicError.emptyAddress }
        let values = raw.contains("://") ? [raw] : ["https://" + raw,"http://" + raw] + (raw.contains(":") ? [] : ["http://" + raw + ":4533"])
        return try values.map { value in
            guard let url = URL(string: value) else { throw SubsonicMusicError.address }
            guard ["http","https"].contains(url.scheme?.lowercased() ?? "") else { throw SubsonicMusicError.scheme }
            guard url.host?.isEmpty == false else { throw SubsonicMusicError.host }
            var normalized = url.absoluteString; while normalized.hasSuffix("/") { normalized.removeLast() }; return normalized
        }
    }
    static func safeID(_ raw: String) throws -> String {
        var id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.hasPrefix("subsonic:") { id = String(id.dropFirst(9)) }
        guard !id.isEmpty, id.utf8.count <= 128, id.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { throw SubsonicMusicError.item }
        return id
    }
    private static func form(_ value: String) -> String {
        value.utf8.map { byte in
            if byte == 32 { return "+" }
            if (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || [42,45,46,95].contains(byte) { return String(UnicodeScalar(byte)) }
            return String(format: "%%%02X", byte)
        }.joined()
    }
}

enum SubsonicMusicError: Error, LocalizedError, Sendable {
    case address, emptyAddress, scheme, host, searchLength, item, disconnected, unreadable, rejected, network, storage
    case field(String)
    case http(Int), api(Int64, String?)
    var errorDescription: String? {
        switch self {
        case .address: "That music server address is not valid"
        case .emptyAddress: "Enter the address of your music server"
        case .scheme: "A music server address must start with http or https"
        case .host: "That music server address is missing a host"
        case .searchLength: "Music search is too long"
        case .field(let label): "Enter your music server \(label)"
        case .item: "That music server item is not available"
        case .disconnected: "Connect your music server first"
        case .unreadable: "Music server sent a response Harbor could not read"
        case .rejected: "Music server rejected the request"
        case .network: "Music server request failed: network connection unavailable"
        case .storage: "Harbor could not store this music server sign in"
        case .http(let status): "Music server returned HTTP \(status)"
        case .api(let code, let message):
            [40,41].contains(code) ? "Your music server rejected this sign in. Connect it again." : message.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "Music server error \(code)"
        }
    }
    var health: MusicSourceCandidate.Health {
        let text = (errorDescription ?? "").lowercased()
        return ["timed out","timeout","network","connection","dns","resolve host","offline","could not reach"].contains { text.contains($0) } ? .offline : .degraded
    }
}

private extension KeyedDecodingContainer {
    func subsonic<T: Decodable>(_ key: Key, default value: T) throws -> T { contains(key) ? try decode(T.self, forKey: key) : value }
}
struct SubsonicSong: Decodable, Sendable {
    let id: String, title: String
    let album: String?, artist: String?, coverArt: String?
    let duration: UInt64?, track: UInt32?, discNumber: UInt32?
    enum CodingKeys: String, CodingKey { case id,title,album,artist,coverArt,duration,track,discNumber }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); title = try c.subsonic(.title, default: "")
        album = try c.decodeIfPresent(String.self, forKey: .album); artist = try c.decodeIfPresent(String.self, forKey: .artist)
        coverArt = try c.decodeIfPresent(String.self, forKey: .coverArt); duration = try c.decodeIfPresent(UInt64.self, forKey: .duration)
        track = try c.decodeIfPresent(UInt32.self, forKey: .track); discNumber = try c.decodeIfPresent(UInt32.self, forKey: .discNumber)
    }
    func recording(_ pairing: SubsonicPairing) -> MusicTrack {
        let seconds = duration ?? 0
        return .init(id: "subsonic:" + id, connectorId: "subsonic", sourceId: id, playbackUrl: nil, title: title, artist: artist ?? "", album: album,
            artwork: pairing.cover(coverArt), durationSeconds: seconds, durationLabel: "\(seconds / 60):" + String(format: "%02llu", seconds % 60))
    }
}
struct SubsonicAlbum: Decodable, Sendable {
    let id: String, name: String
    let artist: String?, coverArt: String?
    let songCount: UInt32?, year: UInt32?
    enum CodingKeys: String, CodingKey { case id,name,artist,coverArt,songCount,year }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.subsonic(.name, default: "")
        artist = try c.decodeIfPresent(String.self, forKey: .artist); coverArt = try c.decodeIfPresent(String.self, forKey: .coverArt)
        songCount = try c.decodeIfPresent(UInt32.self, forKey: .songCount); year = try c.decodeIfPresent(UInt32.self, forKey: .year)
    }
    func reference(_ pairing: SubsonicPairing) -> MusicCatalogAlbum {
        .init(id: id, connectorId: "subsonic", title: name, artist: artist ?? "", artwork: pairing.cover(coverArt), year: year.map(Int.init), trackCount: songCount.map(Int.init))
    }
}
struct SubsonicArtist: Decodable, Sendable {
    let id: String, name: String
    let coverArt: String?, artistImageUrl: String?
    enum CodingKeys: String, CodingKey { case id,name,coverArt,artistImageUrl }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.subsonic(.name, default: "")
        coverArt = try c.decodeIfPresent(String.self, forKey: .coverArt); artistImageUrl = try c.decodeIfPresent(String.self, forKey: .artistImageUrl)
    }
    func reference(_ pairing: SubsonicPairing) -> MusicCatalogArtist {
        let cover = pairing.cover(coverArt), art = cover.isEmpty ? artistImageUrl : cover
        return .init(id: id, connectorId: "subsonic", name: name, artwork: art.flatMap { $0.isEmpty ? nil : $0 })
    }
}
struct SubsonicPlaylist: Decodable, Sendable {
    let id: String, name: String
    let coverArt: String?, comment: String?
    let songCount: UInt32?
    enum CodingKeys: String, CodingKey { case id,name,coverArt,comment,songCount }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.subsonic(.name, default: "")
        coverArt = try c.decodeIfPresent(String.self, forKey: .coverArt); comment = try c.decodeIfPresent(String.self, forKey: .comment)
        songCount = try c.decodeIfPresent(UInt32.self, forKey: .songCount)
    }
    func reference(_ pairing: SubsonicPairing) -> MusicCatalogPlaylist {
        let art = pairing.cover(coverArt), text = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(id: id, connectorId: "subsonic", name: name, artwork: art.isEmpty ? [] : [art], trackCount: songCount.map(Int.init), subtitle: text.flatMap { $0.isEmpty ? nil : $0 })
    }
}
struct SubsonicSearch: Decodable, Sendable {
    let artist: [SubsonicArtist], album: [SubsonicAlbum], song: [SubsonicSong]
    enum CodingKeys: String, CodingKey { case artist,album,song }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist = try c.subsonic(.artist, default: []); album = try c.subsonic(.album, default: []); song = try c.subsonic(.song, default: [])
    }
}

protocol SubsonicField: Sendable { static var name: String { get } }
enum SubsonicFields {
    enum Album: SubsonicField { static let name = "album" }
    enum Artist: SubsonicField { static let name = "artist" }
    enum Song: SubsonicField { static let name = "song" }
    enum Index: SubsonicField { static let name = "index" }
    enum Playlist: SubsonicField { static let name = "playlist" }
    enum Entry: SubsonicField { static let name = "entry" }
}
struct SubsonicItems<Item: Decodable & Sendable, Field: SubsonicField>: Decodable, Sendable {
    let values: [Item]
    private struct Key: CodingKey {
        let stringValue: String; let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { return nil }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self), key = Key(stringValue: Field.name)!
        values = try c.subsonic(key, default: [])
    }
}
struct SubsonicAPIError: Decodable, Sendable {
    let code: Int64, message: String?
    enum CodingKeys: String, CodingKey { case code,message }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.subsonic(.code, default: 0); message = try c.decodeIfPresent(String.self, forKey: .message)
    }
}
struct SubsonicEnvelope: Decodable, Sendable {
    let response: SubsonicBody
    enum CodingKeys: String, CodingKey { case response = "subsonic-response" }
}
struct SubsonicBody: Decodable, Sendable {
    let status: String
    let error: SubsonicAPIError?
    let artists: SubsonicItems<SubsonicItems<SubsonicArtist, SubsonicFields.Artist>, SubsonicFields.Index>?
    let artist: SubsonicItems<SubsonicAlbum, SubsonicFields.Album>?
    let album: SubsonicItems<SubsonicSong, SubsonicFields.Song>?
    let albumList2: SubsonicItems<SubsonicAlbum, SubsonicFields.Album>?
    let starred2: SubsonicItems<SubsonicSong, SubsonicFields.Song>?
    let playlists: SubsonicItems<SubsonicPlaylist, SubsonicFields.Playlist>?
    let playlist: SubsonicItems<SubsonicSong, SubsonicFields.Entry>?
    let searchResult3: SubsonicSearch?
    enum CodingKeys: String, CodingKey { case status,error,artists,artist,album,albumList2,starred2,playlists,playlist,searchResult3 }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.subsonic(.status, default: ""); error = try c.decodeIfPresent(SubsonicAPIError.self, forKey: .error)
        artists = try c.decodeIfPresent(SubsonicItems<SubsonicItems<SubsonicArtist, SubsonicFields.Artist>, SubsonicFields.Index>.self, forKey: .artists)
        artist = try c.decodeIfPresent(SubsonicItems<SubsonicAlbum, SubsonicFields.Album>.self, forKey: .artist)
        album = try c.decodeIfPresent(SubsonicItems<SubsonicSong, SubsonicFields.Song>.self, forKey: .album)
        albumList2 = try c.decodeIfPresent(SubsonicItems<SubsonicAlbum, SubsonicFields.Album>.self, forKey: .albumList2)
        starred2 = try c.decodeIfPresent(SubsonicItems<SubsonicSong, SubsonicFields.Song>.self, forKey: .starred2)
        playlists = try c.decodeIfPresent(SubsonicItems<SubsonicPlaylist, SubsonicFields.Playlist>.self, forKey: .playlists)
        playlist = try c.decodeIfPresent(SubsonicItems<SubsonicSong, SubsonicFields.Entry>.self, forKey: .playlist)
        searchResult3 = try c.decodeIfPresent(SubsonicSearch.self, forKey: .searchResult3)
    }
}
struct SubsonicAuthLogin: Decodable, Sendable {
    let username: String?, subsonicSalt: String?, subsonicToken: String?
}
struct MusicAudioStream: Equatable, Sendable {
    let url: URL
    let httpHeaders: [String: String]
    let mimeType: String
    let bitrate: UInt64
}
