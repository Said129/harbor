import Foundation
import XCTest
@testable import Harbor

private actor OwnedLyricsNetwork: HarborNativeNetworkCalling {
    private(set) var requests: [HarborNetworkRequest] = []
    var gate: CheckedContinuation<Void, Never>?
    private var holding = false
    func hold() { holding = true }
    func release() { holding = false; gate?.resume(); gate = nil }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        if holding { await withCheckedContinuation { gate = $0 } }
        let body = """
        [{"duration":180,"syncedLyrics":"[00:01.50]First owned line\\n[00:10.00]Second owned line"},{"duration":240,"syncedLyrics":"[00:00]Wrong recording"}]
        """
        return .init(status: 200, ok: true, headers: [:], bodyBase64: Data(body.utf8).base64EncodedString(), url: request.url)
    }
}
@MainActor private final class OwnedLyricsScope { var value = PluginExecutionScope(owner: "owned-lyrics-" + UUID().uuidString, activation: UUID()) }

@MainActor final class MusicLyricsTests: XCTestCase {
    func testOriginalLRCParserAndNativeClockFollowForwardAndBackwardWithDuplicateStamps() async throws {
        let scope = OwnedLyricsScope(), client = MusicLyricsClient(scope: scope.value, currentScope: { scope.value })
        defer { client.dispose() }
        let value = try await client.query(["operation": .string("parse"), "lrc": .string("[00:01.5][00:05.25]Repeated\n[00:10.125]Later\n[ar:Owned]\n")])
        let lines = try value.decoded([MusicLyricLine].self)
        XCTAssertEqual(lines.map(\.at), [1.5, 5.25, 10.125])
        XCTAssertEqual(lines.map(\.text), ["Repeated", "Repeated", "Later"])
        for position in [0.0, 1.5, 8, 20, 2, -1] {
            let reference = try await client.query(["operation": .string("index"), "lines": try .encoded(lines), "position": .number(position)])
            XCTAssertEqual(MusicLyricsTiming.index(lines, at: position) ?? -1, reference.integer)
        }
    }
    func testActualLyricsRuntimeSelectsTheRecordingCachesItAndSendsNoPrivateStreamURL() async throws {
        let scope = OwnedLyricsScope(), network = OwnedLyricsNetwork()
        let client = MusicLyricsClient(scope: scope.value, currentScope: { scope.value }, transport: MusicLyricsTransport(network: network))
        defer { client.dispose() }
        let track = Harbor.MusicTrack(id: "owned:lyrics", connectorId: "subsonic", sourceId: "owned", playbackUrl: "https://private.invalid/private-token", title: "Owned Song", artist: "Owned Artist", album: nil, artwork: "", durationSeconds: 180, durationLabel: "3:00")
        let lines = try await client.load(track)
        XCTAssertEqual(lines?.first?.text, "First owned line")
        XCTAssertEqual(lines?.count, 2)
        let repeated = try await client.load(track); XCTAssertEqual(repeated, lines)
        let requests = await network.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].publicNetworkOnly)
        XCTAssertFalse(requests[0].url.contains("private"))
        XCTAssertEqual(URLComponents(string: requests[0].url)?.host, "lrclib.net")
        await network.hold()
        let other = Harbor.MusicTrack(id: "owned:new", connectorId: "catalog", sourceId: nil, playbackUrl: nil, title: "Other", artist: "Owned", album: nil, artwork: "", durationSeconds: 180, durationLabel: "3:00")
        let pending = Task { try await client.load(other) }
        for _ in 0..<100 { if await network.requests.count > 1 { break }; try await Task.sleep(for: .milliseconds(20)) }
        scope.value = .init(owner: "retired", activation: UUID()); await network.release()
        do { _ = try await pending.value; XCTFail("A departing owner must not publish lyrics") } catch is CancellationError { }
    }
}
