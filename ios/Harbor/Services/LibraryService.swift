import Foundation
import CryptoKit

struct LibraryService: Sendable {
    private let http = HTTPClient()
    func records(_ session: AccountSession) async throws -> [JSONValue] {
        let metadata = try await request("datastoreMeta", session: session)
        guard case .array(let pairs) = metadata else { throw HarborError(code: "invalid-library-response") }
        let ids = pairs.compactMap { $0.array.first?.string }.map(JSONValue.string)
        guard !ids.isEmpty else { return [] }
        let response = try await request("datastoreGet", session: session, fields: ["ids": .array(ids), "all": .bool(true)])
        guard case .array(let records) = response else { throw HarborError(code: "invalid-library-response") }
        return records
    }
    func record(_ id: String, session: AccountSession) async throws -> JSONValue? {
        let response = try await request("datastoreGet", session: session, fields: ["ids": .array([.string(id)]), "all": .bool(false)])
        guard case .array(let records) = response else { throw HarborError(code: "invalid-library-response") }
        return records.first { $0["_id"].string == id }
    }
    func save(_ record: JSONValue, session: AccountSession) async throws {
        _ = try await request("datastorePut", session: session, fields: ["changes": .array([record])])
    }
    private func request(_ method: String, session: AccountSession, fields: [String: JSONValue] = [:]) async throws -> JSONValue {
        var body = fields
        body["authKey"] = .string(session.authKey); body["collection"] = .string("libraryItem")
        let value = try await http.post("https://api.strem.io/api/\(method)", body: .object(body))
        guard value["error"] == .null, case .object(let envelope) = value, let result = envelope["result"] else { throw HarborError(code: "invalid-library-response") }
        return result
    }
}

actor LibraryCache {
    func read(owner: String) throws -> [JSONValue] {
        do {
            let data = try Data(contentsOf: location(owner))
            guard data.count <= 8 * 1024 * 1024 else { throw HarborError(code: "library-cache-too-large") }
            return try JSONDecoder().decode([JSONValue].self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        catch { throw HarborError(code: "library-cache-read-failed") }
    }
    func save(_ records: [JSONValue], owner: String) throws {
        do {
            let data = try JSONEncoder().encode(records)
            guard data.count <= 8 * 1024 * 1024 else { throw HarborError(code: "library-cache-too-large") }
            let file = try location(owner)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { throw HarborError(code: "library-cache-write-failed") }
    }
    private func location(_ owner: String) throws -> URL {
        let hash = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Harbor/library-\(hash).json")
    }
}
