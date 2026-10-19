import Foundation

actor AnimeMetadataGate {
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func run<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async throws -> Value {
        if active < 4 { active += 1 }
        else { await withCheckedContinuation { waiting.append($0) } }
        defer {
            if waiting.isEmpty { active -= 1 }
            else { waiting.removeFirst().resume() }
        }
        try Task.checkCancellation()
        return try await operation()
    }
}

actor AnimeFranchiseService {
    static let shared = AnimeFranchiseService()
    private struct Cached { let value: JSONValue; let expires: Date; let cost: Int }
    private struct SavedGraph { let value: AnimeFranchise; let expires: Date }
    private let transport: any AnimeFranchiseTransport
    private let anilistSpacing: TimeInterval
    private let gate = AnimeMetadataGate()
    private var anilistNext = Date.distantPast
    private var cache: [AnimeFranchiseRequest: Cached] = [:]
    private var cacheCost = 0
    private static let cacheBudget = 16 * 1_024 * 1_024
    private var pending: [AnimeFranchiseRequest: Task<JSONValue, Error>] = [:]
    private var graphs: [Int: SavedGraph] = [:]
    private var graphPending: [Int: Task<AnimeFranchise, Error>] = [:]
    private var roots: [Int: (id: Int, expires: Date)] = [:]

    init(transport: any AnimeFranchiseTransport = AnimeFranchiseHTTPTransport(), anilistSpacing: TimeInterval = 1) {
        self.transport = transport; self.anilistSpacing = max(0, min(2, anilistSpacing))
    }

    func franchise(for id: String, now: Date = Date()) async throws -> AnimeFranchise? {
        guard let identity = AnimePublicIdentity(id), let kitsu = try await kitsuID(identity) else { return nil }
        if let saved = graphs[kitsu], saved.expires > now { return saved.value }
        if let task = graphPending[kitsu] { return try await task.value }
        let task = Task { try await self.build(kitsu, now: now) }
        graphPending[kitsu] = task
        defer { graphPending[kitsu] = nil }
        let value = try await task.value
        if value.complete {
            if graphs.count >= 64, let oldest = graphs.min(by: { $0.value.expires < $1.value.expires })?.key { graphs[oldest] = nil }
            graphs[kitsu] = SavedGraph(value: value, expires: now.addingTimeInterval(3_600))
        }
        return value
    }

    func response(_ request: AnimeFranchiseRequest) async throws -> JSONValue {
        if case .anilist(let id) = request {
            guard id > 0, id <= Int(Int32.max) else { throw HarborError(code: "anime-id") }
        } else { _ = try request.url }
        if let saved = cache[request], saved.expires > Date() { return saved.value }
        if let task = pending[request] { return try await task.value }
        let transport = transport
        let gate = gate
        let delay: TimeInterval
        if case .anilist = request {
            let scheduled = max(Date(), anilistNext)
            anilistNext = scheduled.addingTimeInterval(anilistSpacing)
            delay = max(0, scheduled.timeIntervalSinceNow)
        } else { delay = 0 }
        let task = Task {
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            let value = try await gate.run { try await transport.get(request) }
            try Self.validate(value, for: request)
            return value
        }
        pending[request] = task
        defer { pending[request] = nil }
        let value = try await task.value
        remember(value, for: request)
        // Included Kitsu destinations are complete public anime resources. Reuse
        // them rather than requesting the same detail again in the next wave.
        if case .related = request {
            for entry in value["included"].array where entry["type"].string == "anime" {
                if let id = AnimeFranchiseEntry.positiveID(entry["id"]), case .object = entry["attributes"] {
                    remember(.object(["data": entry]), for: .kitsu(id))
                }
            }
        }
        return value
    }

    private func remember(_ value: JSONValue, for request: AnimeFranchiseRequest) {
        let cost = Self.memoryCost(value)
        if let previous = cache.removeValue(forKey: request) { cacheCost -= previous.cost }
        guard cost <= Self.cacheBudget else { return }
        while cache.count >= 256 || cacheCost + cost > Self.cacheBudget {
            guard let oldest = cache.min(by: { $0.value.expires < $1.value.expires })?.key, let removed = cache.removeValue(forKey: oldest) else { break }
            cacheCost -= removed.cost
        }
        let ttl: TimeInterval
        switch request { case .relations: ttl = 30 * 86_400; case .mapping: ttl = 1_800; default: ttl = 3_600 }
        cache[request] = Cached(value: value, expires: Date().addingTimeInterval(ttl), cost: cost); cacheCost += cost
    }

    private static func memoryCost(_ value: JSONValue) -> Int {
        switch value {
        case .string(let text): return min(cacheBudget + 1, text.utf8.count + 32)
        case .array(let values):
            var cost = 32
            for item in values { cost += 24 + memoryCost(item); if cost > cacheBudget { return cacheBudget + 1 } }
            return cost
        case .object(let values):
            var cost = 64
            for (key, item) in values { cost += key.utf8.count + 64 + memoryCost(item); if cost > cacheBudget { return cacheBudget + 1 } }
            return cost
        default: return 16
        }
    }

    private static func validate(_ value: JSONValue, for request: AnimeFranchiseRequest) throws {
        switch request {
        case .kitsu(let id):
            guard AnimeFranchiseEntry.positiveID(value["data"]["id"]) == id, value["data"]["type"].string == "anime", case .object = value["data"]["attributes"] else { throw HarborError(code: "anime-response") }
        case .related:
            guard case .array = value["data"] else { throw HarborError(code: "anime-response") }
        case .anilist(let id):
            guard value["Media"]["id"].integer == id, case .array = value["Media"]["relations"]["edges"] else { throw HarborError(code: "anime-response") }
        case .relations(let source, let id):
            guard case .object = value else { throw HarborError(code: "anime-response") }
            let key = source == "myanimelist" ? "mal" : source
            if let reported = value[key].integer, reported != id { throw HarborError(code: "anime-response") }
        case .mapping(let id):
            guard let identity = AnimePublicIdentity(id), value["mappings"][identity.mappingKey].textValue == identity.number else { throw HarborError(code: "anime-response") }
        }
    }

    private func kitsuID(_ identity: AnimePublicIdentity) async throws -> Int? {
        if identity.provider == "kitsu" { return Int(identity.number) }
        if let source = identity.relationsSource, let id = Int(identity.number),
           let arm = try? await response(.relations(source: source, id: id)), let kitsu = arm["kitsu"].integer, kitsu > 0 { return kitsu }
        let raw = identity.provider == "imdb" ? identity.number : identity.provider + ":" + identity.number
        guard let mapping = try? await response(.mapping(raw)) else { return nil }
        if let id = mapping["mappings"]["kitsu_id"].integer, id > 0 { return id }
        if let anidb = mapping["mappings"]["anidb_id"].integer, anidb > 0,
           let arm = try? await response(.relations(source: "anidb", id: anidb)), let kitsu = arm["kitsu"].integer, kitsu > 0 { return kitsu }
        return nil
    }

    private func anilistID(_ kitsu: Int) async -> (id: Int?, complete: Bool) {
        var complete = true
        do {
            let arm = try await response(.relations(source: "kitsu", id: kitsu))
            if let id = arm["anilist"].integer, id > 0 { return (id, true) }
        } catch { complete = (error as? HarborError)?.code == "http-404" }
        do {
            let mapping = try await response(.mapping("kitsu:\(kitsu)"))
            if let id = mapping["mappings"]["anilist_id"].integer, id > 0 { return (id, true) }
            return (nil, complete)
        } catch { return (nil, complete && (error as? HarborError)?.code == "http-404") }
    }

    private func related(_ id: Int, current: Int, now: Date) async throws -> [(role: String, entry: AnimeFranchiseEntry)] {
        let value = try await response(.related(id))
        var destinations: [Int: AnimeFranchiseEntry] = [:]
        for resource in value["included"].array {
            if let entry = AnimeFranchiseEntry.kitsu(resource, currentID: current, now: now), let id = AnimeFranchiseEntry.positiveID(resource["id"]) { destinations[id] = entry }
        }
        return value["data"].array.compactMap { relation in
            guard let id = AnimeFranchiseEntry.positiveID(relation["relationships"]["destination"]["data"]["id"]), let entry = destinations[id] else { return nil }
            return (relation["attributes"]["role"].string?.lowercased() ?? "related", entry)
        }
    }

    private func root(of start: Int, now: Date) async -> (id: Int, complete: Bool) {
        if let saved = roots[start], saved.expires > now { return (saved.id, true) }
        var current = start, chain = [start], visited: Set<Int> = [start], complete = true
        for _ in 0..<8 {
            guard let relations = try? await related(current, current: start, now: now) else { complete = false; break }
            let ancestors = relations.filter { $0.role == "prequel" && !visited.contains(Int($0.entry.id.dropFirst(6)) ?? 0) }
                .sorted {
                    let first = $0.entry, second = $1.entry
                    if (first.media.type != "movie") != (second.media.type != "movie") { return first.media.type != "movie" }
                    let a = first.year == 0 ? 9999 : first.year, b = second.year == 0 ? 9999 : second.year
                    return a == b ? (Int(first.id.dropFirst(6)) ?? 0) < (Int(second.id.dropFirst(6)) ?? 0) : a < b
                }
            guard let next = ancestors.first.flatMap({ Int($0.entry.id.dropFirst(6)) }) else { break }
            current = next; visited.insert(next); chain.append(next)
        }
        if complete {
            if roots.count + chain.count > 600 { roots = roots.filter { $0.value.expires > now }; if roots.count + chain.count > 600 { roots.removeAll() } }
            for id in chain { roots[id] = (current, now.addingTimeInterval(30 * 86_400)) }
        }
        return (current, complete)
    }

    private func build(_ current: Int, now: Date) async throws -> AnimeFranchise {
        let resource = try await response(.kitsu(current))
        guard let first = AnimeFranchiseEntry.kitsu(resource["data"], currentID: current, now: now) else { throw HarborError(code: "anime-response") }
        async let rootIdentity = root(of: current, now: now)
        async let rootAnilist = anilistFranchise(current)
        var entries = [first], visited: Set<Int> = [current], frontier = [current], complete = true
        for _ in 0..<3 {
            if frontier.isEmpty { break }
            let batches = await Self.limited(frontier) { id in try? await self.related(id, current: current, now: now) }
            var next: [Int] = []
            for batch in batches {
                guard let batch else { complete = false; continue }
                for relation in batch where ["sequel", "prequel", "parent_story"].contains(relation.role) {
                    guard let id = Int(relation.entry.id.dropFirst(6)), visited.insert(id).inserted else { continue }
                    entries.append(relation.entry); next.append(id)
                }
            }
            frontier = next
        }
        let siblings = entries.filter { !$0.current }.sorted { ($0.year == 0 ? 9999 : $0.year) < ($1.year == 0 ? 9999 : $1.year) }.prefix(2)
        let siblingLists = await Self.limited(siblings.compactMap { Int($0.id.dropFirst(6)) }) { id in await self.anilistFranchise(id) }
        let (rootValue, extra) = await (rootIdentity, rootAnilist)
        complete = complete && rootValue.complete && extra.complete && siblingLists.allSatisfy(\.complete)
        var uniqueAniList: [String: AnimeFranchiseEntry] = [:], aniListOrder: [String] = []
        for entry in ([extra.entries] + siblingLists.map(\.entries)).flatMap({ $0 }) {
            if uniqueAniList[entry.id] == nil { aniListOrder.append(entry.id) }
            uniqueAniList[entry.id] = entry
        }
        let merged = AnimeFranchise.merged(entries + aniListOrder.compactMap { uniqueAniList[$0] })
        let resolved = await Self.limited(merged) { entry -> AnimeFranchiseEntry in
            guard entry.id.hasPrefix("anilist:"), let identity = AnimePublicIdentity(entry.id), let id = try? await self.kitsuID(identity) else { return entry }
            var value = entry; value.media.id = "kitsu:\(id)"; return value
        }
        var ids = Set<String>()
        let result = resolved.filter { ids.insert($0.id).inserted }.enumerated().sorted {
            let first = $0.element.startDate ?? "9999", second = $1.element.startDate ?? "9999"
            return first == second ? $0.offset < $1.offset : first < second
        }.map(\.element)
        return AnimeFranchise(currentID: "kitsu:\(current)", rootID: "kitsu:\(rootValue.id)", entries: result, complete: complete)
    }

    private func anilistFranchise(_ kitsu: Int) async -> (entries: [AnimeFranchiseEntry], complete: Bool) {
        let identity = await anilistID(kitsu)
        guard let root = identity.id else { return ([], identity.complete) }
        var entries: [Int: AnimeFranchiseEntry] = [:], order: [Int] = [], visited: Set<Int> = [root], frontier = [root], complete = true
        for _ in 0..<6 {
            if frontier.isEmpty || entries.count >= 40 { break }
            let batches = await Self.limited(frontier) { id in try? await self.response(.anilist(id)) }
            var next: [Int] = []
            for batch in batches {
                guard let batch else { complete = false; continue }
                for edge in batch["Media"]["relations"]["edges"].array {
                    guard let role = edge["relationType"].string, ["SEQUEL", "PREQUEL", "PARENT", "SIDE_STORY"].contains(role),
                          let id = edge["node"]["id"].integer, visited.insert(id).inserted else { continue }
                    if let entry = AnimeFranchiseEntry.anilist(edge["node"]) { order.append(id); entries[id] = entry }
                    next.append(id)
                }
            }
            frontier = next
        }
        return (order.compactMap { entries[$0] }, complete)
    }

    private static func limited<Input: Sendable, Output: Sendable>(_ inputs: [Input], operation: @escaping @Sendable (Input) async -> Output) async -> [Output] {
        await withTaskGroup(of: (Int, Output).self) { group in
            var iterator = inputs.enumerated().makeIterator(), results: [Int: Output] = [:]
            for _ in 0..<min(4, inputs.count) { if let (index, value) = iterator.next() { group.addTask { (index, await operation(value)) } } }
            for await (index, result) in group {
                results.updateValue(result, forKey: index)
                if let (next, value) = iterator.next() { group.addTask { (next, await operation(value)) } }
            }
            return inputs.indices.compactMap { results[$0] }
        }
    }
}
