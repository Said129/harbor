import Foundation

struct HarborPluginStreamBatch: Sendable {
    var streams: [JSONValue] = []
    var errors: [String] = []
}

typealias HarborPluginStreamProvider = @MainActor @Sendable (Media, String, Episode?, Int) async throws -> HarborPluginStreamBatch

struct HarborPluginStreamOptions: Equatable, Sendable {
    var enabled = true
    var groupByRepository = false
    var blockTrackers = true
    var hideAdult = true
    @MainActor static func current(defaults: UserDefaults = .standard) -> Self {
        .init(enabled: defaults.object(forKey: "pluginsEnabled") as? Bool ?? true,
            groupByRepository: defaults.object(forKey: "pluginsGroupByRepo") as? Bool ?? false,
            blockTrackers: defaults.object(forKey: "blockTrackers") as? Bool ?? true,
            hideAdult: defaults.object(forKey: "hideContent.adult") as? Bool ?? true)
    }
}

struct HarborPluginSourceGroup: Sendable {
    let addonID: String
    let name: String
    let url: String
    let plugins: [HarborInstalledStreamPlugin]
    let pickedID: String
    let priority: Int
}

enum HarborPluginSourceSelection {
    static func groups(_ plugins: [HarborInstalledStreamPlugin], type: String, ids: [String],
        options: HarborPluginStreamOptions, startingPriority: Int) -> [HarborPluginSourceGroup] {
        guard options.enabled else { return [] }
        let runnable = plugins.filter { $0.runnable && !(options.hideAdult && $0.entry.nsfw) }
        var collections: [[HarborInstalledStreamPlugin]] = []
        for plugin in runnable {
            if options.groupByRepository, let index = collections.firstIndex(where: { $0.first?.repoURL == plugin.repoURL }) {
                collections[index].append(plugin)
            } else { collections.append([plugin]) }
        }
        let prefixes = ["kitsu", "mal", "anidb", "anilist", "tt", "tmdb"]
        let ordered = ids.enumerated().sorted { a, b in
            let left = prefixes.firstIndex(where: a.element.hasPrefix) ?? 999, right = prefixes.firstIndex(where: b.element.hasPrefix) ?? 999
            return left == right ? a.offset < b.offset : left < right
        }.map(\.element)
        return collections.enumerated().compactMap { index, members in
            guard let first = members.first else { return nil }
            let types = Set(members.flatMap { $0.entry.types }), accepted = members.flatMap { $0.entry.idPrefixes }
            // The reference falls back to any declared stream type when a scheme matches.
            guard !types.isEmpty, let picked = ordered.first(where: { id in accepted.isEmpty || accepted.contains(where: id.hasPrefix) }) else { return nil }
            let addonID = options.groupByRepository ? "plugin-repo:" + HarborPluginManifest.repositoryKey(first.repoURL) : first.id
            let name = options.groupByRepository ? first.repoName : first.entry.name
            let path = options.groupByRepository ? "repo/" + HarborPluginManifest.repositoryKey(first.repoURL) : first.id
            return .init(addonID: addonID, name: name, url: "harbor-plugin://" + path, plugins: members, pickedID: picked, priority: startingPriority + index)
        }
    }
}

/// Plugin transports never enter HTTP resource planning. Their normalized results join ranking directly.
@MainActor struct HarborPluginStreamSource {
    let manager: HarborStreamPluginManager
    let runtime: HarborStreamPluginPool
    let scope: PluginExecutionScope
    let currentScope: @MainActor () -> PluginExecutionScope
    var resolver: HarborPluginMetadataResolver = .shared
    var adapter: HarborPluginStreamAdapter = .shared

    func streams(media: Media, videoID: String, episode: Episode?, startingPriority: Int,
        options: HarborPluginStreamOptions, tmdbKey: String) async throws -> HarborPluginStreamBatch {
        try validate()
        let ids = StreamRequestPolicy.ids(media, videoID: videoID, season: episode?.season, episode: episode?.episode)
        let groups = HarborPluginSourceSelection.groups(manager.document.plugins, type: media.type == "anime" ? "series" : media.type,
            ids: ids, options: options, startingPriority: startingPriority)
        return try await withThrowingTaskGroup(of: (Int, HarborPluginStreamBatch).self) { tasks in
            for (index, group) in groups.enumerated() {
                tasks.addTask { (index, try await self.run(group, media: media, ids: ids, episode: episode, options: options, tmdbKey: tmdbKey)) }
            }
            var answers: [(Int, HarborPluginStreamBatch)] = []
            for try await answer in tasks { answers.append(answer) }
            try validate()
            let ordered = answers.sorted { $0.0 < $1.0 }.map(\.1)
            return .init(streams: ordered.flatMap(\.streams), errors: ordered.flatMap(\.errors))
        }
    }

    private func run(_ group: HarborPluginSourceGroup, media: Media, ids: [String], episode: Episode?,
        options: HarborPluginStreamOptions, tmdbKey: String) async throws -> HarborPluginStreamBatch {
        let request = try await HarborPluginStreamRequest.build(media: media, ids: ids, pickedID: group.pickedID,
            episode: episode, tmdbKey: tmdbKey, resolver: resolver)
        try validate()
        return try await withThrowingTaskGroup(of: (Int, HarborPluginStreamBatch).self) { tasks in
            for (index, plugin) in group.plugins.enumerated() {
                tasks.addTask { (index, try await self.run(plugin, group: group, request: request, options: options)) }
            }
            var answers: [(Int, HarborPluginStreamBatch)] = []
            for try await answer in tasks { answers.append(answer) }
            try validate()
            let ordered = answers.sorted { $0.0 < $1.0 }.map(\.1)
            let streams = ordered.flatMap(\.streams).enumerated().map { index, value in
                var value = value.objectValue; value["addonPriority"] = .integer(Int64(group.priority)); value["addonReturnIdx"] = .integer(Int64(index))
                return JSONValue.object(value)
            }
            return .init(streams: streams, errors: ordered.flatMap(\.errors))
        }
    }
    private func run(_ plugin: HarborInstalledStreamPlugin, group: HarborPluginSourceGroup, request: JSONValue,
        options: HarborPluginStreamOptions) async throws -> HarborPluginStreamBatch {
        try validate()
        guard sameInstallation(plugin) else { return .init() }
        if plugin.entry.format == .providerScript, request["tmdb"] == .null {
            runtime.recordSkip(plugin.id, title: request["title"].string, reason: "plugin-tmdb-missing")
            return .init()
        }
        do {
            let timeout = min(22, (plugin.entry.timeoutMs ?? 22_000) / 1000)
            let reply = try await runtime.run(plugin.id, request: request, timeout: timeout, jsonResult: true)
            guard let raw = reply.string else { throw HarborPluginRuntimeError("plugin-adapter-result") }
            try validate()
            guard sameInstallation(plugin) else { return .init() }
            let context = HarborPluginStreamContext(request: request, addonID: group.addonID, addonName: group.name,
                addonURL: group.url, pluginName: plugin.entry.name)
            let streams = try await adapter.mapJSON(raw, context: context, blockTrackers: options.blockTrackers)
            try validate()
            guard sameInstallation(plugin) else { return .init() }
            return .init(streams: streams)
        } catch is CancellationError {
            try validate()
            // Removing one provider retires that provider, not the other repository members.
            if !sameInstallation(plugin) { return .init() }
            throw CancellationError()
        } catch {
            try validate(); return .init(errors: ["plugin-source"])
        }
    }
    private func sameInstallation(_ plugin: HarborInstalledStreamPlugin) -> Bool {
        guard let fresh = manager.document.plugins.first(where: { $0.id == plugin.id }) else { return false }
        return fresh.runnable && fresh.hash == plugin.hash && fresh.entry == plugin.entry
            && fresh.settingsValues == plugin.settingsValues && fresh.secretRevision == plugin.secretRevision
    }
    private func validate() throws {
        try Task.checkCancellation()
        guard scope == currentScope(), manager.scope == scope, manager.ready else { throw CancellationError() }
    }
}

extension AppModel {
    func pluginStreams(media: Media, videoID: String, episode: Episode?, startingPriority: Int) async throws -> HarborPluginStreamBatch {
        let options = HarborPluginStreamOptions.current()
        guard options.enabled else { return .init() }
        guard let scope = pluginExecutionScope else { throw CancellationError() }
        let current: @MainActor () -> PluginExecutionScope = { [weak self] in self?.pluginExecutionScope ?? .init(owner: "locked", activation: scope.activation) }
        let manager = try await plugins.open(scope: scope, currentScope: current)
        guard scope == pluginExecutionScope, let runtime = plugins.runtime else { throw CancellationError() }
        let result = try await HarborPluginStreamSource(manager: manager, runtime: runtime, scope: scope, currentScope: current)
            .streams(media: media, videoID: videoID, episode: episode, startingPriority: startingPriority, options: options,
                tmdbKey: MetadataPreferences.shared.configuration().tmdbKey)
        guard scope == pluginExecutionScope else { throw CancellationError() }
        guard options == HarborPluginStreamOptions.current() else { return .init() }
        return result
    }
}
