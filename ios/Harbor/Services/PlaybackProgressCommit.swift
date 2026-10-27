import Foundation

/// One production entry point for resume persistence and local viewing history.
/// Its personal owner is captured when playback starts, before asynchronous I/O.
@MainActor enum PlaybackProgressCommit {
    static func save(_ value: ResumeSnapshot, session: PlaybackSession, resume: ResumeStore, media: Media?, library: LibraryModel?) async throws -> Bool {
        guard session.progressEnabled, try await resume.save(session.target, snapshot: value) else { return false }
        var mirrorError: Error?
        if let stores = session.progressStores, stores.personalOwner == session.personalOwner {
            for mirror in [stores.personal, stores.shared] where mirror !== resume {
                do { _ = try await mirror.save(session.target, snapshot: value) } catch { mirrorError = error }
            }
        }
        library?.noteLocalProgress(session.target, snapshot: value, owner: session.owner, personalOwner: session.personalOwner)
        if let media, let library, let personalOwner = session.personalOwner {
            await library.saveLocalProgress(media, target: session.target, snapshot: value,
                source: session.source.via == "download" ? .local : .library, owner: session.owner, personalOwner: personalOwner)
        }
        if let mirrorError { throw mirrorError }
        return true
    }
    static func restart(session: PlaybackSession, resume: ResumeStore, timestampMs: UInt64) async throws {
        guard session.progressEnabled else { return }
        _ = try await resume.restart(session.target, timestampMs: timestampMs)
        if let stores = session.progressStores, stores.personalOwner == session.personalOwner {
            for mirror in [stores.personal, stores.shared] where mirror !== resume { _ = try await mirror.restart(session.target, timestampMs: timestampMs) }
        }
    }
}
