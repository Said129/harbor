import XCTest
@testable import Harbor

/// Watch Together pure logic against Desktop 0.9.132: `src/lib/together/protocol.ts`, `invite.ts`, `source-match.ts`,
/// `seek-coalesce.ts`, `client.ts` (clock), and `views/player/hooks/use-room-sync.ts` (follower).
@MainActor final class TogetherTests: XCTestCase {
    private let banned: Set<Character> = ["0", "1", "I", "O"]

    func testRoomCodeNormalizesToAlphabetAndLength() {
        XCTAssertEqual(TogetherRoomCode.normalize("ab c-2 3!x"), "ABC23X")
        XCTAssertEqual(TogetherRoomCode.normalize("abcdefghij"), "ABCDEF")
        XCTAssertEqual(TogetherRoomCode.normalize("  !!  "), "")
    }

    func testGeneratedRoomCodeUsesDesktopAlphabet() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let code = TogetherRoomCode.generate(using: &generator)
            XCTAssertEqual(code.count, 6)
            XCTAssertTrue(code.allSatisfy { TogetherProtocol.roomCodeAlphabet.contains($0) })
            XCTAssertTrue(code.allSatisfy { !banned.contains($0) })
        }
    }

    func testHelloEncodesNullAvatarAsJSONNull() throws {
        let message = TogetherClientMessage.hello(name: "Ana", avatar: nil, color: "#7dd3fc")
        let text = try XCTUnwrap(TogetherJSON.text(from: message.json(room: "ABC23D", clientId: "me")))
        XCTAssertEqual(text, "{\"avatar\":null,\"clientId\":\"me\",\"color\":\"#7dd3fc\",\"name\":\"Ana\",\"room\":\"ABC23D\",\"t\":\"hello\"}")
    }

    func testSyncStateEncodesNullsAndOmitsUndefinedFields() {
        let state = TogetherSyncState(mediaId: "tt0111161", mediaTitle: "Film", episode: nil, posterUrl: nil,
                                      positionSeconds: 12.5, playing: true, speed: nil, source: nil,
                                      guestPick: nil, updatedAt: 1_000, updatedBy: "me", hostClientId: nil)
        let object = state.json
        XCTAssertTrue(object["episode"] is NSNull)
        XCTAssertTrue(object["posterUrl"] is NSNull)
        XCTAssertTrue(object["hostClientId"] is NSNull)
        XCTAssertNil(object["speed"])
        XCTAssertNil(object["source"])
        XCTAssertNil(object["guestPick"])
        XCTAssertEqual(TogetherSyncState(json: object), state)
    }

    func testCommandsEncodeAndDecodeBothWays() {
        let seek = TogetherRoomCommand.seek(positionSeconds: 42.5, seq: 7, at: 1_000)
        XCTAssertEqual(TogetherRoomCommand(json: seek.json), seek)
        XCTAssertEqual(seek.json["action"] as? String, "seek")
        XCTAssertEqual(TogetherRoomCommand.play.json["action"] as? String, "play")
        XCTAssertEqual(TogetherRoomCommand(json: ["action": "pause"]), TogetherRoomCommand.pause)
        XCTAssertNil(TogetherRoomCommand(json: ["action": "seek"]))
    }

    func testServerFramesDecodeAndUnknownFramesAreIgnored() {
        let joined = "{\"t\":\"joined\",\"room\":\"ABC23D\",\"participants\":[{\"id\":\"a\",\"name\":\"Ana\",\"joinedAt\":1,\"ready\":true}],\"state\":null,\"hostClientId\":\"a\",\"started\":false,\"srvAt\":5000,\"relayVersion\":11}"
        guard case .joined(let info)? = TogetherServerMessage.decode(joined) else {
            XCTFail("joined did not decode")
            return
        }
        XCTAssertEqual(info.room, "ABC23D")
        XCTAssertEqual(info.participants.map { $0.name }, ["Ana"])
        XCTAssertNil(info.state)
        XCTAssertEqual(info.relayVersion, 11)
        XCTAssertEqual(info.srvAt, 5000)
        let chat = "{\"t\":\"chat\",\"from\":\"a\",\"name\":\"Ana\",\"text\":\"hi\",\"at\":9}"
        XCTAssertEqual(TogetherServerMessage.decode(chat), TogetherServerMessage.chat(from: "a", name: "Ana", text: "hi", at: 9))
        XCTAssertNil(TogetherServerMessage.decode("{\"t\":\"cursor\",\"from\":\"b\",\"name\":\"B\",\"x\":1,\"y\":2,\"visible\":true,\"path\":\"/\"}"))
        XCTAssertNil(TogetherServerMessage.decode("not json"))
    }

    func testInviteBuildsLikeURLSearchParamsAndParsesBack() throws {
        let link = TogetherInviteLink.build(relayURL: "wss://relay.example.test/", roomCode: "abc23d")
        XCTAssertEqual(link, "https://app.harbor.site/?harbor-relay=wss%3A%2F%2Frelay.example.test%2F&harbor-room=ABC23D")
        let parsed = try XCTUnwrap(TogetherInviteLink.parse(link))
        XCTAssertEqual(parsed, TogetherJoinLink(relayURL: "wss://relay.example.test/", roomCode: "ABC23D"))
        XCTAssertNil(TogetherInviteLink.parse("https://app.harbor.site/?harbor-relay=https%3A%2F%2Frelay.example.test&harbor-room=ABC23D"))
        XCTAssertEqual(TogetherInviteLink.parse("harbor-relay=wss%3A%2F%2Frelay.example.test&harbor-room=abc%20def")?.roomCode, "ABCDEF")
    }

    func testJoinInputReadsCodesLinksAndBlank() {
        XCTAssertEqual(TogetherJoinInput.resolve("  abc-23 "), TogetherJoinInput.Resolution.room("ABC23"))
        XCTAssertEqual(TogetherJoinInput.resolve("   "), TogetherJoinInput.Resolution.empty)
        let link = TogetherInviteLink.build(relayURL: "wss://relay.example.test", roomCode: "ABC23D")
        let expected = TogetherJoinLink(relayURL: "wss://relay.example.test", roomCode: "ABC23D")
        XCTAssertEqual(TogetherJoinInput.resolve(link), TogetherJoinInput.Resolution.link(expected))
    }

    func testSourceDescriptorNormalizesAndKeepsOnlyValidHashes() {
        let input = TogetherSourceInput(parsedTitle: nil, title: " Film.2160p.REMUX ", resolution: "4K", sizeBytes: 1234.4,
                                        infoHash: "ABCDEF0123456789ABCDEF0123456789ABCDEF01", fileIdx: 2)
        let descriptor = TogetherSourceBuilder.descriptor(from: input, durationSec: 1234.56)
        XCTAssertEqual(descriptor, TogetherSourceDescriptor(title: "Film.2160p.REMUX", resolution: "2160p", sizeBytes: 1234,
                                                            infoHash: "abcdef0123456789abcdef0123456789abcdef01",
                                                            fileIdx: 2, durationSec: 1234.6))
        let invalid = TogetherSourceInput(parsedTitle: nil, title: nil, resolution: nil, sizeBytes: nil, infoHash: "xyz", fileIdx: 4)
        XCTAssertNil(TogetherSourceBuilder.descriptor(from: invalid, durationSec: nil))
    }

    func testSourceMatchScoresSameFileCloseAndUnrelated() {
        let host = TogetherSourceDescriptor(title: "Film 2020 1080p BluRay GROUP", resolution: "1080p",
                                            sizeBytes: 1_000_000_000, infoHash: "aaaaaaaaaaaaaaaa", fileIdx: 1, durationSec: nil)
        let same = TogetherMatchCandidate(infoHash: "AAAAAAAAAAAAAAAA", fileIdx: 1, resolution: "1080p",
                                          sizeBytes: 1_000_000_000, title: "Film 2020 1080p", releaseGroup: "GROUP")
        XCTAssertEqual(TogetherSourceMatch.score(same, host: host), 1512, accuracy: 0.0001)
        XCTAssertEqual(TogetherSourceMatch.badge(TogetherSourceMatch.score(same, host: host)), "same")

        let close = TogetherMatchCandidate(infoHash: nil, fileIdx: nil, resolution: "1080p", sizeBytes: 1_200_000_000,
                                           title: "Film 2020 1080p", releaseGroup: nil)
        XCTAssertEqual(TogetherSourceMatch.score(close, host: host), 200 + 150 * (1 - 0.2 / 0.35) + 72, accuracy: 0.0001)
        XCTAssertEqual(TogetherSourceMatch.badge(TogetherSourceMatch.score(close, host: host)), "close")

        let unrelated = TogetherMatchCandidate(infoHash: nil, fileIdx: nil, resolution: "720p", sizeBytes: nil,
                                               title: "Unrelated Show", releaseGroup: nil)
        XCTAssertEqual(TogetherSourceMatch.score(unrelated, host: host), 0, accuracy: 0.0001)
        XCTAssertNil(TogetherSourceMatch.badge(0))
    }

    func testSourceMatchSortIsStableForEqualScores() {
        let hash = "bbbbbbbbbbbbbbbb"
        let sorted = TogetherSourceMatch.sorted(["zero-a", "exact", "zero-b"],
                                                host: TogetherSourceDescriptor(infoHash: hash)) { name in
            name == "exact" ? TogetherMatchCandidate(infoHash: hash) : TogetherMatchCandidate()
        }
        XCTAssertEqual(sorted, ["exact", "zero-a", "zero-b"])
    }

    func testSeekCoalescerSendsFirstThenLatestOnce() {
        var coalescer = TogetherSeekCoalescer(seed: 100, intervalMs: 250)
        XCTAssertEqual(coalescer.push(10, nowMs: 1_000), TogetherSeekSend(positionSeconds: 10, seq: 101, at: 1_000))
        XCTAssertNil(coalescer.push(11, nowMs: 1_100))
        XCTAssertNil(coalescer.push(12, nowMs: 1_200))
        XCTAssertNil(coalescer.tick(nowMs: 1_100))
        XCTAssertEqual(coalescer.tick(nowMs: 1_250), TogetherSeekSend(positionSeconds: 12, seq: 102, at: 1_250))
        XCTAssertNil(coalescer.tick(nowMs: 1_500))
    }

    func testCommandSenderFlushesPendingSeekBeforeOtherCommands() {
        var sender = TogetherCommandSender(seed: 0)
        XCTAssertEqual(sender.send(.seek(positionSeconds: 5, seq: nil, at: nil), nowMs: 1_000),
                       [TogetherRoomCommand.seek(positionSeconds: 5, seq: 1, at: 1_000)])
        XCTAssertEqual(sender.send(.seek(positionSeconds: 9, seq: nil, at: nil), nowMs: 1_100), [])
        XCTAssertEqual(sender.send(.pause, nowMs: 1_150),
                       [TogetherRoomCommand.seek(positionSeconds: 9, seq: 2, at: 1_150), TogetherRoomCommand.pause])
    }

    func testClockOffsetFollowsPongsAndLocalizesStateTimes() {
        var clock = TogetherClockSync()
        clock.markPing(at: 1_000)
        clock.recordPong(srvAt: 5_000, nowMs: 1_100)
        XCTAssertEqual(clock.relayOffset ?? 0, 3_950, accuracy: 0.0001)
        XCTAssertEqual(clock.localize(srvAt: 6_000, nowMs: 2_000), 2_050, accuracy: 0.0001)

        clock.markPing(at: 2_000)
        clock.recordPong(srvAt: 6_100, nowMs: 2_100)
        XCTAssertEqual(clock.relayOffset ?? 0, 3_980, accuracy: 0.0001)

        clock.markPing(at: 0)
        clock.recordPong(srvAt: 1, nowMs: 20_000)
        XCTAssertEqual(clock.relayOffset ?? 0, 3_980, accuracy: 0.0001)

        var fresh = TogetherClockSync()
        XCTAssertEqual(fresh.localize(srvAt: 5_000, nowMs: 1_000), 1_000, accuracy: 0.0001)
        XCTAssertEqual(fresh.localize(srvAt: 6_000, nowMs: 9_999), 2_000, accuracy: 0.0001)
    }

    func testSyncTargetProjectsAgeWhilePlayingAndClampsToDuration() {
        var state = TogetherSyncState(mediaId: "tt1", positionSeconds: 100, playing: true, updatedAt: 10_000, updatedBy: "h")
        XCTAssertEqual(TogetherSync.target(state, durationSec: 7200, nowMs: 11_000), 101.4, accuracy: 0.0001)
        state.playing = false
        XCTAssertEqual(TogetherSync.target(state, durationSec: 7200, nowMs: 11_000), 100, accuracy: 0.0001)
        state.playing = true
        XCTAssertEqual(TogetherSync.target(state, durationSec: 100, nowMs: 10_000), 99.75, accuracy: 0.0001)
    }

    func testFollowerSeeksAndPlaysWhenHostPlaysAndGuestIsBehind() {
        var follower = PlaybackFollower()
        let state = TogetherSyncState(mediaId: "tt1", positionSeconds: 100, playing: true, updatedAt: 10_000, updatedBy: "host")
        let local = TogetherLocalPlayback(positionSeconds: 90, playing: false, rate: 1, durationSec: 7200, bufferedSec: 30, mediaMismatch: false)
        let decision = follower.follow(state, selfID: "me", local: local, nowMs: 10_000)
        XCTAssertEqual(decision.seekTo ?? -1, 100.4, accuracy: 0.0001)
        XCTAssertTrue(decision.play)
        XCTAssertFalse(decision.pause)
        XCTAssertNil(decision.setRate)
        XCTAssertTrue(follower.catchingUp)
    }

    func testFollowerIgnoresOwnStaleAndForeignStates() {
        var follower = PlaybackFollower()
        let local = TogetherLocalPlayback(positionSeconds: 10, playing: true, rate: 1, durationSec: 7200, bufferedSec: 30, mediaMismatch: false)
        let own = TogetherSyncState(mediaId: "tt1", positionSeconds: 99, playing: false, updatedAt: 10_000, updatedBy: "me")
        XCTAssertEqual(follower.follow(own, selfID: "me", local: local, nowMs: 10_000), PlaybackFollower.Decision())
        XCTAssertEqual(follower.lastAppliedAt, 0)

        let newer = TogetherSyncState(mediaId: "tt1", positionSeconds: 10, playing: true, updatedAt: 10_000, updatedBy: "host")
        _ = follower.follow(newer, selfID: "me", local: local, nowMs: 10_000)
        let stale = TogetherSyncState(mediaId: "tt1", positionSeconds: 50, playing: true, updatedAt: 9_000, updatedBy: "host")
        XCTAssertEqual(follower.follow(stale, selfID: "me", local: local, nowMs: 10_000), PlaybackFollower.Decision())

        let other = TogetherLocalPlayback(positionSeconds: 10, playing: true, rate: 1, durationSec: 7200, bufferedSec: 30, mediaMismatch: true)
        XCTAssertTrue(follower.follow(newer, selfID: "me", local: other, nowMs: 10_000).foreignMedia)
    }

    func testFollowerKeepsCatchingUpUntilBufferRecovers() {
        var follower = PlaybackFollower()
        let local = TogetherLocalPlayback(positionSeconds: 90, playing: true, rate: 1, durationSec: 7200, bufferedSec: 30, mediaMismatch: false)
        let first = TogetherSyncState(mediaId: "tt1", positionSeconds: 100, playing: true, updatedAt: 10_000, updatedBy: "host")
        _ = follower.follow(first, selfID: "me", local: local, nowMs: 10_000)
        XCTAssertTrue(follower.catchingUp)

        let slowBuffer = TogetherLocalPlayback(positionSeconds: 100.2, playing: true, rate: 1, durationSec: 7200, bufferedSec: 1, mediaMismatch: false)
        let second = TogetherSyncState(mediaId: "tt1", positionSeconds: 100, playing: true, updatedAt: 11_000, updatedBy: "host")
        XCTAssertEqual(follower.follow(second, selfID: "me", local: slowBuffer, nowMs: 11_000), PlaybackFollower.Decision())
        XCTAssertTrue(follower.catchingUp)
    }

    func testFollowerAppliesRateAndJoinAlignment() {
        var follower = PlaybackFollower()
        let local = TogetherLocalPlayback(positionSeconds: 50, playing: true, rate: 1, durationSec: 7200, bufferedSec: 30, mediaMismatch: false)
        let fast = TogetherSyncState(mediaId: "tt1", positionSeconds: 50, playing: true, speed: 2, updatedAt: 10_000, updatedBy: "host")
        XCTAssertEqual(follower.follow(fast, selfID: "me", local: local, nowMs: 10_000).setRate, 2)

        let paused = TogetherSyncState(mediaId: "tt1", positionSeconds: 50, playing: false, speed: 1.5, updatedAt: 10_000, updatedBy: "host")
        let joined = PlaybackFollower.joinAlignment(paused, local: local, nowMs: 10_000)
        XCTAssertEqual(joined?.setRate, 1.5)
        XCTAssertEqual(joined?.seekTo ?? -1, 50, accuracy: 0.0001)
        XCTAssertEqual(joined?.pause, true)
        let anonymous = TogetherSyncState(mediaId: nil, positionSeconds: 0, playing: false, updatedAt: 0, updatedBy: "host")
        XCTAssertNil(PlaybackFollower.joinAlignment(anonymous, local: local, nowMs: 0))
    }

    func testGuestPickFollowsTheNewestHostWord() {
        let stateFromHost = TogetherSyncState(mediaId: "tt1", positionSeconds: 0, playing: false, updatedAt: 1_000, updatedBy: "host")
        let snapshot = TogetherRoomSnapshot(state: .joined, room: "ABC23D", syncState: stateFromHost, hostClientId: "host")
        XCTAssertFalse(TogetherRoomDerive.guestPick(snapshot, clientId: "host", lastInvite: nil))
        XCTAssertFalse(TogetherRoomDerive.guestPick(snapshot, clientId: "guest", lastInvite: nil))
        let invite = TogetherLastInvite(key: "tt1||", at: 2_000, proto: 2, guestPick: true)
        XCTAssertTrue(TogetherRoomDerive.guestPick(snapshot, clientId: "guest", lastInvite: invite))
    }

    func testReconnectDelayCapsAtThirtySeconds() {
        XCTAssertEqual(TogetherReconnect.delayMs(attempt: 0, jitter: 0), 1_000, accuracy: 0.0001)
        XCTAssertEqual(TogetherReconnect.delayMs(attempt: 1, jitter: 0), 2_000, accuracy: 0.0001)
        XCTAssertEqual(TogetherReconnect.delayMs(attempt: 10, jitter: 0), 30_000, accuracy: 0.0001)
        XCTAssertEqual(TogetherReconnect.delayMs(attempt: 10, jitter: 1), 39_000, accuracy: 0.0001)
    }

    func testRelayAddressesAndVersionGate() {
        XCTAssertEqual(TogetherRelay.websocketURL(relay: "https://relay.example.test/", room: "ABCD23")?.absoluteString,
                       "wss://relay.example.test/r/ABCD23")
        XCTAssertEqual(TogetherRelay.healthBase("wss://relay.example.test/"), "https://relay.example.test")
        XCTAssertTrue(TogetherRelay.isPublic("wss://pub.harbor.site/"))
        XCTAssertFalse(TogetherRelayVersion.isOutdated(nil, relay: "wss://pub.harbor.site"))
        XCTAssertTrue(TogetherRelayVersion.isOutdated(10, relay: "wss://relay.example.test"))
        XCTAssertTrue(TogetherRelayVersion.isOutdated(nil, relay: "wss://relay.example.test"))
        XCTAssertFalse(TogetherRelayVersion.isOutdated(11, relay: "wss://relay.example.test"))
    }

    func testPreferenceDefaultsMatchDesktopAndKeysAreMirrored() {
        XCTAssertEqual(TogetherPreferences.defaultRelayURL, "")
        XCTAssertTrue(TogetherPreferences.defaultShareCursors)
        XCTAssertFalse(TogetherPreferences.defaultGuestsPick)
        XCTAssertTrue(ProfileSettingsStore.keys.contains("togetherRelayUrl"))
        XCTAssertTrue(ProfileSettingsStore.keys.contains("togetherShareCursors"))
        XCTAssertTrue(ProfileSettingsStore.keys.contains("togetherGuestsPick"))
    }
}

/// A socket the test drives by hand: open, receive, drop. Sent frames are kept as parsed dictionaries.
@MainActor final class FakeTogetherSocket: TogetherSocket {
    private let delegate: TogetherSocketDelegate
    private(set) var sent: [String] = []
    private(set) var closed = false

    init(delegate: TogetherSocketDelegate) {
        self.delegate = delegate
    }

    func send(_ text: String) {
        sent.append(text)
    }

    func close() {
        closed = true
    }

    func open() {
        delegate.togetherSocketDidOpen(self)
    }

    func receive(_ text: String) {
        delegate.togetherSocket(self, didReceive: text)
    }

    func drop() {
        delegate.togetherSocketDidClose(self)
    }

    var sentObjects: [[String: Any]] {
        sent.compactMap { TogetherJSON.object(from: $0) }
    }
}

@MainActor final class FakeTogetherSocketFactory: TogetherSocketFactory {
    private(set) var urls: [URL] = []
    private(set) var sockets: [FakeTogetherSocket] = []

    func makeSocket(url: URL, delegate: TogetherSocketDelegate) -> TogetherSocket {
        urls.append(url)
        let socket = FakeTogetherSocket(delegate: delegate)
        sockets.append(socket)
        return socket
    }
}

/// The client and session over a fake socket. No network, no sleeping: time is a variable the test moves.
@MainActor final class TogetherSocketTests: XCTestCase {
    private let joinedFrame = "{\"t\":\"joined\",\"room\":\"ABC23D\",\"participants\":[{\"id\":\"me\",\"name\":\"Ana\",\"joinedAt\":1,\"ready\":false},{\"id\":\"host\",\"name\":\"Ben\",\"joinedAt\":2,\"ready\":true}],\"state\":null,\"hostClientId\":\"host\",\"started\":false,\"srvAt\":2000,\"relayVersion\":11}"

    func testClientJoinsOverFakeSocketAndSendsHelloThenState() {
        let factory = FakeTogetherSocketFactory()
        let client = TogetherClient(relayURL: "wss://relay.example.test", clientId: "me", name: "Ana", factory: factory)
        var now = 1_000_000.0
        client.nowProvider = { now }
        client.join(room: "ABC23D")
        XCTAssertEqual(factory.urls.first?.absoluteString, "wss://relay.example.test/r/ABC23D")

        let socket = factory.sockets[0]
        socket.open()
        XCTAssertEqual(socket.sentObjects.first?["t"] as? String, "ping")
        let hello = socket.sentObjects.first { ($0["t"] as? String) == "hello" }
        XCTAssertEqual(hello?["name"] as? String, "Ana")
        XCTAssertEqual(hello?["room"] as? String, "ABC23D")

        socket.receive(joinedFrame)
        XCTAssertEqual(client.snapshot.state, .joined)
        XCTAssertEqual(client.snapshot.participants.count, 2)
        XCTAssertEqual(client.snapshot.hostClientId, "host")

        now += 100
        client.publishState(TogetherSyncState(mediaId: "tt1", positionSeconds: 30, playing: true, updatedAt: now, updatedBy: "me"))
        XCTAssertEqual(socket.sentObjects.last?["t"] as? String, "state")
    }

    func testClientRetriesThenGivesUpWithRelayMessage() {
        let factory = FakeTogetherSocketFactory()
        let client = TogetherClient(relayURL: "wss://relay.example.test", clientId: "me", name: "Ana", factory: factory)
        var now = 1_000_000.0
        client.nowProvider = { now }
        client.jitterProvider = { 0 }
        client.join(room: "ABC23D")
        factory.sockets[0].drop()
        XCTAssertEqual(client.snapshot.state, .connecting)

        now += 1_000
        client.tick()
        XCTAssertEqual(factory.sockets.count, 2)
        factory.sockets[1].drop()

        now += 2_000
        client.tick()
        XCTAssertEqual(factory.sockets.count, 3)
        factory.sockets[2].drop()

        now += 4_000
        client.tick()
        XCTAssertEqual(factory.sockets.count, 4)
        factory.sockets[3].drop()

        XCTAssertEqual(client.snapshot.state, .error)
        XCTAssertEqual(client.snapshot.lastError, TogetherRelayDiagnosis.message(healthStatus: nil))
        client.applyHealthProbe(status: 429)
        XCTAssertEqual(client.snapshot.lastError, TogetherRelayDiagnosis.message(healthStatus: 429))
    }

    func testClientStreamDeliversChatEvents() async {
        let factory = FakeTogetherSocketFactory()
        let client = TogetherClient(relayURL: "wss://relay.example.test", clientId: "me", name: "Ana", factory: factory)
        client.join(room: "ABC23D")
        factory.sockets[0].open()
        factory.sockets[0].receive(joinedFrame)
        factory.sockets[0].receive("{\"t\":\"chat\",\"from\":\"host\",\"name\":\"Ben\",\"text\":\"hi\",\"at\":9}")

        var iterator = client.events.makeAsyncIterator()
        var found: TogetherRoomEvent?
        for _ in 0..<100 {
            guard let event = await iterator.next() else { break }
            if case .chat = event {
                found = event
                break
            }
        }
        XCTAssertEqual(found, TogetherRoomEvent.chat(from: "host", name: "Ben", text: "hi", at: 9))
    }

    func testSessionJoinsAnnouncesAndFollowsOverFakeSocket() async throws {
        let suite = "TogetherTests-session"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("wss://relay.example.test", forKey: TogetherPreferences.Key.relayURL)
        let preferences = TogetherPreferences(defaults: defaults)
        let factory = FakeTogetherSocketFactory()
        let session = TogetherSession(preferences: preferences, factory: factory)

        XCTAssertTrue(session.join(code: "abc-23d"))
        XCTAssertEqual(factory.urls.first?.absoluteString, "wss://relay.example.test/r/ABC23D")
        let socket = factory.sockets[0]
        socket.open()
        socket.receive(joinedFrame)
        await waitUntil { session.snapshot.state == .joined }
        XCTAssertEqual(session.snapshot.state, .joined)

        session.announcePlayback(TogetherPlaybackSnapshot(mediaId: "tt1", mediaTitle: "Film", episode: nil, posterUrl: nil,
                                                          positionSeconds: 30, playing: true, speed: 1, source: nil))
        let state = socket.sentObjects.last { ($0["t"] as? String) == "state" }
        XCTAssertEqual((state?["state"] as? [String: Any])?["mediaId"] as? String, "tt1")

        session.sendCommand(.pause)
        XCTAssertEqual(socket.sentObjects.last?["t"] as? String, "cmd")

        socket.receive("{\"t\":\"chat\",\"from\":\"host\",\"name\":\"Ben\",\"text\":\"hello\",\"at\":9}")
        await waitUntil { session.chat.count == 1 }
        XCTAssertEqual(session.chat.first?.text, "hello")

        let hostState = TogetherSyncState(mediaId: "tt1", positionSeconds: 100, playing: true,
                                          updatedAt: TogetherClock.nowMs(), updatedBy: "host")
        let local = TogetherLocalPlayback(positionSeconds: 90, playing: false, rate: 1, durationSec: 7200,
                                          bufferedSec: 30, mediaMismatch: false)
        let decision = session.followHostState(hostState, local: local)
        XCTAssertNotNil(decision.seekTo)
        XCTAssertTrue(decision.play)

        defaults.removePersistentDomain(forName: suite)
    }

    /// Lets queued MainActor work (the session's event pump) run until the condition holds, or gives up.
    private func waitUntil(attempts: Int = 200, _ condition: () -> Bool) async {
        var remaining = attempts
        while !condition() && remaining > 0 {
            remaining -= 1
            await Task.yield()
        }
    }
}
