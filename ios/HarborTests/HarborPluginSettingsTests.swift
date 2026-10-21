import XCTest
@testable import Harbor

private actor SettingsPluginNetwork: HarborNativeNetworkCalling {
    private var responses: [String: HarborNetworkResponse] = [:]
    private var requests: [HarborNetworkRequest] = []
    private var holding = false
    private var held: CheckedContinuation<Void, Never>?
    func set(_ url: String, data: Data) { responses[url] = .init(status: 200, ok: true, headers: [:], bodyBase64: data.base64EncodedString(), url: url) }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        if holding && request.url == "https://rpc.example.org/owned" { await withCheckedContinuation { held = $0 } }
        guard let result = responses[request.url] else { throw HarborError(code: "owned-unavailable") }
        return result
    }
    func holdRPC() { holding = true }
    func release() { holding = false; held?.resume(); held = nil }
    func captured() -> [HarborNetworkRequest] { requests }
    func waitUntilHeld() async throws {
        for _ in 0..<100 { if held != nil { return }; try await Task.sleep(for: .milliseconds(20)) }
        throw HarborPluginRepositoryError("owned-timeout")
    }
}

@MainActor final class HarborPluginSettingsTests: XCTestCase {
    func testOriginalDesktopNormalizerRunsInJavaScriptCoreWithAllReferenceFieldCoercions() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "plugin-settings-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(fixture["cases"].array.count, 14)
        for row in fixture["cases"].array {
            if let code = row["error"].string {
                do { _ = try await HarborPluginSettings.fields(row["input"]); XCTFail("Invalid field coercion accepted") }
                catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, code) }
            } else {
                let fields = try await HarborPluginSettings.fields(row["input"])
                XCTAssertEqual(try JSONValue.encoded(fields), row["expected"])
            }
        }
    }

    private let source = #"var plugin={id:'owned.settings',name:'Owned settings',streams:async function(){return [];},settings:async function(){var denied=false;try{await harbor.http('https://denied.example.org/owned');}catch(error){denied=String(error).includes('network not available here');}if(!denied)throw new Error('HTTP was not denied');var rpc=await harbor.grpc('https://rpc.example.org/owned',new Uint8Array([1]));return {fields:[{type:'header',label:'Account'},{type:'text',key:'token',label:'Token',isPassword:true},{type:'select',key:'quality',options:[{value:1080,label:'FHD'},{value:720,label:'HD'}],defaultValue:1080},{type:'checkbox',key:'enabled',defaultValue:true},{type:'info',label:'RPC '+rpc.body[0]}]};}};"#

    private func prepared() async throws -> (HarborStreamPluginManager, SettingsPluginNetwork, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("owned-plugin-settings-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("catalog.json"), network = SettingsPluginNetwork()
        await network.set("https://example.org/manifest.json", data: Data(#"{"plugins":[{"id":"owned.settings","name":"Owned settings","entry":"source.js","settings":true}]}"#.utf8))
        await network.set("https://example.org/source.js", data: Data(source.utf8))
        await network.set("https://rpc.example.org/owned", data: Data([0,0,0,0,1,7]))
        let scope = PluginExecutionScope(owner: "owned-plugin-settings", activation: UUID())
        let store = try HarborPluginCatalogStore(namespace: scope.owner, file: file)
        let manager = HarborStreamPluginManager(namespace: scope.owner, scope: scope, currentScope: { scope }, store: store, client: .init(network: network))
        try await manager.load(); try await manager.addRepository("https://example.org/manifest.json")
        try await manager.install(repository: "https://example.org/manifest.json", entryID: "owned.settings")
        return (manager, network, file)
    }

    func testActualSettingsWorkerKeepsDeclaredFieldsHTTPDenialAndTheReferenceGRPCPath() async throws {
        let (manager, network, _) = try await prepared(); defer { manager.dispose() }
        let id = try XCTUnwrap(manager.document.plugins.first?.id)
        let fields = try await manager.settingsFields(id)
        XCTAssertEqual(fields.map(\.type), ["header","text","select","toggle","info"])
        XCTAssertEqual(fields[1].isPassword, true); XCTAssertEqual(fields[2].options?.map(\.value), ["1080","720"])
        XCTAssertEqual(fields[2].defaultValue, .string("1080")); XCTAssertEqual(fields[3].defaultValue, .bool(true))
        XCTAssertEqual(fields[4].label, "RPC 7")
        let requests = await network.captured()
        XCTAssertFalse(requests.contains(where: { $0.url == "https://denied.example.org/owned" }))
        let rpc = try XCTUnwrap(requests.first(where: { $0.url == "https://rpc.example.org/owned" }))
        XCTAssertEqual(rpc.method, "POST"); XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(rpc.bodyBase64)), Data([0,0,0,0,1,1]))
        XCTAssertNil(rpc.allowCookie); XCTAssertNil(rpc.allowReferer); XCTAssertFalse(rpc.openHeaders)
    }

    func testDisposingTheManagerCancelsItsRealSettingsWorkerWithoutChangingInstalledState() async throws {
        let (manager, network, file) = try await prepared(); defer { manager.dispose() }
        let id = try XCTUnwrap(manager.document.plugins.first?.id), before = try Data(contentsOf: file)
        await network.holdRPC()
        let task = Task { try await manager.settingsFields(id) }
        try await network.waitUntilHeld()
        manager.dispose(); await network.release()
        do { _ = try await task.value; XCTFail("Disposed settings published") }
        catch { XCTAssertTrue(error is CancellationError || (error as? HarborPluginRepositoryError)?.code == "plugin-scope") }
        XCTAssertFalse(manager.ready); XCTAssertTrue(manager.document.plugins.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }
}
