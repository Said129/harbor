import Foundation

/// One production entry point for resume persistence and local viewing history.
/// Its personal owner is captured when playback starts, before asynchronous I/O.
@MainActor enum PlaybackProgressCommit {
    static func save(_ value: ResumeSnapshot, session: PlaybackSession, resume: ResumeStore, media: Media?, library: LibraryModel?) async throws -> Bool {
        guard session.progressEnabled, try await resume.save(session.target, snapshot: value) else { return false }
        library?.noteLocalProgress(session.target, snapshot: value, owner: session.owner)
        if let media, let library, let personalOwner = session.personalOwner {
            await library.saveLocalProgress(media, target: session.target, snapshot: value,
                source: session.source.via == "download" ? .local : .library, owner: session.owner, personalOwner: personalOwner)
        }
        return true
    }
}
