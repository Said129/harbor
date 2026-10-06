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
        case "invalid-catalog-response", "catalog-response": "Este addon no ha devuelto un catálogo válido."
        case "invalid-artwork", "artwork-unavailable", "artwork-too-large": "No se pudo cargar esta imagen."
        case "invalid-library-response": "No se pudo recuperar la biblioteca de Stremio. Tu copia guardada se ha conservado."
        case "invalid-watched-state": "No se pudo actualizar el estado visto. El progreso guardado se ha conservado."
        case "library-cache-read-failed", "library-cache-too-large": "No se pudo leer la biblioteca guardada. Los datos se han conservado."
        case "library-cache-write-failed": "No se pudo guardar la biblioteca en este iPhone. Reintenta la sincronización."
        case "metadata-not-configured": "Introduce tu clave de TMDB para activar este proveedor."
        case "download-index": "No se pudo acceder a la lista de descargas. Los archivos se conservan."
        case "music-file", "invalid-music-tags": "No se pudo leer este archivo de música. Prueba con otro archivo de audio."
        case "music-store": "No se pudo guardar tu biblioteca de Música. Los datos anteriores se conservan."
        case "music-capacity": "La biblioteca ha alcanzado el espacio reservado para Música. Elimina archivos para importar otros."
        case "music-folder": "No se pudo leer la carpeta seleccionada. Comprueba su acceso en Archivos y vuelve a intentarlo."
        case "music-folder-limit": "Selecciona una carpeta más pequeña, con hasta 500 archivos de audio. Tu biblioteca anterior se conserva."
        case "subtitle-file": "No se pudo cargar ese subtítulo. Selecciona un archivo .srt, .ass, .ssa, .vtt o .sub compatible, de hasta 8 MB."
        case "subtitle-capacity": "Esta reproducción ya tiene 24 archivos de subtítulos importados. Cierra el reproductor y vuelve a abrir el vídeo antes de importar más."
        case "music-player": "No se pudo iniciar la reproducción de Música."
        case "music-playlist-name": "El nombre de la lista debe tener entre 1 y 100 caracteres."
        case "music-playlist-duplicate-name": "Ya existe una lista con este nombre. Elige otro nombre."
        case "music-playlist-order": "No se pudo cambiar el orden de las canciones."
        case "download-source": "Esta fuente no se puede guardar como un archivo. Elige un enlace directo de vídeo o audio."
        case "download-missing": "El archivo descargado ya no está disponible en este iPhone."
        case "download-active": "Este título ya tiene una descarga activa. Puedes verla en Descargas."
        case "ebook-store": "No se pudo guardar tu estantería. Los libros y el progreso anteriores se conservan."
        case "ebook-size": "Este EPUB es demasiado grande para el lector."
        case "ebook-encrypted": "Este EPUB contiene recursos cifrados que el lector no puede abrir."
        case "ebook-format", "ebook-empty": "No se pudo leer la estructura de este EPUB. Prueba con otro archivo."
        case "ebook-missing": "El libro no está guardado en este iPhone."
        case "ebook-network": "No se pudo descargar el libro. Vuelve a intentarlo."
        case "manga-store": "No se pudo guardar tu biblioteca de Manga. Los datos anteriores se conservan."
        case "manga-size": "Este manga supera el tamaño admitido por el lector."
        case "manga-format": "No se pudieron leer las imágenes del archivo. Usa un CBZ o ZIP con imágenes."
        case "manga-server-url": "Introduce la URL http o https de tu servidor. Usa los campos de usuario y contraseña para el acceso."
        case "manga-image-origin": "La dirección de esta página no es compatible."
        case "manga-connection": "Conecta el servidor Suwayomi de este manga para abrirlo."
        case "manga-network": "No se pudo conectar con Suwayomi. Comprueba el servidor y la red."
        case "manga-authorization": "Suwayomi ha rechazado el acceso. Comprueba el usuario y la contraseña."
        case "manga-protocol": "Suwayomi no devolvió los datos esperados. Comprueba la versión y sus extensiones."
        case "manga-pages": "Suwayomi no pudo obtener las páginas de este capítulo. Prueba de nuevo desde su fuente."
        case "sports-catalog": "No se pudo cargar la lista de ligas de Sports."
        case "sports-store": "No se pudo guardar la configuración de Sports. Los favoritos anteriores se conservan."
        case "sports-response": "El servicio deportivo no devolvió los datos esperados. Vuelve a intentarlo."
        case "sports-standings": "No hay una clasificación disponible para esta liga."
        case "iptv-store": "No se pudo guardar Live TV. Las listas y los favoritos anteriores se conservan."
        case "iptv-format", "iptv-empty": "El archivo no contiene una lista M3U con canales compatibles."
        case "iptv-size": "La lista supera el tamaño o número de canales admitidos."
        case "iptv-url": "Introduce una URL http o https válida para la lista."
        case "iptv-network": "No se pudo actualizar la lista. Comprueba la URL y tu conexión."
        case "iptv-drm": "Este canal requiere un sistema de protección que el reproductor de iPhone todavía no admite."
        case "xtream-url": "Introduce la dirección http o https de tu servidor Xtream."
        case "xtream-credentials": "Introduce el usuario y la contraseña de tu servidor Xtream."
        case "xtream-authorization": "El servidor ha rechazado el acceso. Comprueba tus datos y el estado de la cuenta con tu proveedor."
        case "xtream-response": "El servidor no ha devuelto un catálogo o una programación compatible."
        case "xtream-network": "No se pudo conectar al servidor Xtream. Comprueba la dirección y tu conexión."
        case "sports-reminder-past": "La hora del recordatorio ya ha pasado. Elige un aviso más cercano al inicio."
        case "sports-reminder-save": "No se pudo crear el recordatorio. Vuelve a intentarlo."
        case "sports-reminder-permission": "Permite las notificaciones de Harbor en los ajustes de iOS para recibir el recordatorio."
        case "invalid-metadata-response": "El proveedor de metadata no devolvió los datos esperados."
        case "resume-read-failed", "invalid-resume-store", "unsupported-resume-version": "No se pudo leer el progreso guardado. Los datos se han conservado."
        case "resume-write-failed", "resume-store-too-large": "No se pudo guardar el progreso. Los datos anteriores se han conservado."
        case "resume-store-unavailable": "El almacenamiento del progreso no está disponible."
        default: code.hasPrefix("http-") ? "El servicio no está disponible ahora. Inténtalo de nuevo más tarde." : "No se pudo completar la operación. Puedes volver a intentarlo."
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
