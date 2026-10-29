import Libmpv
import XCTest
@testable import Harbor

@MainActor final class MusicPlaybackPreparationTests: XCTestCase {
    func testOriginalHeaderLimitsReachRealMPVAsAnUnmodifiedNativeStringArray() throws {
        let special = #"opaque,token=one\\two; quoted=\"three,four\""#
        let fields = try MusicStreamHeaders.fields(["Cookie": special, "User-Agent": "Owned/1.0"])
        XCTAssertEqual(fields.agent, "Owned/1.0"); XCTAssertEqual(fields.fields, ["Cookie: " + special])
        for headers in [["bad name": "value"], ["Good": "line\r\nInjected: true"], ["Good": "nul\0"], [String(repeating: "x", count: 129): "v"], ["Good": String(repeating: "a", count: 8193)], Dictionary(uniqueKeysWithValues: (0..<17).map { ("Owned-\($0)", "value") })] {
            XCTAssertThrowsError(try MusicStreamHeaders.fields(headers))
        }
        let handle = try XCTUnwrap(mpv_create()); defer { mpv_terminate_destroy(handle) }
        for (name, value) in [("config", "no"), ("terminal", "no"), ("msg-level", "all=no"), ("vo", "null"), ("vid", "no"), ("ao", "null")] {
            XCTAssertGreaterThanOrEqual(mpv_set_option_string(handle, name, value), 0)
        }
        XCTAssertGreaterThanOrEqual(mpv_initialize(handle), 0)
        try MusicStreamHeaders.apply(["Cookie": special, "User-Agent": "Owned/1.0"], to: handle, defaultAgent: "Owned/default")
        XCTAssertEqual(try headerFields(handle), ["Cookie: " + special])
        let agent = try XCTUnwrap(mpv_get_property_string(handle, "user-agent")); defer { mpv_free(agent) }
        XCTAssertEqual(String(cString: agent), "Owned/1.0")
        try MusicStreamHeaders.apply([:], to: handle, defaultAgent: "Owned/default")
        XCTAssertTrue(try headerFields(handle).isEmpty)
        let reset = try XCTUnwrap(mpv_get_property_string(handle, "user-agent")); defer { mpv_free(reset) }
        XCTAssertEqual(String(cString: reset), "Owned/default")
    }
    func testActualOwnerSessionPersistsSharedMetadataAndRetiresItsPrivateStreamLeaseOnCredentialOrProfileChange() async throws {
        let state = PreparationScope(), disk = PreparationMusicDisk(), pairing = PreparationPairingDisk()
        pairing.pairing = .salted(baseUrl: "https://owned.example.test", username: "owned", password: "owned", salt: "owned")
        let store = MusicPlaylistStore(owner: state.scope.owner, persistence: disk)
        let service = SubsonicMusicService(scope: state.scope, currentScope: { state.scope }, transport: PreparationNoExternalWire(), persistence: pairing)
        let session = MusicPlaybackSession(server: service, playlists: store, localRecords: { [] }, currentScope: { state.scope })
        let privateTrack = track("subsonic:song", connector: "subsonic")
        let privateStream = try await session.resolve(privateTrack)
        XCTAssertTrue(privateStream.valid()); XCTAssertEqual(store.tracks[privateTrack.id], privateTrack.playlistRecording(replacing: nil))
        XCTAssertEqual(privateStream.stream.url.host, "owned.example.test")
        service.cancelPendingConnection(); XCTAssertFalse(privateStream.valid())
        let direct = track("direct:song", connector: "direct", url: "https://owned.example.test/full-audio.wav")
        let directStream = try await session.resolve(direct); XCTAssertTrue(directStream.valid())
        XCTAssertEqual(directStream.stream.url.absoluteString, direct.playbackUrl)
        XCTAssertEqual(MusicPlaylistStore(owner: state.scope.owner, persistence: disk).tracks[direct.id]?.playbackUrl, direct.playbackUrl)
        let wrongOwner = MusicPlaybackSession(server: service, playlists: MusicPlaylistStore(owner: "wrong", persistence: PreparationMusicDisk()), localRecords: { [] }, currentScope: { service.scope })
        XCTAssertThrowsError(try wrongOwner.validate())
        disk.failWrite = true
        do { _ = try await session.resolve(track("direct:failed", connector: "direct", url: "https://owned.example.test/failed.wav")); XCTFail("Failed shared metadata writes must prevent admission") } catch { }
        XCTAssertEqual(store.tracks.count, 2); XCTAssertEqual(disk.document?.tracks.count, 2)
        disk.failWrite = false
        state.scope = .init(owner: "other", activation: UUID()); XCTAssertFalse(directStream.valid())
        do { _ = try await session.resolve(direct); XCTFail("A departed owner cannot resolve or remember another recording") } catch is CancellationError { }
        XCTAssertEqual(store.tracks.count, 2)
    }
    func testListeningUsesActualSmallPositionAdvancesAndOriginalHalfTrackOrFourMinuteThreshold() {
        XCTAssertEqual(MusicListening.increment(previous: nil, current: 10), 0)
        for (previous, current, expected) in [(1.0, 1.2, 0.2), (1, 3, 2), (1, 3.01, 0), (3, 1, 0), (1, 1, 0), (Double.nan, 2, 0), (1, Double.infinity, 0)] {
            XCTAssertEqual(MusicListening.increment(previous: previous, current: current), expected, accuracy: 0.00001)
        }
        XCTAssertFalse(MusicListening.shouldScrobble(listened: 149, duration: 300)); XCTAssertTrue(MusicListening.shouldScrobble(listened: 150, duration: 300))
        XCTAssertFalse(MusicListening.shouldScrobble(listened: 239, duration: 900)); XCTAssertTrue(MusicListening.shouldScrobble(listened: 240, duration: 900))
        XCTAssertFalse(MusicListening.shouldScrobble(listened: 239, duration: .nan)); XCTAssertTrue(MusicListening.shouldScrobble(listened: 240, duration: 0))
    }
    private func track(_ id: String, connector: String, url: String? = nil) -> MusicTrack {
        .init(id: id, connectorId: connector, sourceId: "song", playbackUrl: url, title: "Owned song", artist: "Owned artist", album: nil, artwork: "", durationSeconds: 8, durationLabel: "0:08")
    }
    private func headerFields(_ handle: OpaquePointer) throws -> [String] {
        var node = mpv_node()
        XCTAssertGreaterThanOrEqual(mpv_get_property(handle, "http-header-fields", MPV_FORMAT_NODE, &node), 0)
        defer { mpv_free_node_contents(&node) }
        XCTAssertEqual(node.format, MPV_FORMAT_NODE_ARRAY)
        let list = try XCTUnwrap(node.u.list)
        if list.pointee.num == 0 { return [] }
        let values = try XCTUnwrap(list.pointee.values)
        return try (0..<Int(list.pointee.num)).map { index in
            XCTAssertEqual(values[index].format, MPV_FORMAT_STRING)
            return String(cString: try XCTUnwrap(values[index].u.string))
        }
    }
}
@MainActor private final class PreparationScope { var scope = PluginExecutionScope(owner: "owned-music-preparation", activation: UUID()) }
@MainActor private final class PreparationMusicDisk: MusicPlaylistPersistence {
    var document: MusicPlaylistDocument?
    var failWrite = false
    func read(owner: String) throws -> MusicPlaylistDocument? { document }
    func write(_ value: MusicPlaylistDocument, owner: String) throws { if failWrite { throw HarborError(code: "music-store") }; document = value }
}
@MainActor private final class PreparationPairingDisk: SubsonicPairingPersistence {
    var pairing: SubsonicPairing?
    func read(owner: String) throws -> SubsonicPairing? { pairing }
    func write(_ pairing: SubsonicPairing, owner: String) throws { self.pairing = pairing }
    func remove(owner: String) throws { pairing = nil }
}
private struct PreparationNoExternalWire: MusicServiceHTTPTransport {
    func perform(_ request: URLRequest) async throws -> MusicServiceHTTPResponse {
        guard request.url?.lastPathComponent == "scrobble" else { XCTFail("Resolution must not request unowned audio"); throw SubsonicMusicError.network }
        return .init(status: 200, data: Data(#"{"subsonic-response":{"status":"ok"}}"#.utf8))
    }
}
