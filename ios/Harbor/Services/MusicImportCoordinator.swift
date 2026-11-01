import Foundation
import Observation

/// A departing profile's copy/rollback must finish before another workspace for
/// that same owner can reuse the content-addressed audio file.
@MainActor @Observable final class MusicImportCoordinator {
    static let shared = MusicImportCoordinator()
    private var owners: [String: UUID] = [:]
    @ObservationIgnored private var cancellations: [String: @MainActor () -> Void] = [:]
    func busy(_ owner: String) -> Bool { owners[owner] != nil }
    func acquire(_ owner: String, cancel: @escaping @MainActor () -> Void) -> UUID? {
        guard owners[owner] == nil else { return nil }
        let token = UUID(); owners[owner] = token; cancellations[owner] = cancel; return token
    }
    func contains(_ owner: String, token: UUID) -> Bool { owners[owner] == token }
    func release(_ owner: String, token: UUID) {
        guard owners[owner] == token else { return }
        cancellations[owner] = nil; owners[owner] = nil
    }
    func cancel(_ owner: String) { cancellations[owner]?() }
}

struct MusicLocalRecordIndex {
    private let ids: [String: MusicRecord]
    private let filenames: [String: MusicRecord]
    init(_ records: [MusicRecord]) {
        ids = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        filenames = Dictionary(records.map { ($0.filename, $0) }, uniquingKeysWith: { first, _ in first })
    }
    func record(_ track: MusicTrack) -> MusicRecord? {
        guard track.connectorId == "local" else { return nil }
        if let record = ids[track.id] { return record }
        guard let filename = track.sourceId, MusicFileService.validFilename(filename) else { return nil }
        return filenames[filename]
    }
}
