import Foundation
import HarborCore

struct HarborNetworkRequest: Encodable, Sendable {
    let url: String
    var method = "GET"
    var headers: [String: String] = [:]
    var bodyBase64: String?
    var timeoutMs: UInt64 = 20_000
    var followRedirects = true
    var maxResponseBytes = 8 * 1024 * 1024
    var strictLimit = false
    var publicNetworkOnly = false
    var allowLocalNetwork = false
    var allowReferer: String?
    var allowCookie: String?
    var openHeaders = false
    var blockedHosts: [String] = []
}

struct HarborNetworkResponse: Decodable, Sendable {
    let status: Int
    let ok: Bool
    let headers: [String: String]
    let bodyBase64: String
    let url: String
    var protocolVersion: String? = nil
    func bytes() throws -> Data {
        guard let data = Data(base64Encoded: bodyBase64), data.count <= 8 * 1024 * 1024 else { throw HarborError(code: "plugin-network-response-format") }
        return data
    }
}

protocol HarborNativeNetworkCalling: Sendable {
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse
}

/// NSLock protects a one-shot continuation across native completion, cancellation and handle setup.
final class HarborNetworkOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HarborNetworkResponse, Error>?
    private var finished = false
    private var cancelled = false
    private var handle: UInt64 = 0

    func prepare(_ continuation: CheckedContinuation<HarborNetworkResponse, Error>) -> Bool {
        lock.lock()
        if finished { lock.unlock(); continuation.resume(throwing: CancellationError()); return false }
        self.continuation = continuation; lock.unlock(); return true
    }

    func attach(_ handle: UInt64) {
        lock.lock(); self.handle = handle; let shouldCancel = cancelled; lock.unlock()
        if shouldCancel { harbor_ios_network_cancel(handle) }
    }

    func cancel() {
        lock.lock(); cancelled = true; let handle = handle
        let continuation = finished ? nil : self.continuation
        finished = true; self.continuation = nil; lock.unlock()
        if handle != 0 { harbor_ios_network_cancel(handle) }
        continuation?.resume(throwing: CancellationError())
    }

    func finish(_ result: Result<HarborNetworkResponse, Error>) {
        lock.lock()
        let continuation = finished ? nil : self.continuation
        finished = true; self.continuation = nil; lock.unlock()
        continuation?.resume(with: result)
    }

    func receive(_ bytes: UnsafePointer<UInt8>?, length: Int) {
        struct Envelope: Decodable {
            let ok: Bool
            let data: HarborNetworkResponse?
            let error: Failure?
            struct Failure: Decodable { let code: String }
        }
        do {
            guard let bytes, length > 0, length <= 16 * 1024 * 1024 else { throw HarborError(code: "plugin-network-response-format") }
            let response = try JSONDecoder().decode(Envelope.self, from: Data(bytes: bytes, count: length))
            if !response.ok {
                if response.error?.code == "plugin-network-cancelled" { throw CancellationError() }
                throw HarborError(code: response.error?.code ?? "plugin-network-response-format")
            }
            guard let value = response.data else { throw HarborError(code: "plugin-network-response-format") }
            finish(.success(value))
        } catch let error as HarborError { finish(.failure(error)) }
        catch is CancellationError { finish(.failure(CancellationError())) }
        catch { finish(.failure(HarborError(code: "plugin-network-response-format"))) }
    }
}

private func harborNetworkCompletion(_ context: UnsafeMutableRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int) {
    guard let context else { return }
    let operation = Unmanaged<HarborNetworkOperation>.fromOpaque(context).takeRetainedValue()
    operation.receive(bytes, length: length)
}

/// Async work runs on Rust's network executor, without blocking the main actor or a Swift executor thread.
struct HarborNativeNetwork: HarborNativeNetworkCalling {
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        try Task.checkCancellation()
        guard harbor_ios_network_abi_version() == 1 else { throw HarborError(code: "plugin-network-abi") }
        let data = try JSONEncoder().encode(request)
        guard !data.isEmpty, data.count <= 16 * 1024 * 1024 else { throw HarborError(code: "plugin-network-request-size") }
        let operation = HarborNetworkOperation()
        let response: HarborNetworkResponse = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard operation.prepare(continuation) else { return }
                let context = Unmanaged.passRetained(operation).toOpaque()
                let handle = data.withUnsafeBytes { buffer in
                    harbor_ios_network_start(buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count, context, harborNetworkCompletion)
                }
                if handle == 0 {
                    Unmanaged<HarborNetworkOperation>.fromOpaque(context).release()
                    operation.finish(.failure(HarborError(code: "plugin-network-unavailable")))
                } else { operation.attach(handle) }
            }
        } onCancel: { operation.cancel() }
        try Task.checkCancellation()
        return response
    }
}

struct HarborPluginNetworkPolicy: Sendable {
    let sameSiteHeaders: Bool
    let publicOnly: Bool
    let openHeaders: Bool
    let baseURL: String?
    let blockedHosts: [String]
    var maxBytes = 8 * 1024 * 1024
    var allowLocalNetwork = false

    static func stream(installing: Bool, blockedHosts: [String]) -> Self {
        .init(sameSiteHeaders: true, publicOnly: true, openHeaders: !installing, baseURL: nil, blockedHosts: blockedHosts)
    }
    static func reading(baseURL: String?, blockedHosts: [String]) -> Self {
        .init(sameSiteHeaders: false, publicOnly: false, openHeaders: false, baseURL: baseURL, blockedHosts: blockedHosts, allowLocalNetwork: true)
    }
}

struct HarborNativePluginTransport: HarborPluginHostTransport {
    let policy: HarborPluginNetworkPolicy
    var network: any HarborNativeNetworkCalling = HarborNativeNetwork()
    private static let httpUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

    func perform(_ kind: HarborPluginBridgeKind, payload: JSONValue) async throws -> JSONValue {
        guard let url = payload["url"].string else { throw HarborError(code: "plugin-network-url") }
        let options = payload["opts"]
        var request = HarborNetworkRequest(url: url)
        request.headers = options["headers"].objectValue.compactMapValues(\.string)
        request.timeoutMs = UInt64(HarborPluginGRPC.timeoutMilliseconds(try? options["timeoutMs"].decoded(Double.self)))
        request.maxResponseBytes = min(max(0, policy.maxBytes), 8 * 1024 * 1024)
        request.publicNetworkOnly = policy.publicOnly; request.strictLimit = policy.publicOnly
        request.allowLocalNetwork = policy.allowLocalNetwork
        request.allowReferer = policy.sameSiteHeaders ? url : policy.baseURL
        request.allowCookie = policy.sameSiteHeaders ? url : nil
        request.blockedHosts = policy.blockedHosts
        if kind == .grpc {
            // runPluginGrpc uses the normal byte transport and its fixed 8 MiB cap.
            request.publicNetworkOnly = false; request.strictLimit = false; request.maxResponseBytes = 8 * 1024 * 1024
            request.method = "POST"
            request.bodyBase64 = try HarborPluginGRPC.requestFrame(payload["requestBase64"].string ?? "").base64EncodedString()
            // A frame includes five bytes beyond the 8 MiB protobuf limit.
            let web = options["mode"].string == "grpc-web"
            let contentType = web ? "application/grpc-web+proto" : "application/grpc"
            setDefault(contentType, key: "content-type", headers: &request.headers)
            setDefault(contentType, key: "accept", headers: &request.headers)
            replace("identity", key: "grpc-accept-encoding", headers: &request.headers)
            setDefault(String(request.timeoutMs) + "m", key: "grpc-timeout", headers: &request.headers)
            if web { replace("1", key: "x-grpc-web", headers: &request.headers) }
            else { replace("trailers", key: "te", headers: &request.headers) }
            let response = try await network.perform(request)
            return try HarborPluginGRPC.response(status: response.status, headers: response.headers, bytes: response.bytes())
        }
        request.method = options["method"].string.flatMap { $0.isEmpty ? nil : $0 }?.uppercased() ?? "GET"
        if !["GET", "HEAD"].contains(request.method), let body = options["body"].string { request.bodyBase64 = Data(body.utf8).base64EncodedString() }
        request.openHeaders = policy.openHeaders
        request.followRedirects = !["manual", "error"].contains(options["redirect"].string ?? "")
        setDefault(Self.httpUA, key: "user-agent", headers: &request.headers)
        let response = try await network.perform(request)
        let data = try response.bytes()
        let body: String
        if options["responseType"].string == "base64" { body = data.base64EncodedString() }
        else { var text = String(decoding: data, as: UTF8.self); if text.hasPrefix("\u{feff}") { text.removeFirst() }; body = text }
        return .object(["status": .integer(Int64(response.status)), "ok": .bool(response.ok), "headers": .object(response.headers.mapValues(JSONValue.string)), "body": .string(body), "url": .string(response.url)])
    }

    private func setDefault(_ value: String, key: String, headers: inout [String: String]) {
        if !headers.keys.contains(where: { $0.lowercased() == key }) { headers[key] = value }
    }
    private func replace(_ value: String, key: String, headers: inout [String: String]) {
        headers = headers.filter { $0.key.lowercased() != key }; headers[key] = value
    }
}
