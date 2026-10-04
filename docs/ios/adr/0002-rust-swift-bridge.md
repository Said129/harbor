# 0002 — ABI C pequeña y core nativo

## Context

Core es principalmente pure functions con wrappers WASM obligatorios en el manifest. Necesitamos probar enlace Apple antes de ampliar la aplicación.

## Options

UniFFI; C ABI por cada función; C ABI versionada con mensajes tipados serde/Codable; JavaScriptCore reutilizando TypeScript. UniFFI aporta generación/types/async, pero añade build tooling y runtime que no requiere el primer pipeline puro. JavaScriptCore requeriría adaptar fetch/AbortController/storage y no sustituye el Rust existente.

## Decision

Separar wrappers WASM con feature default; native consumer usa default-features=false. Crate `harbor-ios-bridge` con versión ABI, llamada UTF-8+length y destructor de respuesta. Request enum por operación, respuesta data/error con códigos estables y límite de tamaño. Rust construye rutas addon y corre parser/trust/scoring originales; Swift aporta URLSession y sistema. El bridge es estático, se empaqueta XCFramework device y simulator.

## Advantages

No referencias Rust ni runtime async cruzan ABI, ownership explícito, portable en Windows, pocos símbolos, contratos testables. Conserva exportaciones WASM/upstream. Protocolo addon puro reutilizable sin networking/Swift.

## Disadvantages

JSON implica serialización y traducción de tipos; no sirve para frames/audio. Caller C debe respetar pointers válidos y ownership. Se debe mantener versión y tests de contratos.

## Consequences

Encapsular en `CoreBridge.swift`; ningún View usa C. Buffers se liberan siempre. Core calls de ranking fuera de UI actor. No convertir errores/panics en resultados vacíos. Si servicios Rust crecen con async/cancelación, evaluar UniFFI con ADR adicional. La pequeña implementación addon Rust porta contratos hoy TypeScript porque esos servicios NO existen en core; no duplicar ranking ni Debrid en Swift.
