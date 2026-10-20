import Foundation

struct HarborFetchedPluginSource: Sendable {
    let code: String
    let etag: String?
}

/// Downloads the actual repository/source documents before installation or probing.
/// The catalog store remains the authority for committed state and revisions.
struct HarborPluginRepositoryClient: Sendable {
    var network: any HarborNativeNetworkCalling = HarborNativeNetwork()
    var blockedHosts: [String] = []

    func add(_ rawURL: String, existingURLs: Set<String>) async throws -> HarborStreamRepositoryRecord {
        let candidates = HarborPluginManifest.candidates(try HarborPluginManifest.normalizeURL(rawURL))
        guard !candidates.contains(where: existingURLs.contains) else { throw HarborPluginRepositoryError("already-added") }
        var lastError: Error = HarborPluginRepositoryError("no-answer")
        for (index, url) in candidates.enumerated() {
            try Task.checkCancellation()
            do {
                let manifest = try await fetchManifest(url)
                try Task.checkCancellation()
                if !manifest.entries.isEmpty || index == candidates.count - 1 {
                    return .init(url: url, manifest: manifest, checkedAt: Date().timeIntervalSince1970 * 1000)
                }
            } catch is CancellationError { throw CancellationError() }
            catch { lastError = error }
        }
        throw lastError
    }

    func fetchManifest(_ url: String) async throws -> HarborParsedStreamRepository {
        var manifest = try HarborPluginManifest.parse(await json(url), url: url)
        var seen = Set(manifest.entries.map(\.id))
        for listURL in manifest.lists ?? [] {
            try Task.checkCancellation()
            do {
                let list = try HarborPluginManifest.parse(await json(listURL), url: listURL)
                guard list.format == .androidExtension else { continue }
                manifest.entries += list.entries.filter { seen.insert($0.id).inserted }
            } catch is CancellationError { throw CancellationError() }
            catch { continue } // Desktop retains usable lists when another list fails.
        }
        return manifest
    }

    func fetchSource(_ entry: HarborStreamPluginEntry) async throws -> HarborFetchedPluginSource {
        guard entry.format != .androidExtension else { throw HarborPluginRepositoryError("android-extensions") }
        let response = try await fetch(entry.entry, failure: "fetch-failed")
        var code = String(decoding: try response.bytes(), as: UTF8.self)
        if code.hasPrefix("\u{feff}") { code.removeFirst() }
        guard code.utf16.count <= 2 * 1024 * 1024 else { throw HarborPluginRepositoryError("too-large") }
        return .init(code: code, etag: response.headers["etag"])
    }

    func fetchIcon(_ url: String?) async throws -> String? {
        guard let url else { return nil }
        do {
            var request = request(url)
            request.timeoutMs = 8_000; request.maxResponseBytes = 512 * 1024; request.strictLimit = true
            let response = try await network.perform(request)
            try Task.checkCancellation()
            guard response.ok else { return nil }
            let type = (response.headers["content-type"] ?? "").split(separator: ";", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard type.hasPrefix("image/") else { return nil }
            let data = try response.bytes()
            guard !data.isEmpty, data.count <= 512 * 1024 else { return nil }
            return "data:" + type + ";base64," + data.base64EncodedString()
        } catch is CancellationError { throw CancellationError() }
        catch { return nil }
    }

    private func json(_ url: String) async throws -> JSONValue {
        let response = try await fetch(url, failure: "no-answer")
        do { return try JSONDecoder().decode(JSONValue.self, from: response.bytes()) }
        catch { throw HarborPluginRepositoryError("not-a-repo") }
    }

    private func fetch(_ url: String, failure: String) async throws -> HarborNetworkResponse {
        do {
            try Task.checkCancellation()
            let response = try await network.perform(request(url))
            try Task.checkCancellation()
            guard response.ok else { throw HarborPluginRepositoryError(failure) }
            return response
        } catch is CancellationError { throw CancellationError() }
        catch { throw HarborPluginRepositoryError(failure) }
    }

    private func request(_ url: String) -> HarborNetworkRequest {
        var request = HarborNetworkRequest(url: url)
        request.blockedHosts = blockedHosts
        return request
    }
}
