import Foundation
import HarborCore

struct HarborError: Error, LocalizedError, Sendable {
    let code: String
    var errorDescription: String? {
        switch code {
        case "invalid-account-request": "Introduce tu correo y contraseña de Stremio."
        case "account-rejected": "Stremio ha rechazado el acceso. Comprueba tus datos o vuelve a iniciar sesión."
        case "invalid-account-response", "invalid-account-store": "No se pudo recuperar tu cuenta. Los datos guardados se han conservado."
        case "account-auth-response": "Stremio no devolvió los datos necesarios para iniciar sesión. Inténtalo de nuevo."
        case "account-addons-response": "No se pudieron recuperar los addons de Stremio. Tu configuración guardada se ha conservado. Inténtalo de nuevo."
        case "account-addons-save-response": "No se pudo confirmar el cambio de addons en Stremio. Pulsa Sincronizar antes de volver a editar."
        case "account-local-save-failed": "Los addons cambiaron en tu cuenta, pero no se pudo guardar la copia local. Pulsa Sincronizar para recuperarlos."
        case "account-busy": "Espera a que termine la operación de tu cuenta."
        case "account-cancelled": "Se canceló el inicio de sesión."
        case "account-browser-unavailable": "No se pudo abrir el acceso de Stremio. Puedes usar correo y contraseña."
        case "account-timeout": "El acceso de Stremio tardó demasiado. Inténtalo otra vez."
        case "torrent-resolver-pending": "Esta fuente requiere el motor torrent o Debrid, todavía pendiente en iPhone."
        case "youtube-resolver-pending": "La resolución de YouTube todavía está pendiente."
        case "addon-not-configured": "Configura este addon antes de reproducir."
        case "no-streams": "Los addons consultados no devolvieron streams para este título."
        case "no-metadata": "Los addons no devolvieron metadata para este título."
        case "network": "La solicitud de red falló. Puedes volver a intentarlo."
        case "resume-read-failed", "invalid-resume-store", "unsupported-resume-version": "No se pudo leer el progreso guardado. Los datos se han conservado."
        case "resume-write-failed", "resume-store-too-large": "No se pudo guardar el progreso. Los datos anteriores se han conservado."
        case "resume-store-unavailable": "El almacenamiento del progreso no está disponible."
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
