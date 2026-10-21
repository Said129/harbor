import XCTest
@testable import Harbor

private actor StreamSourceSecrets: HarborPluginSecrets {
    private var values: [String: [String: String]] = [:]
    func stage(plugin: String, values: [String: String]) -> String { let id = UUID().uuidString; self.values[id] = values; return id }
    func read(plugin: String, revision: String) throws -> [String: String] {
        guard let value = values[revision] else { throw HarborPluginRepositoryError("plugin-secrets-missing") }; return value
    }
    func remove(plugin: String, revision: String) { values[revision] = nil }
}
private actor StreamSourceNetwork: HarborNativeNetworkCalling {
    private var held: CheckedContinuation<Void, Never>?
    private var released = false
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        if request.url.contains("/hold") && !released { await withCheckedContinuation { held = $0 } }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: Data("owned".utf8).base64EncodedString(), url: request.url)
    }
    func waitUntilHeld() async throws {
        for _ in 0..<150 { if held != nil { return }; try await Task.sleep(for: .milliseconds(20)) }
        throw HarborError(code: "owned-timeout")
    }
    func release() { released = true; held?.resume(); held = nil }
}
@MainActor private final class StreamSourceContext {
    var scope = PluginExecutionScope(owner: "owned-source-" + UUID().uuidString, activation: UUID())
}

@MainActor final class HarborPluginStreamSourceTests: XCTestCase {
    private let direct = #"var plugin={id:'owned',name:'Owned',streams:function(req){return {streams:[{url:'https://files.example.org/owned.m3u8',name:'Owned FHD',quality:'1080p',headers:{Referer:'https://files.example.org/player'},subtitles:[{url:'https://files.example.org/owned.srt',lang:'spa',title:'Owned Spanish'}]}]};}};"#

    func testOriginalWorkerHeaderOrderSurvivesThePoolAndAdapterHeaderLimit() async throws {
        let (source, _, _, _) = try await prepared([#"var plugin={id:'owned',name:'Owned',streams:function(){var h={Referer:'https://files.example.org/player','X-First':'owned'};for(var i=0;i<30;i++)h['X-N'+i]='v'+i;return [{url:'https://files.example.org/owned.m3u8',headers:h}];}};"#])
        defer { source.runtime.dispose(); source.manager.dispose(); source.adapter.clear() }
        let media = Media(id: "tt0137523", type: "movie", name: "Owned")
        let response = try await source.streams(media: media, videoID: media.id, episode: nil, startingPriority: 0, options: .init(), tmdbKey: "")
        let row = try XCTUnwrap(response.streams.first), headers = row["behaviorHints"]["proxyHeaders"]["request"]
        XCTAssertEqual(headers.objectValue.count, 24); XCTAssertEqual(headers["Referer"].string, "https://files.example.org/player")
        XCTAssertEqual(headers["X-First"].string, "owned"); XCTAssertEqual(headers["X-N21"].string, "v21"); XCTAssertEqual(headers["X-N22"], .null)
        let id = try XCTUnwrap(source.manager.document.plugins.first?.id)
        XCTAssertEqual(source.runtime.health[id]?.count, 1); XCTAssertEqual(source.manager.document.plugins.first?.failures, 0)
    }

    private func prepared(_ codes: [String], providerIndex: Int? = nil) async throws
        -> (HarborPluginStreamSource, StreamSourceContext, StreamSourceNetwork, URL) {
        let context = StreamSourceContext(), network = StreamSourceNetwork()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(context.scope.owner, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("catalog.json"), store = try HarborPluginCatalogStore(namespace: context.scope.owner, file: file)
        try await store.load()
        let url = "https://example.org/source/manifest.json"
        let rows: [JSONValue] = codes.indices.map { index in .object(["id": .string("source.\(index)"), "name": .string("Source \(index)"),
            "entry": .string("\(index).js"), "idPrefixes": .array([.string("kitsu:"), .string("tt"), .string("tmdb:")])]) }
        var manifest = try HarborPluginManifest.parse(.object(["name": .string("Owned repository"), "plugins": .array(rows)]), url: url)
        if let providerIndex { manifest.entries[providerIndex].format = .providerScript }
        try await store.saveRepository(.init(url: url, manifest: manifest, checkedAt: 1), revision: 0)
        for (index, entry) in manifest.entries.enumerated() {
            let before = try await store.snapshot()
            try await store.install(repository: url, entry: entry, code: codes[index], etag: nil, methods: ["streams"], time: 1, revision: before.revision)
        }
        let manager = HarborStreamPluginManager(namespace: context.scope.owner, scope: context.scope, currentScope: { context.scope }, store: store,
            client: .init(network: network), secrets: StreamSourceSecrets())
        try await manager.load()
        let runtime = HarborStreamPluginPool(manager: manager, currentScope: { context.scope }, gate: HarborPluginCallGate())
        manager.invalidateRuntime = { [weak runtime] id in runtime?.invalidate(id) }
        let namespace = context.scope.owner
        let resolver = HarborPluginMetadataResolver(defaultsName: namespace, fetchTMDB: { _, _, _ in nil }, fetchCinemeta: { _, _ in .object([:]) })
        addTeardownBlock { UserDefaults(suiteName: namespace)?.removePersistentDomain(forName: namespace) }
        return (.init(manager: manager, runtime: runtime, scope: context.scope, currentScope: { context.scope }, resolver: resolver,
            adapter: HarborPluginStreamAdapter()), context, network, file)
    }

    func testActualDetailSelectionMergesPluginWorkersThroughOriginalAdapterRankingAndDirectSubtitleResolution() async throws {
        let checked = #"var plugin={id:'owned',name:'Owned',streams:function(req){if(req.type!=='series'||req.season!==5||req.episode!==23||req.absoluteEpisode!==99||req.title!=='Owned show')throw new Error('owned-request-mismatch');return [{url:'https://files.example.org/owned.m3u8',quality:'1080p',headers:{Referer:'https://files.example.org/player'},subtitles:[{url:'https://files.example.org/owned.srt',lang:'spa',title:'Owned Spanish'}]}];}};"#
        let (source, context, _, _) = try await prepared([checked, #"var plugin={id:'bad',name:'Bad',streams:function(){throw new Error('owned failure');}};"#])
        defer { source.runtime.dispose(); source.manager.dispose(); source.adapter.clear() }
        let episode = Episode(id: "tt3398540:5:23", season: 5, episode: 23, displaySeason: 1, displayEpisode: 99, absoluteNumber: 99)
        let media = Media(id: "tt3398540", type: "series", name: "Owned show", releaseInfo: "2015", videos: [episode])
        let model = DetailModel(media, service: HarborService(), metadataLoaded: true, contextRevision: { context.scope.activation },
            pluginStreams: { media, videoID, episode, priority in try await source.streams(media: media, videoID: videoID,
                episode: episode, startingPriority: priority, options: .init(), tmdbKey: "") })
        await model.findStreams([], episode: episode)
        XCTAssertNil(model.error); XCTAssertEqual(model.offers.count, 1); XCTAssertEqual(model.warnings, ["plugin-source"])
        let offer = try XCTUnwrap(model.offers.first)
        XCTAssertEqual(offer.addonID, source.manager.document.plugins.first?.id)
        let resolved = try await HarborService().resolve(offer)
        XCTAssertEqual(resolved.url, "https://files.example.org/owned.m3u8")
        XCTAssertEqual(resolved.headers?["Referer"], "https://files.example.org/player")
        XCTAssertEqual(resolved.subtitles?.first?.url, "https://files.example.org/owned.srt")
        XCTAssertEqual(resolved.subtitles?.first?.lang, "spa")
        XCTAssertEqual(source.manager.document.plugins.last?.failures, 1)
    }

    func testRepositoryGroupingKeepsWorkingMembersAndSkipsProviderWithoutTMDBWithoutCountingFailure() async throws {
        let (source, _, _, _) = try await prepared([direct, "throw new Error('a skipped provider must never start');"], providerIndex: 1)
        defer { source.runtime.dispose(); source.manager.dispose(); source.adapter.clear() }
        let media = Media(id: "tt0133093", type: "movie", name: "Owned movie")
        let result = try await source.streams(media: media, videoID: media.id, episode: nil, startingPriority: 3,
            options: .init(groupByRepository: true), tmdbKey: "")
        XCTAssertEqual(result.streams.count, 1); XCTAssertTrue(result.errors.isEmpty)
        let id = "plugin-repo:" + HarborPluginManifest.repositoryKey("https://example.org/source/manifest.json")
        XCTAssertEqual(result.streams.first?["addonId"].string, id)
        XCTAssertEqual(result.streams.first?["addonName"].string, "Owned repository")
        XCTAssertEqual(result.streams.first?["addonPriority"].integer, 3)
        XCTAssertEqual(result.streams.first?["addonReturnIdx"].integer, 0)
        let skipped = try XCTUnwrap(source.manager.document.plugins.last)
        XCTAssertEqual(source.runtime.health[skipped.id]?.skipped, "plugin-tmdb-missing")
        XCTAssertEqual(skipped.failures, 0); XCTAssertFalse(skipped.autoPaused)
        XCTAssertEqual(source.runtime.residentWorkerCount, 1)
        let good = try XCTUnwrap(source.manager.document.plugins.first)
        XCTAssertEqual(source.runtime.health[good.id]?.count, 1)
        var plugins = source.manager.document.plugins
        plugins[0].entry.nsfw = true; plugins[1].repoDisabled = true
        XCTAssertTrue(HarborPluginSourceSelection.groups(plugins, type: "movie", ids: [media.id], options: .init(), startingPriority: 0).isEmpty)
        XCTAssertEqual(HarborPluginSourceSelection.groups(plugins, type: "movie", ids: [media.id], options: .init(hideAdult: false), startingPriority: 0).count, 1)
        XCTAssertTrue(HarborPluginSourceSelection.groups(plugins, type: "movie", ids: [media.id], options: .init(enabled: false, hideAdult: false), startingPriority: 0).isEmpty)
    }

    func testMasterPauseCancelsActiveProviderWithoutRemovingItOrBreakingSubsequentPlayback() async throws {
        let (source, _, network, _) = try await prepared([#"var plugin={id:'held',name:'Held',streams:async function(){await harbor.http('https://files.example.org/hold');return [{url:'https://files.example.org/owned.m3u8'}];}};"#])
        defer { source.runtime.dispose(); source.manager.dispose(); source.adapter.clear(); Task { await network.release() } }
        let media = Media(id: "tmdb:603", type: "movie", name: "Owned movie")
        let pending = Task { try await source.streams(media: media, videoID: media.id, episode: nil, startingPriority: 0, options: .init(), tmdbKey: "") }
        try await network.waitUntilHeld(); source.runtime.cancelCalls(); await network.release()
        do { _ = try await pending.value; XCTFail("Paused plugin returned") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(source.manager.document.plugins.count, 1); XCTAssertEqual(source.manager.document.plugins.first?.failures, 0)
        XCTAssertFalse(Task.isCancelled); XCTAssertTrue(source.manager.ready)
        XCTAssertEqual(source.runtime.residentWorkerCount, 0)
        do {
            let paused = try await source.streams(media: media, videoID: media.id, episode: nil, startingPriority: 0, options: .init(enabled: false), tmdbKey: "")
            XCTAssertTrue(paused.streams.isEmpty)
        } catch { XCTFail("The paused source lookup failed: \(error)"); return }
        do {
            let resumed = try await source.streams(media: media, videoID: media.id, episode: nil, startingPriority: 0, options: .init(), tmdbKey: "")
            XCTAssertEqual(resumed.streams.count, 1); XCTAssertTrue(resumed.errors.isEmpty)
        } catch { XCTFail("The fresh source lookup after resuming failed: \(error)") }
    }

    func testRetiringProfileWhileARealPluginRequestIsHeldCannotPublishSourcesOrPersistFailure() async throws {
        let (source, context, network, file) = try await prepared([#"var plugin={id:'held',name:'Held',streams:async function(){await harbor.http('https://files.example.org/hold');return [{url:'https://files.example.org/late.m3u8'}];}};"#])
        defer { source.runtime.dispose(); source.manager.dispose(); source.adapter.clear(); Task { await network.release() } }
        let before = try Data(contentsOf: file), media = Media(id: "tmdb:603", type: "movie", name: "Owned movie")
        let pending = Task { try await source.streams(media: media, videoID: media.id, episode: nil, startingPriority: 0, options: .init(), tmdbKey: "") }
        try await network.waitUntilHeld()
        context.scope = .init(owner: "other-owner", activation: UUID()); source.runtime.dispose(); source.manager.dispose(); await network.release()
        do { _ = try await pending.value; XCTFail("A retired profile returned plugin sources") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: file), before)
    }
}
