import XCTest
import Observation
import SwiftUI
import UIKit
@testable import Harbor

@MainActor @Observable private final class MountedSimklResume { var pending = true }
private struct MountedSimklPlayback: View {
    let state: PlayerState
    let resume: MountedSimklResume
    let session: PlaybackSession
    let library: LibraryModel
    let reporter: SimklWatchReporter
    var body: some View {
        Color.black.modifier(SimklPlaybackTracking(state: state, session: session, media: .init(id: "tt0123456", type: "movie", name: "Owned Movie"),
            library: library, resumePending: resume.pending, reporter: reporter))
    }
}
@MainActor final class SimklPlaybackMountTests: XCTestCase {
    func testMountedProductionModifierWaitsForResumeThenReportsActualStateChangesAndTheFinalHistoryOnUnmount() async throws {
        let defaults = UserDefaults.standard, old = defaults.object(forKey: "simklScrobbleEnabled")
        defer { if let old { defaults.set(old, forKey: "simklScrobbleEnabled") } else { defaults.removeObject(forKey: "simklScrobbleEnabled") } }
        defaults.set(true, forKey: "simklScrobbleEnabled")
        let account = SimklAccountStore(owner: "owned-mounted-tracking", persistence: OwnedSimklLibraryAccount()); try account.load()
        let queue = SimklPendingWatches(owner: account.owner, persistence: OwnedSimklPendingMemory()), clock = OwnedSimklClock()
        let replies = OwnedSimklReplies(Array(repeating: .init(status: 200, data: Data("{}".utf8)), count: 4)
            + [.init(status: 200, data: Data("{\"added\":{\"movies\":1}}".utf8))], clock: clock)
        let client = SimklClient(transport: { try await replies.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
        let reporter = SimklWatchReporter(account: account, queue: queue, client: client, active: { true })
        let session = PlaybackSession(source: .init(url: "https://owned.invalid/not-opened.mp4", headers: nil, subtitles: nil, via: "owned-state-fixture"),
            target: .init(id: "tt0123456"), startMs: 0, storageWarning: nil, progressEnabled: true)
        let state = PlayerState(), resume = MountedSimklResume(); state.loaded = true; state.duration = 1000; state.position = 990
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: MountedSimklPlayback(state: state, resume: resume, session: session, library: LibraryModel(), reporter: reporter))
        window.makeKeyAndVisible(); defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(300)); let waiting = await replies.requests; XCTAssertTrue(waiting.isEmpty)
        state.position = 100; resume.pending = false
        try await wait(replies, count: 1)
        state.position = 200; state.paused = true; try await wait(replies, count: 2)
        state.position = 950; state.paused = false; try await wait(replies, count: 3)
        window.rootViewController = UIHostingController(rootView: Color.clear)
        try await wait(replies, count: 5)
        let sent = await replies.requests; XCTAssertEqual(sent.map { $0.0.url!.path }, ["/scrobble/start", "/scrobble/pause", "/scrobble/start", "/scrobble/stop", "/sync/history"])
        let stop = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(sent[3].0.httpBody)); XCTAssertEqual(stop["progress"].integer, 100)
        for _ in 0..<100 { if queue.document?.entries.isEmpty == true { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(queue.document?.entries.isEmpty == true)
    }
    private func wait(_ replies: OwnedSimklReplies, count: Int) async throws {
        for _ in 0..<100 { if await replies.requests.count == count { return }; try await Task.sleep(for: .milliseconds(30)) }
        XCTFail("The real mounted SwiftUI playback state did not produce the expected reporting requests"); throw HarborError(code: "owned-tracking-mount")
    }
}
