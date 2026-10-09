# 0002 — ABI C pequeña y core nativo

## Context

Core es principalmente pure functions con wrappers WASM obligatorios en el manifest. Necesitamos probar enlace Apple antes de ampliar la aplicación.

## Options

UniFFI; C ABI por cada función; C ABI versionada con mensajes tipados serde/Codable; JavaScriptCore reutilizando TypeScript. UniFFI aporta generación/types/async, pero añade build tooling y runtime que no requiere el primer pipeline puro. JavaScriptCore requeriría adaptar fetch/AbortController/storage y no sustituye el Rust existente.

## Decision

Separar wrappers WASM con feature default; native consumer usa default-features=false. Crate `harbor-ios-bridge` con versión ABI, llamada UTF-8+length y destructor de respuesta. Request enum por operación, respuesta data/error con códigos estables y límite de tamaño. Rust construye rutas addon y corre parser/trust/scoring originales; Swift aporta URLSession y sistema. En iOS, el bridge se empaqueta como framework dinámico dentro de un XCFramework device y simulator. La DLL host y los demás crate types siguen disponibles.

## Advantages

No referencias Rust ni runtime async cruzan ABI, ownership explícito, portable en Windows, pocos símbolos, contratos testables. Conserva exportaciones WASM/upstream. Protocolo addon puro reutilizable sin networking/Swift.

## Disadvantages

JSON implica serialización y traducción de tipos; no sirve para frames/audio. Caller C debe respetar pointers válidos y ownership. Se debe mantener versión y tests de contratos. El framework dinámico se embebe en la app y también requiere firmado válido al distribuir.

## Consequences

Encapsular en `CoreBridge.swift`; ningún View usa C. Buffers se liberan siempre. Core calls de ranking fuera de UI actor. No convertir errores/panics en resultados vacíos. Si servicios Rust crecen con async/cancelación, evaluar UniFFI con ADR adicional. La pequeña implementación addon Rust porta contratos hoy TypeScript porque esos servicios NO existen en core; no duplicar ranking ni Debrid en Swift.

## Extracción de Música local (2026-10-06)

`harbor-core::music` conserva el modelo MusicTrack, FNV de track/album/artista, crédito albumArtist, limpieza de tags, fallback de filename y duration_label del checkpoint beta `19ddc311`. `musicLocalTrack` sólo recibe metadata acotada de audio propio y un nombre SHA256 relativo; devuelve tipos serializados y códigos seguros. Se mantienen ABI 1, límite de 8 MiB y los tres exports; no pasan archivos de audio, covers, callbacks, handles mpv ni objetos Rust por JSON. No se modifica el Music/Tauri Desktop histórico. La procedencia se registra en native-music-provenance.json.

Swift posee el selector de Archivos, almacenamiento privado/protegido, lectura incremental SHA256, inspección/reproducción con libmpv y los controles MediaPlayer. La extracción opcional de cover usa AVFoundation/ImageIO y devuelve sólo Data acotada entre tareas; no se añade Sendable sin comprobar a objetos Apple. Esas adaptaciones necesitan compilación y comportamiento Apple. Los proveedores de música conectados y el resto del deck Desktop siguen pendientes; esta extracción local no certifica su paridad.

## Revisión tras enlace Apple (2026-10-04)

El experimento inicial usó una staticlib. El CI `37213976287` pasó build simulator/device y 8 tests, pero el linker señaló `_rust_eh_personality` duplicado entre HarborCore y Libdovi de MPVKit: ambos contienen std de toolchains Rust distintos. La [referencia Rust](https://doc.rust-lang.org/reference/linkage.html) documenta conflictos al enlazar varios subsistemas Rust estáticos y el uso de cdylib para otros lenguajes. Elegimos una cdylib con runtime privado y ABI C idéntica; no hay llamadas Rust entre HarborCore y Libdovi ni unwinding a través de C. Se mantienen catch_unwind y el destructor dentro del mismo runtime. El empaquetado valida los tres exports de ABI 1 por arquitectura y el install name `@rpath/HarborCore.framework/HarborCore`. Device es arm64; simulator universal arm64/x86_64. No se eliminan Libdovi, Dolby Vision ni el manejo de panics para resolver la colisión.
