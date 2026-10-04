# Evidencia de validación

Fecha: 2026-10-04. Base Desktop: `0117755855d3f43960bad3f9f62b69ef851d5991` (Harbor 0.9.21). Entorno local: Windows 11 x86_64, Rust estable 1.99.0, MSVC Build Tools/Windows SDK. Fork público: [Said197812/harbor](https://github.com/Said197812/harbor/tree/ios/native-iphone).

No hay validación de SwiftUI, linker Apple, simulator o reproducción física todavía. El código del primer recorrido existe; el milestone funcional en iPhone NO está completado. En la matriz, 75 entradas tienen implementación parcial y 15 investigación; 616 permanecen Not Started. No se declara Working/Parity por compilar Rust en Windows.

## Checks locales observados

| Check                                                           | Resultado                                                                 | Límite de la evidencia                                                                                                                                                                 |
| --------------------------------------------------------------- | ------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Core upstream antes del cambio                                  | 56 tests pasan                                                            | Baseline original del motor                                                                                                                                                            |
| Core después, features default                                  | 56 originales + 6 contratos addon pasan                                   | Misma lógica parser/trust/scoring; wrappers WASM conservados                                                                                                                           |
| Core después, `--no-default-features`                           | Los mismos 62 tests pasan                                                 | Uso nativo sin wrappers JS                                                                                                                                                             |
| `cargo test` bridge                                             | 5 tests pasan                                                             | Ownership/size/null, errores sin secretos, headers/subs, controles en URL antes de CString, resolver pendiente explícito                                                               |
| Clippy core default y bridge all-targets, `-D warnings`         | Pasan                                                                     | No warnings nuevos en código compartido                                                                                                                                                |
| `cargo check` core nativo y bridge, `aarch64-apple-ios`         | Pasan desde Windows                                                       | Metadata Rust; no linker, SDK Apple o Swift                                                                                                                                            |
| `cargo check` core, `wasm32-unknown-unknown`                    | Pasa                                                                      | API WASM anterior continúa compilando; empaquetado wasm-pack no ejecutado localmente                                                                                                   |
| Bridge host build + ctypes ABI + servicios reales               | Pasa                                                                      | Cinemeta: 4 catálogos elegibles, 50 items en catálogo observado, 20 resultados de búsqueda; metadata real. Addon oficial estático: 1 stream mapeado/rankeado/resuelto con trust normal |
| Transporte de vídeo del addon oficial antiguo                   | HTTP 403 desde esta máquina                                               | No garantiza disponibilidad general; tampoco prueba playback. No sustituir su URL por un mock                                                                                          |
| Desktop `cargo check --manifest-path src-tauri/Cargo.toml`      | Pasa con recursos de packaging desactivados sólo por `TAURI_CONFIG` local | Verifica backend/código compartido; no empaquetado final                                                                                                                               |
| Desktop `cargo test --manifest-path src-tauri/Cargo.toml --lib` | 49 tests pasan con mismo override local                                   | Backend Desktop y librqbit/streaming existentes                                                                                                                                        |
| Desktop `pnpm run typecheck`                                    | Pasa                                                                      | No se modificó TypeScript existente                                                                                                                                                    |
| Frontend build del comando Tauri                                | tsc y Vite completan                                                      | La fase posterior de bundling no completó                                                                                                                                              |

Las pruebas de red no se ejecutan como unit tests ni automáticamente en CI. Reproducir con `cargo build --manifest-path harbor-ios-bridge/Cargo.toml --locked` y `python scripts/ios/integration-live.py`; `--probe-media` añade el gate real de HTTP 206. Los counts son observaciones de un momento, no catálogos incorporados a la app.

## Baselines y checks incompletos

- `pnpm test` en el baseline: 101 pasan, 1 falla en `tests/startup-loader.test.ts:41` (“main page-load handler must exist”), archivo no modificado. No se repara aquí un test ajeno al port.
- `pnpm run check` global detecta formato en 1661 archivos no modificados por esta fase; este checkout Windows tiene CRLF en gran parte del baseline. No se aplica `--fix` global. Los archivos nuevos soportados se formatean de manera acotada. Swift/Python/Rust no tienen lint a través de vp; Rust usa clippy/rustfmt.
- Check acotado final: `pnpm run check --no-error-on-unmatched-pattern docs/ios ios/README.md .github/workflows/ios.yml ios/project.yml harbor-core/Cargo.toml harbor-ios-bridge/Cargo.toml` pasa en los 16 archivos soportados. El flag permite cero entradas JS/TS para el linter: ningún JS/TS cambió. Una prueba con un script JS upstream de referencia confirmó también su baseline de formato; no se reformateó ese script ajeno.
- Desktop conserva tres warnings anteriores en módulos Windows: import CommandExt no usado y funciones VapourSynth no usadas. Los lib tests añaden imports anteriores no usados. No son warnings introducidos en harbor-core/bridge.
- `pnpm tauri:build:linux-system` se ejecutó desde Windows con Cargo en PATH: frontend compiló; Tauri eligió `x86_64-pc-windows-msvc` y falló por el recurso Desktop ausente `binaries/mpv-x86_64-pc-windows-msvc.exe`. Un comando/config Linux no convierte un host Windows en un builder Linux. Falta validar el binario Linux en un host Linux y el packaging Desktop completo con sus sidecars/fonts originales; no se eliminaron recursos del proyecto para hacerlo pasar.

## CI real y bloqueo externo

Primer run: [iPhone Native / 37207098484](https://github.com/Said197812/harbor/actions/runs/37207098484), commit `8badcf6a`. Ambos jobs shared terminaron antes de iniciar pasos; Apple quedó skipped. La anotación del check run de GitHub indica:

> The job was not started because your account is locked due to a billing issue.

No fue un error de Rust, Swift o linker: esas etapas no llegaron a ejecutarse. No se ha contratado ningún servicio ni cambiado planes/facturación. El propietario solicita coste cero. El workflow usa únicamente runners estándar públicos y deshabilita uploads por defecto; el bloqueo de la cuenta debe resolverse sin habilitar gasto. [GitHub documenta runners estándar gratis](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) y [opciones para cuentas bloqueadas, incluido GitHub Free](https://docs.github.com/en/billing/how-tos/troubleshooting/locked-account).

Reejecutar desde la rama actual cuando GitHub permita Actions. Registrar aquí URL/commit, Xcode/SDK, errores y correcciones, tests y productos reales. No sustituir la validación de CI por checks sintácticos o stubs de frameworks Apple.

## Gates pendientes antes de declarar el milestone

1. Core/bridge staticlib y XCFramework enlazan con iOS SDK device/simulator en macOS.
2. XcodeGen/SPM, Swift/libmpv, tests de ABI y modelos pasan; app arranca en iPhone simulator y obtiene datos reales.
3. Signing válido e instalación física por una vía acordada sin gastos automáticos.
4. Stream accesible de un addon real avanza time-pos y reproduce imagen/audio en iPhone. Seeking/ranges, controls/tracks/subs/rotación, teardown y errores se verifican en el dispositivo.
5. Repetir con matrices de formatos/codec, condiciones de red y lifecycle antes de declarar compatibilidad. El render OpenGL inicial tiene un riesgo documentado de vídeo 10 bits en MPVKit; evaluar Metal/VideoToolbox y conservar el objetivo HDR.

Después: shared Debrid completo (cinco proveedores), extracción librqbit/Axum, progreso/resume/biblioteca/sync/cuentas y cada entrada restante de FEATURE_PARITY. La investigación y el código parcial no significan retirada de funciones.
