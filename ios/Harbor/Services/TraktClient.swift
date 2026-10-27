import Foundation

actor TraktClient {
    static let shared = TraktClient()
    typealias Lease = @Sendable () async -> Bool
    typealias Active = @MainActor @Sendable () -> Bool
    typealias Transport = @Sendable (URLRequest) async throws -> TraktReply
    typealias Sleep = @Sendable (TimeInterval) async throws -> Void
    private let transport: Transport
    private let sleep: Sleep
    private let now: @Sendable () -> Date
    private var tail: Task<Void, Never>?
    private var lastWrite = Date.distantPast
    init(transport: @escaping Transport = { try await HTTPClient().traktReply($0) },
         sleep: @escaping Sleep = { try await Task.sleep(for: .seconds($0)) }, now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport; self.sleep = sleep; self.now = now
    }
    func reply(_ endpoint: TraktEndpoint, token: String? = nil, current: @escaping Lease = { true }, accept: Lease? = nil) async throws -> TraktReply {
        try Task.checkCancellation()
        let request = try endpoint.request(token: token), previous = tail
        let result = Task<TraktReply, Error> {
            await previous?.value
            guard await current() else { throw CancellationError() }
            if request.httpMethod != "GET" {
                let delay = 1 - self.now().timeIntervalSince(self.lastWrite)
                if delay > 0 { try await self.sleep(delay) }
                guard await current() else { throw CancellationError() }; self.lastWrite = self.now()
            }
            let reply = try await self.transport(request)
            guard await (accept ?? current)() else { throw CancellationError() }; return reply
        }
        tail = Task { _ = try? await result.value }
        let reply = try await result.value
        if accept == nil { try Task.checkCancellation() }; return reply
    }
    func pause(_ seconds: TimeInterval) async throws { try await sleep(seconds) }
}
