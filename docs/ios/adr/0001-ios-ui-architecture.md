# 0001 — Interfaz nativa iPhone

## Context

Harbor Desktop separa React/TypeScript y backend Tauri. La petición exige iPhone nativo y paridad, excluyendo WebView y otros targets nuevos.

## Options

SwiftUI/UIKit; Tauri mobile/WebView; frontend React con otra shell; UI completa en Rust.

## Decision

SwiftUI, servicios y ViewModels separados, UIKit para render multimedia y APIs del OS. iPhone family 1; iOS 17 inicial. No portar Tauri entero. Mantener servicios/protocolo compartidos en Rust y registrar la lógica TypeScript pendiente de extracción.

## Advantages

Navegación, accesibilidad, gestos, sheets y safe areas nativos. Desktop permanece intacto. Views pequeñas y comprobables por CI.

## Disadvantages

No reutiliza los componentes React; servicios TypeScript no son automáticamente Rust. SwiftUI requiere Xcode/SDK para validación.

## Consequences

CI macOS desde el primer experimento. Home/search/detail/stream picker/addons primero, otras salas por pantallas secundarias conforme avanza la matriz. Adaptar interacción no autoriza a quitar funciones.
