import XCTest
@testable import Harbor

private actor OwnedNativeNetwork: HarborNativeNetworkCalling {
    private var requests: [HarborNetworkRequest] = []
    private let data: Data
    init(_ data: Data) { self.data = data }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        return HarborNetworkResponse(status: 200, ok: true, headers: ["content-type": "application/octet-stream"], bodyBase64: data.base64EncodedString(), url: request.url)
    }
    func captured() -> [HarborNetworkRequest] { requests }
}

@MainActor private final class OwnedNetworkScope { var value = PluginExecutionScope(owner: "owned-native-network", activation: UUID()) }

final class HarborNativeNetworkTests: XCTestCase {
    func testHTTPAdapterKeepsOwnedGatesTextAndOriginalBinaryBytes() async throws {
        let data = Data([0xef, 0xbb, 0xbf, 0x61, 0x62, 0x63])
        let network = OwnedNativeNetwork(data)
        let transport = HarborNativePluginTransport(policy: .reading(baseURL: "https://owned.example.org", blockedHosts: ["owned-tracker.invalid"]), network: network)
        let payload: JSONValue = .object(["url": .string("https://cdn.example.org/owned"), "opts": .object(["method": .string("GET"), "body": .string("never-on-get"), "allowReferer": .string("https://forged.invalid"), "responseType": .string("text")])])
        let text = try await transport.perform(.http, payload: payload); XCTAssertEqual(text["body"].string, "abc")
        var binary = payload.objectValue; binary["opts"] = .object(["responseType": .string("base64"), "redirect": .string("error")])
        let response = try await transport.perform(.http, payload: .object(binary)); XCTAssertEqual(response["body"].string, data.base64EncodedString())
        let requests = await network.captured(); XCTAssertEqual(requests.count, 2)
        XCTAssertNil(requests[0].bodyBase64); XCTAssertEqual(requests[0].allowReferer, "https://owned.example.org")
        XCTAssertNil(requests[0].allowCookie); XCTAssertFalse(requests[0].openHeaders)
        XCTAssertEqual(requests[0].blockedHosts, ["owned-tracker.invalid"]); XCTAssertFalse(requests[1].followRedirects)
    }

    func testGRPCAdapterKeepsModeHeadersFramesAndReferencePolicy() async throws {
        let network = OwnedNativeNetwork(Data([0, 0, 0, 0, 3, 1, 2, 3]))
        var policy = HarborPluginNetworkPolicy.stream(installing: false, blockedHosts: [])
        policy.maxBytes = 1024
        let transport = HarborNativePluginTransport(policy: policy, network: network)
        for mode in ["grpc", "grpc-web"] {
            let result = try await transport.perform(.grpc, payload: .object(["url": .string("https://example.invalid/owned"), "requestBase64": .string("BAU="), "opts": .object(["mode": .string(mode), "timeoutMs": .integer(10)])]))
            XCTAssertEqual(result["body"].string, "AQID"); XCTAssertEqual(result["messages"].array, [.string("AQID")])
        }
        let requests = await network.captured(); XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.method, "POST"); XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(request.bodyBase64)), Data([0, 0, 0, 0, 2, 4, 5]))
            XCTAssertEqual(request.timeoutMs, 1000); XCTAssertEqual(request.headers["grpc-timeout"], "1000m")
            XCTAssertEqual(request.headers["grpc-accept-encoding"], "identity"); XCTAssertFalse(request.openHeaders)
            XCTAssertFalse(request.strictLimit); XCTAssertFalse(request.publicNetworkOnly)
            XCTAssertEqual(request.maxResponseBytes, 8 * 1024 * 1024); XCTAssertEqual(request.allowCookie, request.url)
        }
        XCTAssertEqual(requests[0].headers["content-type"], "application/grpc"); XCTAssertEqual(requests[0].headers["te"], "trailers")
        XCTAssertEqual(requests[1].headers["content-type"], "application/grpc-web+proto"); XCTAssertEqual(requests[1].headers["x-grpc-web"], "1")
    }

    func testNativeContinuationResumesOnceAcrossConcurrentCancellationAndCompletion() async throws {
        let reply = HarborNetworkResponse(status: 200, ok: true, headers: [:], bodyBase64: "", url: "https://example.invalid/owned")
        for _ in 0..<16 {
            let operation = HarborNetworkOperation(), group = DispatchGroup()
            do {
                let result: HarborNetworkResponse = try await withCheckedThrowingContinuation { continuation in
                    XCTAssertTrue(operation.prepare(continuation))
                    group.enter(); DispatchQueue.global().async { operation.cancel(); group.leave() }
                    group.enter(); DispatchQueue.global().async { operation.finish(.success(reply)); group.leave() }
                }
                XCTAssertEqual(result.status, 200)
            } catch { XCTAssertTrue(error is CancellationError) }
            await withCheckedContinuation { continuation in group.notify(queue: .global()) { continuation.resume() } }
        }
        let cancelled = HarborNetworkOperation(); cancelled.cancel()
        do {
            let _: HarborNetworkResponse = try await withCheckedThrowingContinuation { continuation in XCTAssertFalse(cancelled.prepare(continuation)) }
            XCTFail("Cancellation before setup was lost")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testActualNativeABIDeniesPrivateTargetsBeforeAnyConnection() async throws {
        for url in ["http://127.1/owned", "https://localhost/owned", "http://[::1]/owned"] {
            do { _ = try await HarborNativeNetwork().perform(HarborNetworkRequest(url: url)); XCTFail("Private target accepted") }
            catch { XCTAssertEqual((error as? HarborError)?.code, "plugin-network-private") }
        }
    }

    @MainActor func testMaximumRPCResponseCrossesActualWebKitWorkerBridge() async throws {
        let count = 8 * 1024 * 1024 - 5
        let size = UInt32(count)
        var bytes = Data([0, UInt8((size >> 24) & 255), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)])
        bytes.append(Data(repeating: 7, count: count))
        let scope = OwnedNetworkScope()
        let transport = HarborNativePluginTransport(policy: .stream(installing: false, blockedHosts: []), network: OwnedNativeNetwork(bytes))
        let source = #"var plugin={id:'owned.maximum',name:'Owned maximum',search:async function(){var result=await harbor.grpc('https://example.invalid/owned',new Uint8Array([1]));return {count:result.body.length,first:result.body[0],last:result.body[result.body.length-1]};}};"#
        let runtime = HarborPluginRuntime(id: "owned.maximum", name: "Owned maximum", source: source, format: .raw,
            scope: scope.value, currentScope: { scope.value }, transport: transport)
        defer { runtime.dispose() }
        let result = try await runtime.call("search", timeout: 60)
        XCTAssertEqual(result["count"].integer, count); XCTAssertEqual(result["first"].integer, 7); XCTAssertEqual(result["last"].integer, 7)
    }
}
