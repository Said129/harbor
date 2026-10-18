import Foundation
import Network
import XCTest
@testable import Harbor

final class EBookDownloadTests: XCTestCase {
    func testTransientPublisherErrorRetriesOnceAndCachesOnlyTheCompleteEPUB() async throws {
        let server = try Publisher(statuses: [504, 200], body: fixture())
        let url = try await server.start()
        defer { server.stop() }
        let book = EBook(id: UUID().uuidString, title: "Publisher recovery", epub: url.absoluteString)
        let owner = UUID().uuidString
        let service = EBookService()
        let publication = try await service.open(book, owner: owner)
        XCTAssertEqual(publication.chapters.map(\.title), ["First section", "Second section"])
        XCTAssertEqual(server.requests, 2)
        server.stop()
        let restored = EBookService()
        let cached = try await restored.open(book, owner: owner)
        XCTAssertEqual(cached.chapters.map(\.title), publication.chapters.map(\.title))
        XCTAssertEqual(server.requests, 2, "Reopening from disk must not issue another HTTP request")
        try await restored.remove(book, owner: owner)
        try await service.remove(book, owner: owner)
    }

    func testPermanentPublisherErrorDoesNotRetryOrPersistItsBody() async throws {
        let server = try Publisher(statuses: [404, 200], body: fixture())
        let url = try await server.start()
        defer { server.stop() }
        let book = EBook(id: UUID().uuidString, title: "Missing publication", epub: url.absoluteString)
        let owner = UUID().uuidString
        let service = EBookService()
        do { _ = try await service.open(book, owner: owner); XCTFail("HTTP 404 is not a publication") }
        catch let error as HarborError { XCTAssertEqual(error.code, "ebook-network") }
        XCTAssertEqual(server.requests, 1, "A permanent HTTP error must not consume a retry")
        let publication = try await service.open(book, owner: owner)
        XCTAssertEqual(publication.chapters.count, 2)
        XCTAssertEqual(server.requests, 2, "The failed response body must not have been cached as an EPUB")
        try await service.remove(book, owner: owner)
    }

    func testRepeatedPublisherErrorsStopAfterTwoRequestsAndLeaveTheBookRetryable() async throws {
        let server = try Publisher(statuses: [503, 503, 200], body: fixture())
        let url = try await server.start()
        defer { server.stop() }
        let book = EBook(id: UUID().uuidString, title: "Unavailable publication", epub: url.absoluteString)
        let owner = UUID().uuidString
        let service = EBookService()
        do { _ = try await service.open(book, owner: owner); XCTFail("Repeated HTTP 503 must finish with an error") }
        catch let error as HarborError { XCTAssertEqual(error.code, "ebook-network") }
        XCTAssertEqual(server.requests, 2, "Publisher outages must not create an unbounded retry loop")
        let publication = try await service.open(book, owner: owner)
        XCTAssertEqual(publication.chapters.count, 2)
        XCTAssertEqual(server.requests, 3, "A later user retry must fetch a new publication")
        try await service.remove(book, owner: owner)
    }

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reader", withExtension: "epub", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// Real loopback HTTP exercises URLSession and the production downloader.
    private final class Publisher: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "harbor.ebook-download-test")
        private let lock = NSLock()
        private let statuses: [Int]
        private let body: Data
        private var count = 0
        private var stopped = false
        private var startCompleted = false // Accessed only on the listener's serial queue.
        var requests: Int { lock.lock(); defer { lock.unlock() }; return count }

        init(statuses: [Int], body: Data) throws {
            self.statuses = statuses; self.body = body
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
        }

        func start() async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    guard !startCompleted else { return }
                    switch state {
                    case .ready:
                        startCompleted = true
                        if let port = listener.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)/book.epub") {
                            continuation.resume(returning: url)
                        } else { continuation.resume(throwing: HarborError(code: "ebook-network")) }
                    case .failed(let error): startCompleted = true; continuation.resume(throwing: error)
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { connection.cancel(); return }
                    connection.start(queue: queue)
                    receive(connection, request: Data())
                }
                listener.start(queue: queue)
            }
        }

        private func receive(_ connection: NWConnection, request: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [self] data, _, ended, error in
                var request = request
                if let data { request.append(data) }
                guard error == nil, request.count <= 16 * 1024 else { connection.cancel(); return }
                guard request.range(of: Data("\r\n\r\n".utf8)) != nil else {
                    if ended { connection.cancel() } else { receive(connection, request: request) }
                    return
                }
                lock.lock()
                let status = statuses[min(count, statuses.count - 1)]
                count += 1
                lock.unlock()
                let header = "HTTP/1.1 \(status) Response\r\nContent-Type: application/epub+zip\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
            }
        }

        func stop() {
            lock.lock()
            guard !stopped else { lock.unlock(); return }
            stopped = true
            lock.unlock()
            listener.cancel()
        }
    }
}
