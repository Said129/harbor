import Foundation
import HarborCore

struct HarborError: Error, LocalizedError, Sendable {
    let code: String
    var errorDescription: String? {
        switch code {
        case "torrent-resolver-pending": "Esta fuente requiere el motor torrent o Debrid, todavía pendiente en iPhone."
        case "youtube-resolver-pending": "La resolución de YouTube todavía está pendiente."
        case "addon-not-configured": "Configura este addon antes de reproducir."
        case "no-streams": "Los addons consultados no devolvieron streams para este título."
        case "no-metadata": "Los addons no devolvieron metadata para este título."
        case "network": "La solicitud de red falló. Puedes volver a intentarlo."
        default: "Harbor: \(code)"
        }
    }
}

struct CoreBridge: Sendable {
    private struct Envelope<T: Decodable>: Decodable {
        let ok: Bool
        let data: T?
        let error: Failure?
        struct Failure: Decodable { let code: String }
    }

    func call<T: Decodable & Sendable>(_ operation: String, _ fields: [String: JSONValue] = [:], as: T.Type = T.self) async throws -> T {
        try Task.checkCancellation()
        var request = fields
        request["operation"] = .string(operation)
        let bytes = try JSONEncoder().encode(JSONValue.object(request))
        do {
            let result: T = try await Task.detached(priority: .userInitiated) {
                try Self.invoke(bytes, as: T.self)
            }.value
            try Task.checkCancellation()
            return result
        } catch is CancellationError { throw CancellationError() }
        catch {
            await Diagnostics.shared.recordFailure(error)
            throw error
        }
    }

    static func invoke<T: Decodable>(_ bytes: Data, as: T.Type) throws -> T {
        guard harbor_ios_abi_version() == 1 else { throw HarborError(code: "abi-version") }
        guard !bytes.isEmpty, bytes.count <= 8 * 1024 * 1024 else { throw HarborError(code: "invalid-request-size") }
        let pointer = bytes.withUnsafeBytes { buffer in
            harbor_ios_call(buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count)
        }
        guard let pointer else { throw HarborError(code: "core-no-response") }
        defer { harbor_ios_response_free(pointer) }
        let data = Data(bytes: pointer, count: strlen(pointer))
        let response = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard response.ok, let value = response.data else { throw HarborError(code: response.error?.code ?? "invalid-core-response") }
        return value
    }
}
