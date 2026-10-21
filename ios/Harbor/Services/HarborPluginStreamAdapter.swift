import CryptoKit
import Foundation
import WebKit

struct HarborPluginStreamContext: Sendable {
    let request: JSONValue
    let addonID: String
    let addonName: String
    let addonURL: String
    let pluginName: String
    var json: JSONValue {
        .object(["req": request, "addonId": .string(addonID), "addonName": .string(addonName),
            "addonUrl": .string(addonURL), "pluginName": .string(pluginName), "trustHeaders": .bool(false)])
    }
}

private struct PluginStreamAdapterAsset: Decodable {
    struct Program: Decodable { let source: String; let sha256: String }
    struct Dependency: Decodable {
        let name: String
        let version: String
        let programSha256: String
        let licenseSha256: String
        let integrity: String
    }
    let schema: Int
    let reference: String
    let inputs: [String: String]
    let thirdParty: Dependency
    let program: Program

    static func readProgram() throws -> String {
        guard let url = Bundle.main.url(forResource: "PluginStreamAdapterAssets", withExtension: "json"),
              let license = Bundle.main.url(forResource: "TLDTS-LICENSE", withExtension: "txt") else { throw HarborPluginRuntimeError("plugin-adapter-assets") }
        let data = try Data(contentsOf: url), licenseData = try Data(contentsOf: license)
        guard data.count <= 2 * 1024 * 1024, licenseData.count <= 64 * 1024 else { throw HarborPluginRuntimeError("plugin-adapter-assets") }
        let asset = try JSONDecoder().decode(Self.self, from: data)
        func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        guard asset.schema == 1, asset.reference == "0834340cec5531650bfe78cd628628702e636987",
              asset.thirdParty.name == "tldts", asset.thirdParty.version == "7.4.12",
              asset.thirdParty.programSha256 == "202d92c731736e54220874e8dd0bdc469a01e773836b4a87169cd05a2c8dd558",
              asset.thirdParty.licenseSha256 == "c64182d48160db948b6aa97a984f1a32974ce4d2053900361264cd33853796cb",
              hash(licenseData) == asset.thirdParty.licenseSha256, hash(Data(asset.program.source.utf8)) == asset.program.sha256,
              asset.inputs == [
                "src/lib/streams/plugins/adapter.ts": "257ddc205520ae9c1dae089e8764bfe5733a928c7512331b36433dd9de547a4f",
                "src/lib/manga/plugins/host-http.ts": "9f88ca743ef87f50d820fb4ca2573d1837d5418279f1284839bf34410245f589",
                "src/lib/same-site-host.ts": "3fc786aa3035c5f0f3ac5cfd4413968acd0376dc2ef5ecde104656aae11e6022",
                "src/lib/torrent/magnet.ts": "278bde3277b52408c5af11f812a6673801d020e2af32f2e8f2ebd73181d78789",
                "src/lib/privacy/blocklist.ts": "dad2a89a8856370cdb548b1062a997bb80664b20665b0465ddc2e9a8312422c4",
                "package.json": "ff5aed57316298a94db2749f543656646c23807c6271de1fbdbcab5af76ce9ce"
              ] else { throw HarborPluginRuntimeError("plugin-adapter-assets") }
        return asset.program.source
    }
}

/// Only the pinned pure Desktop adapter runs here. Installed plugin code and native bridges are absent.
@MainActor final class HarborPluginStreamAdapter: NSObject, WKNavigationDelegate {
    static let shared = HarborPluginStreamAdapter()
    private var web: WKWebView?
    private var loading: Task<Void, Error>?
    private var navigation: CheckedContinuation<Void, Error>?
    private var ready = false
    private var generation = UUID()

    func map(_ raw: JSONValue, context: HarborPluginStreamContext, blockTrackers: Bool = true) async throws -> [JSONValue] {
        let json = try await Task.detached(priority: .utility) {
            let data = try JSONEncoder().encode(raw)
            guard data.count <= 64 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw HarborPluginRuntimeError("plugin-adapter-message") }
            return text
        }.value
        return try await mapJSON(json, context: context, blockTrackers: blockTrackers)
    }
    func mapJSON(_ raw: String, context: HarborPluginStreamContext, blockTrackers: Bool = true) async throws -> [JSONValue] {
        try Task.checkCancellation()
        let input = JSONValue.object(["rawJSON": .string(raw), "context": context.json, "blockTrackers": .bool(blockTrackers)])
        let encoded = try await Task.detached(priority: .utility) {
            let data = try JSONEncoder().encode(input)
            guard data.count <= 64 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw HarborPluginRuntimeError("plugin-adapter-message") }
            return text
        }.value
        try Task.checkCancellation(); try await prepare(); try Task.checkCancellation()
        guard let web, ready else { throw HarborPluginRuntimeError("plugin-adapter-unavailable") }
        let epoch = generation
        let output: String
        do {
            output = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                web.callAsyncJavaScript("return globalThis.harborAdaptPluginStreams(input)", arguments: ["input": encoded], in: nil, in: .page) { result in
                    switch result {
                    case .success(let value):
                        guard let text = value as? String else { continuation.resume(throwing: HarborPluginRuntimeError("plugin-adapter-result")); return }
                        continuation.resume(returning: text)
                    case .failure: continuation.resume(throwing: HarborPluginRuntimeError("plugin-adapter-result"))
                    }
                }
            }
        } catch {
            try Task.checkCancellation()
            throw HarborPluginRuntimeError("plugin-adapter-result")
        }
        try Task.checkCancellation()
        guard ready, generation == epoch, self.web === web else { throw HarborPluginRuntimeError("plugin-adapter-unavailable") }
        let result = try await Task.detached(priority: .utility) {
            guard let data = output.data(using: .utf8), data.count <= 64 * 1024 * 1024 else { throw HarborPluginRuntimeError("plugin-adapter-result") }
            return try JSONDecoder().decode([JSONValue].self, from: data)
        }.value
        try Task.checkCancellation(); return result
    }

    func clear() { retire(HarborPluginRuntimeError("plugin-adapter-unavailable")) }

    private func prepare() async throws {
        if ready, web != nil { return }
        let epoch = generation
        let task: Task<Void, Error>
        if let loading { task = loading }
        else {
            task = Task {
                let program = try await Task.detached(priority: .utility) { try PluginStreamAdapterAsset.readProgram() }.value
                try Task.checkCancellation()
                guard self.generation == epoch else { throw HarborPluginRuntimeError("plugin-adapter-unavailable") }
                let timer = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                    if let self, self.generation == epoch, !self.ready { self.retire(HarborPluginRuntimeError("plugin-adapter-timeout")) }
                }
                defer { timer.cancel() }
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.navigation = continuation
                    let configuration = WKWebViewConfiguration()
                    configuration.websiteDataStore = .nonPersistent()
                    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
                    configuration.userContentController.addUserScript(WKUserScript(source: program, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
                    let view = WKWebView(frame: .zero, configuration: configuration)
                    view.navigationDelegate = self; self.web = view
                    view.loadHTMLString("<!doctype html><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; connect-src 'none'; script-src 'none'; img-src 'none'\"><title>Harbor stream adapter</title>", baseURL: URL(string: "https://harbor-adapter.invalid/"))
                }
                try Task.checkCancellation()
                guard self.generation == epoch, self.web != nil else { throw HarborPluginRuntimeError("plugin-adapter-unavailable") }
                self.ready = true
            }
            loading = task
        }
        defer { if generation == epoch { loading = nil } }
        do { try await task.value }
        catch { if generation == epoch { retire(error) }; throw error }
    }
    private func retire(_ error: Error) {
        generation = UUID(); ready = false
        loading?.cancel(); loading = nil
        let pending = navigation; navigation = nil; pending?.resume(throwing: error)
        web?.stopLoading(); web?.navigationDelegate = nil; web = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard web === webView else { return }
        let pending = self.navigation; self.navigation = nil; pending?.resume()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if web === webView { retire(HarborPluginRuntimeError("plugin-adapter-load")) } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if web === webView { retire(HarborPluginRuntimeError("plugin-adapter-load")) } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if web === webView { retire(HarborPluginRuntimeError("plugin-adapter-process")) } }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        action.navigationType == .other && (action.request.url?.scheme == "about" || action.request.url?.host == "harbor-adapter.invalid") ? .allow : .cancel
    }
}
