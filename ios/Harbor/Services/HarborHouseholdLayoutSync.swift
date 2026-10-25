import Foundation
import Observation

/// A pull applies every known profile's registered sections. Linked profiles
/// share persisted values, but dirty keys and server revisions remain per profile.
@MainActor @Observable final class HarborHouseholdLayoutSync {
    struct Active {
        let navigation: HarborNavigationSync
        let services: HarborStreamingSync
        let home: HarborPageSync
        let anime: HarborPageSync
    }
    private struct Target {
        let id: String
        let owner: String
        let profile: JSONValue
        let linked: Bool
    }
    let account: String
    private var generation = 0
    private var busy = false
    private var pending: Set<String> = []
    var hasPendingChanges: Bool { !pending.isEmpty }
    init(account: String) { self.account = account }
    func invalidate() { generation += 1; busy = false }

    /// Read only the already activated account's settings. This never hydrates
    /// sync journals, arms callbacks, or needs a network request.
    static func bindCached(account: String, context: AppProfileContext, active: Active) throws {
        guard context.ready, context.profiles.scope == .harbor(account: account),
              let binding = context.binding, let selected = context.profiles.active, !selected.desktop.isKid,
              active.navigation.preferences.scope?.owner == binding.settingsOwner,
              active.services.preferences.owner == binding.settingsOwner,
              active.home.preferences.owner == binding.settingsOwner, active.anime.preferences.owner == binding.settingsOwner else {
            throw HarborError(code: "account-changed")
        }
        let expected = NavigationScope.harbor(owner: binding.settingsOwner, account: account,
            profile: selected.syncID, linked: selected.desktop.settingsLinked)
        active.navigation.preferences.bind(expected); active.services.preferences.bind(expected)
        active.home.preferences.bind(expected); active.anime.preferences.bind(expected)
        let shared = NavigationScope.harbor(owner: binding.sharedSettingsOwner, account: account, profile: selected.syncID, linked: true)
        try active.navigation.preferences.inheritSharedIfAbsent(shared); try active.services.preferences.inheritSharedIfAbsent(shared)
        try active.home.preferences.inheritSharedIfAbsent(shared); try active.anime.preferences.inheritSharedIfAbsent(shared)
    }

    func synchronize(state: JSONValue, context: AppProfileContext, active: Active,
                     requestSync: @escaping @MainActor () -> Void,
                     send: @escaping @MainActor (JSONValue) async throws -> JSONValue,
                     check: @escaping @MainActor () throws -> Void) async throws {
        try Task.checkCancellation(); try check()
        guard !busy, let binding = context.binding, let selected = context.profiles.active,
              context.profiles.scope == .harbor(account: account) else { throw HarborError(code: "account-changed") }
        let store = context.profiles, version = store.mutationVersion, pass = generation
        let selectedID = selected.syncID
        let targets = store.profiles.filter { !$0.desktop.isKid }.map { row in
            let personal = HouseholdProfileRouting(profile: row, profiles: store.profiles, scope: store.scope, cwPerProfile: false).personal
            return Target(id: row.syncID, owner: row.desktop.settingsLinked ? binding.sharedSettingsOwner : personal,
                profile: row.desktop.raw, linked: row.desktop.settingsLinked)
        }
        guard let activeTarget = targets.first(where: { $0.id == selectedID }) else { throw HarborError(code: "profile-sync-target") }
        let sharedScope = NavigationScope.harbor(owner: binding.sharedSettingsOwner, account: account, profile: selectedID, linked: true)
        let expected = NavigationScope.harbor(owner: activeTarget.owner, account: account, profile: selectedID, linked: activeTarget.linked)
        active.navigation.preferences.bind(expected); active.services.preferences.bind(expected)
        active.home.preferences.bind(expected); active.anime.preferences.bind(expected)
        let checkPass: @MainActor () throws -> Void = {
            try Task.checkCancellation(); try check()
            guard self.generation == pass, context.profiles === store, store.mutationVersion == version,
                  context.profiles.active?.syncID == selectedID, context.binding == binding else { throw HarborError(code: "account-changed") }
        }
        let guardedSend: @MainActor (JSONValue) async throws -> JSONValue = { body in
            try checkPass(); let response = try await send(body); try checkPass(); return response
        }
        _ = try HarborLayoutDocument.revision(state["rev"])
        guard case .array(let documents) = state["docs"], documents.count <= 10_000 else { throw HarborError(code: "layout-sync-response") }
        var indexed: [String: [JSONValue]] = [:]
        for document in documents { if let key = document["key"].string { indexed[key, default: []].append(document) } }
        let sections = ["services", "nav", "home", "anime"]
        let keys = Set(targets.flatMap { target in sections.map { target.id + ":" + $0 } })
        pending.formIntersection(keys)
        busy = true
        defer { if generation == pass { busy = false } }
        var steps: [HarborLayoutSyncBatch.Step] = []
        for section in sections {
            let byKey = Dictionary(uniqueKeysWithValues: targets.map { ($0.id + ":" + section, $0) })
            var seen: Set<String> = []
            let ordered = documents.compactMap { document -> Target? in
                guard let key = document["key"].string, let target = byKey[key], seen.insert(target.id).inserted else { return nil }
                return target
            } + targets.filter { !seen.contains($0.id) }
            for target in ordered {
                let key = target.id + ":" + section
                // Index once. Each actor sees its own complete (possibly absent
                // or duplicated) document without rescanning thousands of keys.
                let input = JSONValue.object(["rev": state["rev"], "docs": .array(indexed[key] ?? [])])
                steps.append(.init {
                    try checkPass()
                    let background = target.id != selectedID
                    let shared = background && target.linked && activeTarget.linked && target.owner == activeTarget.owner
                    switch section {
                    case "nav":
                        let engine: HarborNavigationSync
                        if background {
                            let preferences = ScopedNavigationPreferences()
                            preferences.bind(.harbor(owner: target.owner, account: self.account, profile: target.id, linked: target.linked))
                            let interface = InterfacePreferences.shared
                            engine = HarborNavigationSync(owner: target.owner, preferences: preferences,
                                defaultOrder: interface.defaultNavigationOrder, knownIDs: Set(HarborSection.allCases.map(\.rawValue)).subtracting(["search"]))
                        } else { engine = active.navigation }
                        if indexed[key] == nil { try engine.preferences.inheritSharedIfAbsent(sharedScope) }
                        engine.requestSync = requestSync
                        var completed = false
                        defer { if self.generation == pass { self.mark(key, pending: engine.hasPendingChanges, completed: completed) } }
                        do { try await engine.synchronize(state: input, account: self.account, profile: target.profile, send: guardedSend) }
                        catch {
                            try checkPass(); if shared { try active.navigation.refreshSharedValue() }
                            try active.navigation.preferences.inheritSharedIfAbsent(sharedScope); throw error
                        }
                        try checkPass(); if shared { try active.navigation.refreshSharedValue() }
                        try active.navigation.preferences.inheritSharedIfAbsent(sharedScope); completed = true
                    case "services":
                        let engine: HarborStreamingSync
                        if background {
                            let preferences = StreamingPreferences(owner: target.owner)
                            preferences.bind(.harbor(owner: target.owner, account: self.account, profile: target.id, linked: target.linked))
                            engine = HarborStreamingSync(owner: target.owner, preferences: preferences)
                        } else { engine = active.services }
                        if indexed[key] == nil { try engine.preferences.inheritSharedIfAbsent(sharedScope) }
                        engine.requestSync = requestSync
                        var completed = false
                        defer { if self.generation == pass { self.mark(key, pending: engine.hasPendingChanges, completed: completed) } }
                        do { try await engine.synchronize(state: input, account: self.account, profile: target.profile, send: guardedSend) }
                        catch {
                            try checkPass(); if shared { try active.services.refreshSharedValue() }
                            try active.services.preferences.inheritSharedIfAbsent(sharedScope); throw error
                        }
                        try checkPass(); if shared { try active.services.refreshSharedValue() }
                        try active.services.preferences.inheritSharedIfAbsent(sharedScope); completed = true
                    default:
                        let visible = section == "home" ? active.home : active.anime
                        let engine: HarborPageSync
                        if background {
                            let preferences = PageCustomization(owner: target.owner, page: section,
                                inheritedOwner: target.linked ? nil : binding.sharedSettingsOwner)
                            preferences.bind(.harbor(owner: target.owner, account: self.account, profile: target.id, linked: target.linked))
                            engine = HarborPageSync(preferences: preferences)
                        } else { engine = visible }
                        if indexed[key] == nil { try engine.preferences.inheritSharedIfAbsent(sharedScope) }
                        engine.requestSync = requestSync
                        var completed = false
                        defer { if self.generation == pass { self.mark(key, pending: engine.hasPendingChanges, completed: completed) } }
                        do { try await engine.synchronize(state: input, account: self.account, profile: target.profile, send: guardedSend) }
                        catch {
                            try checkPass(); if shared { try visible.refreshSharedValue() }
                            try visible.preferences.inheritSharedIfAbsent(sharedScope); throw error
                        }
                        try checkPass(); if shared { try visible.refreshSharedValue() }
                        try visible.preferences.inheritSharedIfAbsent(sharedScope); completed = true
                    }
                })
            }
        }
        try await HarborLayoutSyncBatch.run(steps, check: checkPass)
    }
    private func mark(_ key: String, pending: Bool, completed: Bool) {
        if pending { self.pending.insert(key) } else if completed { self.pending.remove(key) }
    }
}
