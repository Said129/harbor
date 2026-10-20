import XCTest
@testable import Harbor

private actor OwnedPluginTransport: HarborPluginHostTransport {
    private var holdFirst: Bool
    private var held: CheckedContinuation<Void, Never>?
    private var started = false
    private var active = 0
    private var maximum = 0
    private var requests: [(HarborPluginBridgeKind, JSONValue)] = []
    init(holdFirst: Bool = false) { self.holdFirst = holdFirst }
    func perform(_ kind: HarborPluginBridgeKind, payload: JSONValue) async throws -> JSONValue {
        active += 1; maximum = max(maximum, active); requests.append((kind, payload)); started = true
        defer { active -= 1 }
        if holdFirst { holdFirst = false; await withCheckedContinuation { held = $0 } }
        else { try await Task.sleep(for: .milliseconds(20)) }
        if kind == .grpc {
            return .object(["status": .integer(200), "ok": .bool(true), "headers": .object([:]), "body": .string("BAUG"), "messages": .array([.string("BwgJ")])])
        }
        return .object(["status": .integer(200), "ok": .bool(true), "headers": .object([:]), "body": .string("{\"value\":\"host-owned\"}")])
    }
    func waitUntilStarted() async throws {
        for _ in 0..<200 { if started { return }; try await Task.sleep(for: .milliseconds(50)) }
        throw HarborPluginRuntimeError("owned-fixture-timeout")
    }
    func release() { held?.resume(); held = nil }
    func snapshot() -> (Int, Int, [JSONValue]) { (requests.count, maximum, requests.map { $0.1 }) }
}

@MainActor private final class OwnedPluginScope {
    var value = PluginExecutionScope(owner: "owned-runtime", activation: UUID())
}

@MainActor final class HarborPluginRuntimeTests: XCTestCase {
    private func runtime(_ source: String, id: String = "owned.runtime", format: HarborPluginCodeFormat = .raw,
        configuration: JSONValue = .object([:]), context: OwnedPluginScope? = nil, transport: OwnedPluginTransport = OwnedPluginTransport()) -> HarborPluginRuntime {
        let context = context ?? OwnedPluginScope()
        return HarborPluginRuntime(id: id, name: "Owned Runtime", source: source, format: format, configuration: configuration,
            scope: context.value, currentScope: { context.value }, transport: transport)
    }
    private let httpSource = #"var plugin = { id: "owned.http", name: "Owned HTTP", search: async function () { return await harbor.http("https://example.invalid/owned", { responseType: "json" }); } };"#

    func testPinnedHarborWorkerParsesActualHTMLAndExposesDeclaredMethods() async throws {
        let source = #"var plugin = { id: "owned.html", name: "Owned HTML", search: async function (query, page) { var document = await harbor.parseHtml('<style>.hidden{display:none}</style><a class="item" href="/owned">Owned title</a><a class="item hidden" href="/hidden">Hidden</a><script>throw new Error("not executable")</script>'); return { query: query, page: page, title: document.querySelector('a.item').text(), path: document.querySelector('a.item').getAttribute('href'), count: document.querySelectorAll('a.item').length, scripts: document.querySelectorAll('script').length, directFetch: typeof fetch }; }, settings: function () { return [{key:"quality",type:"select",label:"Quality",options:["FHD"]}]; } };"#
        let worker = runtime(source, format: .harbor); defer { worker.dispose() }
        let metadata = try await worker.metadata()
        XCTAssertEqual(metadata["id"].string, "owned.html")
        XCTAssertEqual(Set(metadata["methods"].array.compactMap(\.string)), ["search", "settings"])
        let result = try await worker.call("search", arguments: [.string("café"), .integer(3)])
        XCTAssertEqual(result["query"].string, "café"); XCTAssertEqual(result["page"].integer, 3)
        XCTAssertEqual(result["title"].string, "Owned title"); XCTAssertEqual(result["path"].string, "/owned")
        XCTAssertEqual(result["count"].integer, 1); XCTAssertEqual(result["scripts"].integer, 0)
        XCTAssertEqual(result["directFetch"].string, "undefined")
        let fields = try await worker.call("settings"); XCTAssertEqual(fields.array.first?["key"].string, "quality")
    }

    func testProviderCompatibilityRetainsCommonJSHelpersAndSettingsPerInstance() async throws {
        let source = #"const crypto = require("crypto-js"); const cheerio = require("cheerio"); module.exports.getStreams = function (id, kind, season, episode) { return [{ url:"https://example.invalid/"+id+"/"+kind+"/"+season+"/"+episode, name:crypto.MD5("abc").toString(), title:cheerio.load("<b>owned</b>")("b").text(), headers:{"x-owned":SCRAPER_SETTINGS.token,"x-buffer":Buffer.from("fixture").toString("base64")} }]; };"#
        let one = runtime(source, id: "owned.a", format: .providerScript, configuration: .object(["token": .string("owned-a")]))
        let two = runtime(source, id: "owned.b", format: .providerScript, configuration: .object(["token": .string("owned-b")]))
        defer { one.dispose(); two.dispose() }
        let request: JSONValue = .object(["tmdb": .object(["id": .integer(42)]), "type": .string("series"), "season": .integer(2), "episode": .integer(7)])
        for (worker, token) in [(one, "owned-a"), (two, "owned-b")] {
            let response = try await worker.call("streams", arguments: [request]), row = try XCTUnwrap(response.array.first)
            XCTAssertEqual(row["url"].string, "https://example.invalid/42/tv/2/7")
            XCTAssertEqual(row["name"].string, "900150983cd24fb0d6963f7d28e17f72"); XCTAssertEqual(row["title"].string, "owned")
            XCTAssertEqual(row["headers"]["x-owned"].string, token); XCTAssertEqual(row["headers"]["x-buffer"].string, "Zml4dHVyZQ==")
        }
    }

    func testHTTPAndGRPCUseTheHostContractAndReferenceConcurrencyLimits() async throws {
        let source = #"var plugin = { id:"owned.bridge", name:"Bridge", search:async function () { return await Promise.all(Array.from({length:12},function (_,i) { return harbor.http('https://example.invalid/'+i,{responseType:'json'}); })); }, content:async function () { var value=await harbor.grpc('https://example.invalid/grpc',new Uint8Array([1,2,3]),{mode:'grpc-web'}); return {body:Array.from(value.body),message:Array.from(value.messages[0])}; } };"#
        let transport = OwnedPluginTransport(), workers = [runtime(source, transport: transport), runtime(source, transport: transport), runtime(source, transport: transport)]
        defer { workers.forEach { $0.dispose() } }
        let single = OwnedPluginTransport(), one = runtime(source, transport: single); defer { one.dispose() }
        let first = try await one.call("search"); XCTAssertEqual(first.array.count, 12)
        let singleResult = await single.snapshot(); XCTAssertEqual(singleResult.0, 12); XCTAssertLessThanOrEqual(singleResult.1, 6)
        for worker in workers { _ = try await worker.metadata() }
        async let a = workers[0].call("search")
        async let b = workers[1].call("search")
        async let c = workers[2].call("search")
        let (firstBatch, secondBatch, thirdBatch) = try await (a, b, c)
        XCTAssertTrue([firstBatch, secondBatch, thirdBatch].allSatisfy { $0.array.count == 12 })
        let shared = await transport.snapshot(); XCTAssertEqual(shared.0, 36); XCTAssertLessThanOrEqual(shared.1, 16)
        let grpc = try await one.call("content")
        XCTAssertEqual(grpc["body"], .array([.integer(4), .integer(5), .integer(6)]))
        XCTAssertEqual(grpc["message"], .array([.integer(7), .integer(8), .integer(9)]))
        let recorded = await single.snapshot()
        XCTAssertEqual(recorded.2.last?["requestBase64"].string, "AQID"); XCTAssertEqual(recorded.2.last?["opts"]["mode"].string, "grpc-web")
    }

    func testCancellationRejectsItsLateResultAndLeavesAnotherCallUsable() async throws {
        let transport = OwnedPluginTransport(holdFirst: true), worker = runtime(httpSource, transport: transport)
        defer { worker.dispose(); Task { await transport.release() } }
        _ = try await worker.metadata()
        let pending = Task { try await worker.call("search") }
        try await transport.waitUntilStarted(); pending.cancel()
        switch await pending.result { case .success: XCTFail("Cancelled operation returned content"); case .failure(let error): XCTAssertTrue(error is CancellationError) }
        await transport.release()
        let result = try await worker.call("search"); XCTAssertEqual(result["value"].string, "host-owned")
    }

    func testLateHostResponseCannotPublishAfterAnOwnerOrActivationChange() async throws {
        for ownerChange in [false, true] {
            let context = OwnedPluginScope(), transport = OwnedPluginTransport(holdFirst: true)
            let worker = runtime(httpSource, context: context, transport: transport)
            defer { worker.dispose(); Task { await transport.release() } }
            _ = try await worker.metadata()
            let pending = Task { try await worker.call("search") }
            try await transport.waitUntilStarted()
            context.value = PluginExecutionScope(owner: ownerChange ? "another-owner" : context.value.owner, activation: UUID())
            await transport.release()
            switch await pending.result { case .success: XCTFail("Old scope published content"); case .failure: break }
            XCTAssertTrue(worker.logs.isEmpty)
            do { _ = try await worker.call("search"); XCTFail("Old runtime restarted for a different scope") } catch {}
        }
    }

    func testTimeoutTerminatesABusyWorkerWithoutBlockingAnotherInstance() async throws {
        let busy = runtime(#"var plugin={id:'owned.busy',name:'Busy',search:function(){for(;;){}}};"#)
        let normal = runtime(#"var plugin={id:'owned.quick',name:'Quick',search:function(){return {value:'quick'};}};"#)
        defer { busy.dispose(); normal.dispose() }
        _ = try await busy.metadata(); _ = try await normal.metadata()
        async let quick = normal.call("search")
        let started = Date()
        do { _ = try await busy.call("search", timeout: 0.2); XCTFail("Busy worker did not time out") }
        catch let error as HarborPluginRuntimeError { XCTAssertEqual(error.code, "plugin-timeout") }
        let result = try await quick; XCTAssertEqual(result["value"].string, "quick")
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testInitializationAndMissingMethodsReportRealFailuresInsteadOfEmptyResults() async throws {
        let bad = runtime("throw new Error('owned broken provider');")
        defer { bad.dispose() }
        do { _ = try await bad.metadata(); XCTFail("Broken source initialized") }
        catch let error as HarborPluginRuntimeError { XCTAssertEqual(error.code, "plugin-runtime"); XCTAssertTrue(error.detail.contains("owned broken provider")) }
        let good = runtime(#"var plugin={id:'owned.methods',name:'Methods',search:function(){return [];}};"#)
        defer { good.dispose() }
        do { _ = try await good.call("chapters"); XCTFail("Missing method fabricated results") }
        catch let error as HarborPluginRuntimeError { XCTAssertEqual(error.code, "plugin-call"); XCTAssertTrue(error.detail.contains("no method: chapters")) }
        do { _ = try await good.call("not-a-harbor-method"); XCTFail("Unsupported host method accepted") }
        catch let error as HarborPluginRuntimeError { XCTAssertEqual(error.code, "plugin-method") }
    }
}
