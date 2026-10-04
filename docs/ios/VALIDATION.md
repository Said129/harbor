# Evidencia de validación

Fecha: 2026-10-04. Base Desktop: `0117755855d3f43960bad3f9f62b69ef851d5991` (Harbor 0.9.21). Entorno local: Windows 11 x86_64, Rust estable 1.99.0, MSVC Build Tools/Windows SDK. Fork público de trabajo: [Said129/harbor](https://github.com/Said129/harbor/tree/ios/native-iphone). El fork anterior permanece como respaldo.

El [CI de Said129 / 37215557481](https://github.com/Said129/harbor/actions/runs/37215557481), commit `6e5c8f821a03ae3f519845a7e3f137e8aa266170`, pasó los tres jobs: shared Windows/Linux y Apple. Valida build/enlace SwiftUI/libmpv para simulator y device unsigned, framework dinámico Rust con ABI aislada y 8 tests Swift en iPhone simulator. La reproducción física todavía no está validada y el milestone funcional en iPhone NO está completado. En la matriz, 78 entradas tienen implementación parcial y 15 investigación; 613 permanecen Not Started. No se declara Working/Parity por compilar.

## Checks locales observados

| Check                                                           | Resultado                                                                 | Límite de la evidencia                                                                                                                                                                 |
| --------------------------------------------------------------- | ------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Core upstream antes del cambio                                  | 56 tests pasan                                                            | Baseline original del motor                                                                                                                                                            |
| Core después, features default                                  | 56 originales + 6 contratos addon + 8 resume pasan                        | Misma lógica parser/trust/scoring; wrappers WASM conservados                                                                                                                           |
| Core después, `--no-default-features`                           | Los mismos 70 tests pasan                                                 | Uso nativo sin wrappers JS                                                                                                                                                             |
| `cargo test` bridge                                             | 6 tests pasan                                                             | Ownership/size/null, errores sin secretos, headers/subs, controles en URL antes de CString, resolver pendiente explícito                                                               |
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

Tras el traslado autorizado a Said129, [run 37212328098](https://github.com/Said129/harbor/actions/runs/37212328098), commit `4ae5f38d`, ejecutó los tests shared en Windows/Linux con éxito. En macOS pasó Rust Apple, creación del XCFramework, XcodeGen y resolución SPM; el build simulator falló en `MPVController.swift:95` al pasar `UnsafePointer.init` como función a `Optional.map`. `7300cded` usa una closure con conversión explícita de `UnsafeMutablePointer<CChar>` a `UnsafePointer<CChar>`. No cambia la propiedad ni la vida útil de las cadenas C.

El [run 37213208031](https://github.com/Said129/harbor/actions/runs/37213208031) confirmó que esa conversión compila. Detectó un segundo error en `AddonsView`: el `error` del catch ocultaba el estado de la vista al borrar/reordenar. `67083301` usa `self.error`, igual que los demás handlers. Xcode también señaló que el build genérico de simulator requiere x86_64 además de arm64; `8bc1c933` construye ambas staticlibs, crea una biblioteca universal con lipo y verifica sus arquitecturas antes del XCFramework. No se excluyen arquitecturas para eludir el enlace. El mismo commit evita duplicar push/PR: push sólo en main; PR y dispatch continúan disponibles.

El [run 37213676838](https://github.com/Said129/harbor/actions/runs/37213676838) compiló las tres staticlibs; falló en el orden de argumentos de `lipo -verify_arch`. `b0c39def` coloca primero el archivo de entrada según el uso de la herramienta. El [run 37213976287](https://github.com/Said129/harbor/actions/runs/37213976287) de esa corrección terminó success en los tres jobs: shared Windows/Linux, Apple packaging universal, build/enlace Swift simulator, 8 tests sin fallos (5 bridge/diagnostics y 3 persistencia) en iPhone 16 Pro/iOS 18.5, y build Release device sin firmado. Los productos se construyeron en el runner; no se subieron artifacts porque el input está desactivado.

La revisión de sus logs encontró `_rust_eh_personality` duplicado entre std de HarborCore y Libdovi, y una advertencia de orientaciones sin requisito de pantalla completa. `6e5c8f82` aísla el runtime del bridge en una cdylib con sólo tres exports C verificados por arquitectura y declara pantalla completa para esta app sólo iPhone. El ABI, catch_unwind, destructor y Libdovi se mantienen. El workflow especifica la arquitectura del host al ejecutar los tests y limita esa etapa a 15 minutos; el primer arranque de simulator tardó más de seis minutos antes de ejecutar los 8 tests en menos de un segundo.

El [run 37215557481](https://github.com/Said129/harbor/actions/runs/37215557481) de `6e5c8f82` terminó success y confirmó la corrección completa:

| Etapa Apple                             | Resultado observado                                                                     | Alcance                                                                       |
| --------------------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Rust device/simulator y empaquetado     | Pasa; exports ABI e install name verificados para arm64 device y arm64/x86_64 simulator | Framework dinámico embebido; std permanece privado                            |
| Build Debug simulator                   | BUILD SUCCEEDED                                                                         | SwiftUI, SDK Apple, libmpv y C ABI enlazan                                    |
| XCTest en iPhone 16 Pro/iOS 18.5, arm64 | 8 tests, 0 fallos, TEST SUCCEEDED                                                       | 5 bridge/diagnostics y 3 persistencia, usando la app host y su framework real |
| Build Release device                    | BUILD SUCCEEDED                                                                         | arm64 iPhone; CODE_SIGNING_ALLOWED=NO/CODE_SIGNING_REQUIRED=NO                |
| Colisión Rust y orientaciones           | Ya no aparecen en los logs                                                              | Se conserva Libdovi y el manejo de panics                                     |
| Uploads                                 | Skipped por configuración                                                               | No se publicaron productos ni se generó una IPA firmada                       |

Entorno Apple observado: runner `macos-15`, Xcode 16.4 (16F6), iOS/iOS Simulator SDK 18.5, Rust 1.99.0. El compilador confirmó warnings de deprecación de GLKit/OpenGL ES en la superficie experimental descrita en ADR 0003; no se silenciaron. La evaluación Metal y la comprobación de vídeo de 10 bits/HDR siguen pendientes. No sustituir la validación de CI por checks sintácticos o stubs de frameworks Apple.

El procesador de metadata de Xcode también avisa que omite AppIntents porque la app no depende de ese framework; no es un fallo de extracción de una integración Siri existente. No se añade una dependencia vacía para ocultar ese aviso.

## Gates pendientes antes de declarar el milestone

1. Recorrido UI completo y datos reales dentro de la app en iPhone simulator. El test host arranca, pero sus unit tests no verifican catálogos ni reproducción de red.
2. Signing válido e instalación física por una vía acordada sin gastos automáticos.
3. Stream accesible de un addon real avanza time-pos y reproduce imagen/audio en iPhone. Seeking/ranges, controls/tracks/subs/rotación, teardown y errores se verifican en el dispositivo.
4. Repetir con matrices de formatos/codec, condiciones de red y lifecycle antes de declarar compatibilidad. El render OpenGL inicial tiene un riesgo documentado de vídeo 10 bits en MPVKit; evaluar Metal/VideoToolbox y conservar el objetivo HDR.

Después: shared Debrid completo (cinco proveedores), extracción librqbit/Axum, progreso/resume/biblioteca/sync/cuentas y cada entrada restante de FEATURE_PARITY. La investigación y el código parcial no significan retirada de funciones.

## Integración nativa y empaquetado unsigned (incremento en comprobación)

Se añaden dos tests de `HarborService` con red y un recorrido XCTest UI en el scheme opt-in `HarborLive`, separado del scheme offline `Harbor`. El addon público de ejemplo se instala desde su manifest real; no se añade como default del producto. La navegación observa catálogos, búsqueda, ficha, instalación persistente, stream picker y apertura/cierre del player. Las capturas se conservan en xcresult; mostrar el player no demuestra reproducción.

El workflow permite `run_live_integration=true` y prepara una IPA unsigned mediante `package-ipa.py`. La verificación exige bundle iPhoneOS/arm64, family 1, framework Rust embebido, permisos, layout Payload e integridad ZIP; el informe incluye commit y SHA-256. Las subidas continúan desactivadas por defecto. Este incremento todavía no tiene resultado Apple registrado; no se modifica ningún estado a Working/Parity por añadir pruebas.

## Incremento de reanudacion local (2026-10-04)

- Core: 70 tests pasan con features default y sin WASM; bridge: 6 tests pasan. Clippy core/bridge all-targets `-D warnings`, target `aarch64-apple-ios` (metadata solamente) y WASM pasan.
- `python scripts/ios/test-resume-contract.py`: 28 comparaciones sin red entre `src/lib/resume.ts` real y la DLL/C ABI Rust. Verifica claves de peliculas/episodios/especiales y posiciones; no sustituye almacenamiento Foundation.
- Backend Desktop: `cargo check` y 49 lib tests pasan con el mismo override local de packaging; siguen los warnings anteriores. Ningun modulo de negocio Desktop fue reformateado o cambiado.
- Codigo Swift nuevo: actor de almacenamiento con documento v1 en Application Support, escrituras atomicas y proteccion de archivos tras el primer desbloqueo. Corrupcion/version desconocida/fallo de lectura bloquean escrituras; fallo de escritura conserva el estado anterior. No incluye URLs, credenciales ni datos de streams en el documento.
- Player: snapshots de posiciones observadas por mpv cada 4 s y al pausar/terminar/salir/cambiar lifecycle; no guardar una posicion inicial inventada si la fuente falla. Respeta autosave de Desktop (5 s, omitir stubs de menos de 150 s), reanudacion >5 s, aviso opcional >30 s, defaults resumePlayback=true/resumePrompt=false. Specials usan temporada 0. IDs custom sin coordenadas usan una clave por video para evitar colisiones entre episodios. Reinicio cerca del final segun runtime y guard de 20 s.
- Tres tests Swift nuevos cubren reinicio del store, aislamiento de episodios, checkpoints retrasados, corrupcion/version futura y fallo de escritura. Pasan dentro de los 8 tests del run Apple `37213976287`; la reproduccion y el lifecycle mpv siguen pendientes en iPhone. Guardar al suspender o cerrar es best effort; no se garantiza la ultima posicion ante terminacion forzada.
- Continue Watching, historial completo, biblioteca, perfiles y sincronizacion de cuentas no estan implementados por este incremento. No se marca Working/Parity.

## Traslado a Said129 (2026-10-04)

El propietario indica que Said129 es una cuenta ya existente y autoriza continuar alli. GitHub CLI verifico la identidad Said129 antes de crear un fork publico directo de harborstremio/harbor. Se conserva el checkout, commits y cambios nuevos; Said197812/harbor y su PR permanecen como respaldo y evidencia historica. Hay tambien un bundle local completo verificado anterior al traslado. No se modifica ni elimina la cuenta anterior, ni planes, presupuestos o metodos de pago. El nuevo fork ya ejecuto CI real con exito en Windows/Linux/macOS.

El comando de build completo se repitio tras los cambios de resume: tsc/Vite pasan; bundling Windows vuelve a fallar por el mpv.exe ausente descrito en el baseline. No es una compilacion Linux exitosa.
