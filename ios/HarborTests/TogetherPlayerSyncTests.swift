import XCTest
@testable import Harbor

/// A player the test moves by hand. Every action the sync takes is kept in `calls`.
@MainActor final class FakeTogetherPlayer: TogetherPlayerAdapter {
    var loaded = true
    var frameReady = true
    var position = 0.0
    var duration = 3_600.0
    var playing = true
    var rate = 1.0
    var bufferedSeconds = 30.0
    private(set) var calls: [String] = []
    private(set) var notice: String?

    func setRate(_ rate: Double) { self.rate = rate; calls.append("rate \(rate)") }
    func seek(to seconds: Double) { position = seconds; calls.append("seek \(Int(seconds))") }
    func play() { playing = true; calls.append("play") }
    func pause() { playing = false; calls.append("pause") }
    func showNotice(_ text: String?) { notice = text }
    func clearCalls() { calls = [] }
}

/// The player side of Watch Together over a fake relay socket. Time is a variable the test moves.
@MainActor final class TogetherPlayerSyncTests: XCTestCase {
    private let suite = "TogetherPlayerSyncTests"
    private var defaults: UserDefaults!
    private var factory: FakeTogetherSocketFactory!
    private var session: TogetherSession!
    private var player: FakeTogetherPlayer!
    private var driver: TogetherPlayerSyncDriver!
    private var socket: FakeTogetherSocket!
    private var clock = 0.0

    override func setUp() async throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("wss://relay.example.test", forKey: TogetherPreferences.Key.relayURL)
        defaults.set("me", forKey: TogetherPreferences.Key.clientID)
        factory = FakeTogetherSocketFactory()
        session = TogetherSession(preferences: TogetherPreferences(defaults: defaults), factory: factory)
        player = FakeTogetherPlayer()
        clock = TogetherClock.nowMs()
        driver = TogetherPlayerSyncDriver(together: session, player: player,
                                          identity: .init(mediaId: "tt1", title: "Film", poster: nil, episode: nil),
                                          now: { [unowned self] in self.clock })
    }

    override func tearDown() async throws {
        driver.stop()
        session.leaveRoom()
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: Helpers

    private func join(host: String, started: Bool, ready: Bool = false) async {
        XCTAssertTrue(session.join(code: "ABC23D"))
        socket = factory.sockets[0]
        socket.open()
        socket.receive("{\"t\":\"joined\",\"room\":\"ABC23D\",\"participants\":[{\"id\":\"me\",\"name\":\"Ana\",\"joinedAt\":1,\"ready\":\(ready)},{\"id\":\"host\",\"name\":\"Ben\",\"joinedAt\":2,\"ready\":\(ready)}],\"state\":null,\"hostClientId\":\"\(host)\",\"started\":\(started),\"srvAt\":2000,\"relayVersion\":11}")
        await waitUntil { self.session.snapshot.state == .joined }
        XCTAssertEqual(session.snapshot.state, .joined)
    }

    private func hostState(position: Double, playing: Bool, at: Double? = nil) -> String {
        "{\"t\":\"state\",\"state\":{\"mediaId\":\"tt1\",\"positionSeconds\":\(position),\"playing\":\(playing),\"speed\":1,\"updatedAt\":\(at ?? clock),\"updatedBy\":\"host\"}}"
    }

    private func receiveState(_ text: String, position: Double) async {
        socket.receive(text)
        await waitUntil { self.session.snapshot.syncState?.positionSeconds == position }
    }

    private func command(_ action: String, from sender: String = "guest", position: Double? = nil, seq: Int? = nil) async {
        let before = session.lastCommand?.id
        var body = "\"action\":\"\(action)\""
        if let position { body += ",\"positionSeconds\":\(position)" }
        if let seq { body += ",\"seq\":\(seq)" }
        socket.receive("{\"t\":\"cmd\",\"from\":\"\(sender)\",\"command\":{\(body)}}")
        await waitUntil { self.session.lastCommand?.id != before }
    }

    private func sentFrames(_ type: String) -> [[String: Any]] {
        socket.sentObjects.filter { ($0["t"] as? String) == type }
    }

    private func tick(advance: Double = 250) {
        clock += advance
        driver.tick()
    }

    private func waitUntil(attempts: Int = 400, _ condition: () -> Bool) async {
        var remaining = attempts
        while !condition() && remaining > 0 {
            remaining -= 1
            await Task.yield()
        }
    }

    // MARK: Guest

    func testGuestHoldsPausedInLobbyThenAlignsWhenTheHostStarts() async {
        await join(host: "host", started: false)
        player.playing = true
        tick()
        XCTAssertTrue(player.calls.contains("pause"))
        XCTAssertEqual(player.notice, DesktopInterfaceText.value(TogetherPlayerSyncDriver.waitingForHostNotice))
        XCTAssertEqual(sentFrames("ready").last?["ready"] as? Bool, true)

        await receiveState(hostState(position: 100, playing: true), position: 100)
        socket.receive("{\"t\":\"started\",\"started\":true}")
        await waitUntil { self.session.snapshot.started }
        player.clearCalls()
        tick()
        XCTAssertTrue(player.calls.contains("seek 100"), "\(player.calls)")
        XCTAssertTrue(player.calls.contains("play"), "\(player.calls)")
        XCTAssertNil(player.notice)
    }

    func testGuestFollowsALargeDriftAndLeavesASmallOneAlone() async {
        await join(host: "host", started: true)
        await receiveState(hostState(position: 100, playing: true), position: 100)
        tick()
        player.clearCalls()

        // The host moved to 100.0 + a little: the player is at 100.4 + age, well inside the tolerance.
        clock += 1_000
        await receiveState(hostState(position: 101, playing: true), position: 101)
        player.position = 101.5
        tick(advance: 0)
        XCTAssertTrue(player.calls.isEmpty, "\(player.calls)")

        clock += 1_000
        await receiveState(hostState(position: 300, playing: true), position: 300)
        tick(advance: 0)
        XCTAssertTrue(player.calls.contains("seek 300"), "\(player.calls)")
    }

    func testGuestAdoptsTheHostSpeedBeforeSeeking() async {
        await join(host: "host", started: true)
        let state = "{\"t\":\"state\",\"state\":{\"mediaId\":\"tt1\",\"positionSeconds\":50,\"playing\":true,\"speed\":1.5,\"updatedAt\":\(clock),\"updatedBy\":\"host\"}}"
        socket.receive(state)
        await waitUntil { self.session.snapshot.syncState?.speed == 1.5 }
        tick()
        XCTAssertEqual(player.calls.first, "rate 1.5", "\(player.calls)")
    }

    func testGuestIgnoresAnotherTitle() async {
        await join(host: "host", started: true)
        let state = "{\"t\":\"state\",\"state\":{\"mediaId\":\"tt999\",\"positionSeconds\":50,\"playing\":true,\"updatedAt\":\(clock),\"updatedBy\":\"host\"}}"
        socket.receive(state)
        await waitUntil { self.session.snapshot.syncState?.mediaId == "tt999" }
        tick()
        XCTAssertTrue(player.calls.isEmpty, "\(player.calls)")
    }

    func testGuestPauseGoesToTheHostAsACommandAndOlderStatesAreIgnored() async {
        await join(host: "host", started: true)
        await receiveState(hostState(position: 100, playing: true), position: 100)
        tick()
        // Leave the window that follows an applied decision, then take the baseline.
        tick(advance: 2_000)
        tick()
        player.clearCalls()

        player.playing = false
        tick()
        XCTAssertEqual((sentFrames("cmd").last?["command"] as? [String: Any])?["action"] as? String, "pause")

        // A heartbeat the host sent before it saw the command must not start the video again.
        await receiveState(hostState(position: 101, playing: true, at: clock - 500), position: 101)
        tick(advance: 0)
        XCTAssertFalse(player.calls.contains("play"), "\(player.calls)")

        // The host's answer to the command arrives after it and is consistent with the pause.
        await receiveState(hostState(position: 102, playing: false, at: clock + 10), position: 102)
        tick(advance: 0)
        XCTAssertFalse(player.calls.contains("play"), "\(player.calls)")
    }

    func testGuestSeekGoesToTheHost() async {
        await join(host: "host", started: true)
        await receiveState(hostState(position: 100, playing: true), position: 100)
        tick()
        tick(advance: 2_000)
        tick()
        player.position += 1.0
        tick()
        player.position = 900
        tick()
        let seeks = sentFrames("cmd").compactMap { $0["command"] as? [String: Any] }.filter { ($0["action"] as? String) == "seek" }
        XCTAssertEqual(seeks.last?["positionSeconds"] as? Double, 900)
    }

    // MARK: Host

    func testHostHoldsTheLobbyThenPlayStartsTheRoomAndHeartbeatsFollow() async {
        await join(host: "me", started: false, ready: true)
        player.playing = true
        player.position = 12
        tick()
        XCTAssertTrue(player.calls.contains("pause"))
        XCTAssertEqual(player.notice, DesktopInterfaceText.value(TogetherPlayerSyncDriver.everyoneLoadedNotice))
        XCTAssertTrue(sentFrames("start").isEmpty)

        tick(advance: 1_500)
        XCTAssertTrue(sentFrames("start").isEmpty, "a paused player has not been started by the host")

        player.playing = true
        tick()
        XCTAssertEqual(sentFrames("start").count, 1)
        XCTAssertNil(player.notice)

        tick(advance: 1_000)
        let last = sentFrames("state").last?["state"] as? [String: Any]
        XCTAssertEqual(last?["mediaId"] as? String, "tt1")
        XCTAssertEqual(last?["playing"] as? Bool, true)
        XCTAssertEqual(last?["positionSeconds"] as? Double, 12)
    }

    func testHostPublishesAtOnceWhenItPausesAndNotMoreThanOncePerSecondOtherwise() async {
        await join(host: "me", started: true)
        player.position = 20
        tick()
        let first = sentFrames("state").count
        tick()
        tick()
        XCTAssertEqual(sentFrames("state").count, first, "heartbeat is once per second")

        player.playing = false
        tick()
        let last = sentFrames("state").last?["state"] as? [String: Any]
        XCTAssertEqual(last?["playing"] as? Bool, false)
        XCTAssertGreaterThan(sentFrames("state").count, first)
    }

    func testHostAppliesGuestCommandsInOrderAndDropsStaleSeeks() async {
        await join(host: "me", started: true)
        player.position = 20
        tick()
        player.clearCalls()

        await command("pause")
        tick(advance: 0)
        XCTAssertEqual(player.calls, ["pause"])
        player.clearCalls()

        await command("seek", position: 500, seq: 1)
        tick(advance: 0)
        XCTAssertTrue(player.calls.isEmpty, "a seek waits for the debounce: \(player.calls)")
        tick(advance: 200)
        XCTAssertEqual(player.calls, ["seek 500"])
        player.clearCalls()

        await command("seek", position: 100, seq: 1)
        tick(advance: 400)
        XCTAssertTrue(player.calls.isEmpty, "the same sequence number is not applied twice: \(player.calls)")

        await command("seek", position: 700, seq: 2)
        await command("play")
        tick(advance: 0)
        XCTAssertEqual(player.calls, ["seek 700", "play"])
    }

    func testHostDoesNotReplayCommandsThatCameBeforeThePlayerOpened() async {
        await join(host: "me", started: true)
        await command("pause")
        // A driver for a player that opens after the command.
        let late = FakeTogetherPlayer()
        late.position = 10
        let lateDriver = TogetherPlayerSyncDriver(together: session, player: late,
                                                  identity: .init(mediaId: "tt1", title: nil, poster: nil, episode: nil),
                                                  now: { [unowned self] in self.clock })
        lateDriver.tick()
        lateDriver.tick()
        XCTAssertFalse(late.calls.contains("pause"), "\(late.calls)")
        lateDriver.stop()
    }

    func testNothingHappensOutsideARoomAndLeavingClearsTheNotice() async {
        XCTAssertFalse(driver.tick())
        XCTAssertTrue(player.calls.isEmpty)

        await join(host: "host", started: false)
        XCTAssertTrue(driver.tick())
        XCTAssertNotNil(player.notice)
        session.leaveRoom()
        await waitUntil { self.session.snapshot.state != .joined }
        XCTAssertFalse(driver.tick())
        XCTAssertNil(player.notice)
    }

    func testSessionKeepsTheLatestSixteenCommands() async {
        await join(host: "me", started: true)
        for index in 0..<20 { await command("seek", position: Double(index), seq: index + 1) }
        XCTAssertEqual(session.recentCommands.count, 16)
        XCTAssertEqual(session.lastCommand?.id, session.recentCommands.last?.id)
    }

    // MARK: The real player adapter

    func testPlayerStateAdapterReportsBufferAndOnlyRemovesItsOwnNotice() {
        let state = PlayerState()
        let adapter = PlayerStateAdapter(state: state)
        XCTAssertFalse(adapter.loaded)
        state.loaded = true
        state.duration = 100
        XCTAssertFalse(adapter.frameReady, "no picture yet")
        state.videoWidth = 1920
        state.videoHeight = 1080
        XCTAssertTrue(adapter.frameReady)

        state.position = 10
        XCTAssertEqual(adapter.bufferedSeconds, 30, "unknown cache counts as plenty")
        state.cacheEnd = 14.5
        XCTAssertEqual(adapter.bufferedSeconds, 4.5, accuracy: 0.001)
        state.cacheEnd = 5
        XCTAssertEqual(adapter.bufferedSeconds, 0)

        adapter.showNotice("Waiting")
        XCTAssertEqual(state.playbackIssue, "Waiting")
        state.playbackIssue = "Audio output lost"
        adapter.showNotice(nil)
        XCTAssertEqual(state.playbackIssue, "Audio output lost", "another message is not ours to clear")
        adapter.showNotice("Waiting")
        adapter.showNotice(nil)
        XCTAssertNil(state.playbackIssue)

        state.paused = true
        XCTAssertFalse(adapter.playing)
        state.error = "failed"
        XCTAssertFalse(adapter.loaded)
    }
}
