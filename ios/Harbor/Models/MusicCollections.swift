import Foundation
import Observation

enum MusicPersonalCollection: String, CaseIterable, Identifiable {
    case liked, recent
    var id: String { rawValue }
    var title: String { DesktopInterfaceText.value(self == .liked ? "Saved" : "Recently played") }
    var symbol: String { self == .liked ? "heart.fill" : "clock" }
}

struct MusicCollectionsDocument: Codable, Equatable, Sendable {
    var liked: [String] = []
    var recent: [String] = []
    func validated() throws -> Self {
        guard liked.count <= 10_000, recent.count <= 50,
              Set(liked).count == liked.count, Set(recent).count == recent.count,
              (liked + recent).allSatisfy({ !$0.isEmpty && $0.utf8.count <= 8192 && $0.rangeOfCharacter(from: .controlCharacters) == nil }),
              try JSONEncoder().encode(self).count <= 8 * 1024 * 1024 else { throw HarborError(code: "music-collections") }
        return self
    }
    func identifiers(_ collection: MusicPersonalCollection) -> [String] { collection == .liked ? liked : recent }
}

@MainActor protocol MusicCollectionsPersistence {
    func read(owner: String) throws -> MusicCollectionsDocument?
    func write(_ value: MusicCollectionsDocument, owner: String) throws
}
@MainActor private struct KeychainMusicCollections: MusicCollectionsPersistence {
    private func key(_ owner: String) -> String { "music-collections-" + EBookShelf.hash(owner) }
    func read(owner: String) throws -> MusicCollectionsDocument? { try KeychainStore().read(key(owner), as: MusicCollectionsDocument.self) }
    func write(_ value: MusicCollectionsDocument, owner: String) throws { try KeychainStore().write(value, key: key(owner)) }
}

@MainActor @Observable final class MusicCollections {
    static let shared = MusicCollections()
    private var documents: [String: MusicCollectionsDocument] = [:]
    private var likedIDSets: [String: Set<String>] = [:]
    private var readyOwners: Set<String> = []
    private(set) var errors: [String: String] = [:]
    @ObservationIgnored private let persistence: any MusicCollectionsPersistence
    init(persistence: (any MusicCollectionsPersistence)? = nil) { self.persistence = persistence ?? KeychainMusicCollections() }
    func prepare(owner: String) {
        guard !readyOwners.contains(owner), !owner.isEmpty, owner.utf8.count <= 512 else { return }
        do {
            let value = try (persistence.read(owner: owner) ?? MusicCollectionsDocument()).validated()
            documents[owner] = value; likedIDSets[owner] = Set(value.liked); readyOwners.insert(owner); errors[owner] = nil
        } catch { errors[owner] = "Could not read your saved tracks and listening history. Your data is preserved." }
    }
    func retry(owner: String) { readyOwners.remove(owner); prepare(owner: owner) }
    func isReady(owner: String) -> Bool { readyOwners.contains(owner) }
    func snapshot(owner: String) -> MusicCollectionsDocument? { isReady(owner: owner) ? documents[owner] : nil }
    func isLiked(_ id: String, owner: String) -> Bool { likedIDSets[owner]?.contains(id) == true }
    func records(_ collection: MusicPersonalCollection, library: [MusicRecord], owner: String) -> [MusicRecord] {
        let lookup = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (documents[owner]?.identifiers(collection) ?? []).compactMap { lookup[$0] }
    }
    @discardableResult func setLiked(_ id: String, liked: Bool, owner: String) -> Bool {
        change(owner: owner) { value in
            value.liked.removeAll { $0 == id }
            if liked { value.liked.insert(id, at: 0) }
        }
    }
    @discardableResult func recordPlayed(_ id: String, owner: String) -> Bool {
        change(owner: owner) { value in
            value.recent.removeAll { $0 == id }; value.recent.insert(id, at: 0)
            value.recent = Array(value.recent.prefix(50))
        }
    }
    private func change(owner: String, update: (inout MusicCollectionsDocument) -> Void) -> Bool {
        prepare(owner: owner)
        guard isReady(owner: owner), var value = documents[owner] else { return false }
        let previous = value; update(&value)
        do {
            value = try value.validated()
            if value != previous {
                try persistence.write(value, owner: owner); documents[owner] = value
                if value.liked != previous.liked { likedIDSets[owner] = Set(value.liked) }
            }
            errors[owner] = nil; return true
        } catch { errors[owner] = "Could not save your tracks or listening history. Try again."; return false }
    }
}
