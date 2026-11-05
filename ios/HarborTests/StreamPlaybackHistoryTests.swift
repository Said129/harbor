import XCTest
@testable import Harbor

/// Desktop's "Remember last stream" (`lib/playback-history.ts`).
final class StreamPlaybackHistoryTests: XCTestCase {
    private func offer(_ fields: [String: JSONValue]) -> StreamOffer { StreamOffer(id: 0, raw: .object(fields)) }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "owned.streams.history." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testEntriesAreKeyedPerEpisodeAndNeedBothNumbers() {
        XCTAssertEqual(StreamPlaybackHistory.key("tt1", season: 1, episode: 2), "tt1|s1e2")
        XCTAssertEqual(StreamPlaybackHistory.key("tt1", season: nil, episode: nil), "tt1")
        XCTAssertEqual(StreamPlaybackHistory.key("tt1", season: 1, episode: nil), "tt1")
        XCTAssertEqual(StreamPlaybackHistory.key("kitsu:9", season: 0, episode: 12), "kitsu:9|s0e12")
    }

    func testTheSameTorrentMatchesByHashAndFile() {
        let entry = StreamPlaybackEntry(offer(["infoHash": .string("AABBCC"), "fileIdx": .integer(3), "addonId": .string("a")]))
        XCTAssertTrue(entry.matches(offer(["infoHash": .string("aabbcc"), "fileIdx": .integer(3)])), "Hashes compare without case")
        XCTAssertFalse(entry.matches(offer(["infoHash": .string("aabbcc"), "fileIdx": .integer(4)])), "Another file of the torrent is another stream")
        XCTAssertTrue(entry.matches(offer(["infoHash": .string("aabbcc")])), "A stream without a file index still matches the hash")
        XCTAssertFalse(entry.matches(offer(["infoHash": .string("ddeeff"), "fileIdx": .integer(3)])))
        let unindexed = StreamPlaybackEntry(offer(["infoHash": .string("aabbcc")]))
        XCTAssertTrue(unindexed.matches(offer(["infoHash": .string("AABBCC"), "fileIdx": .integer(9)])))
        XCTAssertFalse(entry.matches(offer(["infoHash": .string("ddeeff"), "url": .string("https://x.example/a.mkv")])), "A different hash is decisive")
    }

    func testTheSameReleaseFromTheSameAddonMatchesWithoutAHash() {
        let fields: [String: JSONValue] = ["addonId": .string("a"), "parsedTitle": .string("Show"), "resolution": .string("1080p"), "source": .string("WEB-DL"), "size": .integer(100)]
        let entry = StreamPlaybackEntry(offer(fields))
        XCTAssertTrue(entry.matches(offer(fields)))
        func changed(_ key: String, _ value: JSONValue) -> StreamOffer { offer(fields.merging([key: value]) { $1 }) }
        XCTAssertFalse(entry.matches(changed("addonId", .string("b"))))
        XCTAssertFalse(entry.matches(changed("parsedTitle", .string("Other"))))
        XCTAssertFalse(entry.matches(changed("resolution", .string("720p"))))
        XCTAssertFalse(entry.matches(changed("source", .string("BluRay"))))
        XCTAssertFalse(entry.matches(changed("size", .integer(101))))
        var withoutSize = fields; withoutSize["size"] = nil
        XCTAssertTrue(entry.matches(offer(withoutSize)), "A missing size does not rule a release out")
        var withoutTitle = fields; withoutTitle["parsedTitle"] = nil
        XCTAssertFalse(entry.matches(offer(withoutTitle)))
    }

    func testAnAddressIsTheLastResort() {
        let entry = StreamPlaybackEntry(offer(["url": .string("https://cdn.example.org/a.mkv")]))
        XCTAssertTrue(entry.matches(offer(["url": .string("https://cdn.example.org/a.mkv"), "addonId": .string("z")])))
        XCTAssertFalse(entry.matches(offer(["url": .string("https://cdn.example.org/b.mkv")])))
        XCTAssertFalse(entry.matches(offer(["name": .string("No address")])))
        XCTAssertFalse(StreamPlaybackEntry(savedAt: 1).matches(offer(["url": .string("https://cdn.example.org/a.mkv")])), "An empty entry matches nothing")
    }

    func testAnEntryLastsThirtyDaysForItsProfileAndEpisode() {
        let defaults = isolatedDefaults(), now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = StreamPlaybackEntry(offer(["infoHash": .string("aabbcc")]), now: now)
        StreamPlaybackHistory.save(entry, metaID: "tt1", season: 1, episode: 2, owner: "owned-profile", defaults: defaults, now: now)
        XCTAssertEqual(StreamPlaybackHistory.entry(metaID: "tt1", season: 1, episode: 2, owner: "owned-profile", defaults: defaults, now: now), entry)
        XCTAssertNil(StreamPlaybackHistory.entry(metaID: "tt1", season: 1, episode: 3, owner: "owned-profile", defaults: defaults, now: now), "Another episode")
        XCTAssertNil(StreamPlaybackHistory.entry(metaID: "tt1", season: 1, episode: 2, owner: "other-profile", defaults: defaults, now: now), "Another profile")
        XCTAssertNotNil(StreamPlaybackHistory.entry(metaID: "tt1", season: 1, episode: 2, owner: "owned-profile", defaults: defaults, now: now.addingTimeInterval(29 * 86_400)))
        XCTAssertNil(StreamPlaybackHistory.entry(metaID: "tt1", season: 1, episode: 2, owner: "owned-profile", defaults: defaults, now: now.addingTimeInterval(31 * 86_400)))
        StreamPlaybackHistory.clear(metaID: "tt1", season: 1, episode: 2, owner: "owned-profile", defaults: defaults, now: now)
        XCTAssertNil(StreamPlaybackHistory.entry(metaID: "tt1", season: 1, episode: 2, owner: "owned-profile", defaults: defaults, now: now))
    }

    func testOnlyTheNewestTwoHundredEntriesAreKept() {
        let defaults = isolatedDefaults(), now = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<205 {
            let saved = now.addingTimeInterval(Double(index))
            StreamPlaybackHistory.save(StreamPlaybackEntry(offer(["infoHash": .string("hash\(index)")]), now: saved), metaID: "tt\(index)", season: nil, episode: nil,
                                       owner: "owned-profile", defaults: defaults, now: saved)
        }
        let later = now.addingTimeInterval(300)
        for index in 0..<5 {
            XCTAssertNil(StreamPlaybackHistory.entry(metaID: "tt\(index)", season: nil, episode: nil, owner: "owned-profile", defaults: defaults, now: later), "The oldest five are dropped")
        }
        for index in [5, 100, 204] {
            XCTAssertNotNil(StreamPlaybackHistory.entry(metaID: "tt\(index)", season: nil, episode: nil, owner: "owned-profile", defaults: defaults, now: later))
        }
    }
}
