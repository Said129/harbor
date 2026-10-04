# Harbor para iPhone: desarrollo

Port nativo SwiftUI, exclusivamente iPhone (device family 1), con iOS 17 como mínimo inicial. Este es el comienzo del primer recorrido funcional, no una release con paridad Desktop. El fork de trabajo es Said129/harbor; el CI ya ejecuta etapas Apple. El estado observado de compilación, tests y reproducción se registra en la [evidencia](../docs/ios/VALIDATION.md) y la [matriz de 706 entradas](../docs/ios/FEATURE_PARITY.md).

La app consulta manifests, catálogos, búsqueda, metadata y streams reales. Instala Cinemeta sólo cuando no existe un registro de addons en Keychain; los catálogos se descubren del manifest. Una lista intencionalmente vacía permanece vacía. Se pueden instalar URLs configuradas de addons, habilitar/deshabilitar, reordenar y desinstalar. El parsing, trust y ranking ejecutan el código original de harbor-core mediante una ABI C versionada. Libmpv integrado usa MPVKit fijado a una revisión concreta; no hay WebView ni proceso mpv externo.

Sólo se resuelven fuentes HTTP(S) directas en este momento. Hay una primera implementación de progreso local y reanudación descrita abajo. Los clientes nativos de los cinco proveedores Debrid, el P2P local, cuentas, biblioteca, sincronización del progreso y las demás entradas de la matriz siguen pendientes. Una URL directa de un addon configurado con Debrid no equivale a implementar Debrid completo. Las ofertas con otras vías no se ocultan; muestran errores explícitos al seleccionarlas.

## Desde Windows

Instalar Git, Node/pnpm, Rust estable y MSVC Build Tools. Para reproducir los checks portables, desde la raíz:

```powershell
cargo test --manifest-path harbor-core/Cargo.toml --locked
cargo test --manifest-path harbor-core/Cargo.toml --locked --no-default-features
cargo test --manifest-path harbor-ios-bridge/Cargo.toml --locked
cargo clippy --manifest-path harbor-ios-bridge/Cargo.toml --locked --all-targets -- -D warnings
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios wasm32-unknown-unknown
cargo check --manifest-path harbor-ios-bridge/Cargo.toml --locked --target aarch64-apple-ios
cargo check --manifest-path harbor-core/Cargo.toml --locked --target wasm32-unknown-unknown
```

El cargo check Apple desde Windows sólo verifica Rust; no prueba el linker/SDK Apple ni SwiftUI. La feature WASM sigue habilitada por defecto para Desktop/Web; el bridge la deshabilita explícitamente.

Prueba opt-in con servicios reales, separada de unit tests:

```powershell
cargo build --manifest-path harbor-ios-bridge/Cargo.toml --locked
python scripts/ios/integration-live.py
```

Usa Cinemeta y el [addon de ejemplo oficial Stremio](https://github.com/Stremio/stremio-static-addon-example), instalado únicamente dentro de la prueba. Lee catálogos/metadata/streams remotos y resuelve la URL pasando por Rust. El vídeo antiguo de ese addon devolvió HTTP 403 en la prueba de transporte de esta máquina; no se reemplaza por una URL inventada ni se certifica playback. Para exigir además una respuesta HTTP 206 con un rango de 1024 bytes, ejecutar con `--probe-media`. Se puede indicar un addon con streams directos accesibles mediante la variable de entorno `HARBOR_IOS_TEST_ADDON`; evitar secretos en el historial del shell. Nunca se imprimen payloads ni URLs de reproducción y no se guarda un archivo de vídeo.

Los logs exportables se comparten desde Ajustes dentro de la app. Incluyen fecha/evento/count y códigos de fallo permitidos o números HTTP/mpv/Keychain validados; excluyen manifests, tokens, URLs y logs crudos de mpv.

## Progreso local y reanudación

La implementación nativa guarda claves de película/episodio, posición y timestamp en un documento versionado de Application Support, sin URLs de streams ni secretos. Usa un actor, escrituras atómicas y protección de archivos tras el primer desbloqueo. Un fallo de lectura no sobrescribe datos anteriores; las incidencias se muestran y registran mediante códigos seguros.

El core comparte las reglas portadas de Desktop: autosave cada 4 s con posición mínima de 5 s, exclusión de stubs cortos, posiciones independientes por episodio y specials, reanudación automática activada por defecto y aviso opcional desactivado. Ajustes permite cambiar ambas opciones. Guarda también snapshots al pausar/terminar/salir y cambiar lifecycle; el cierre forzado puede perder el último intervalo.

Validar el contrato desde Windows, después de construir el bridge:

```powershell
python scripts/ios/test-resume-contract.py
```

Compara el módulo TypeScript Desktop real con la DLL/C ABI, sin red. Los tres tests Swift de persistencia/reinicio/corrupción pasan en Apple CI, junto con cinco tests del bridge y diagnostics. El comportamiento mpv de resume todavía requiere reproducción en iPhone. Continue Watching, historial completo y sincronización de cuentas siguen pendientes. Los resultados y commits comprobados están en VALIDATION.

## CI Apple sin Mac local

El workflow [iPhone Native](../.github/workflows/ios.yml) utiliza los runners estándar `ubuntu-24.04`, `windows-latest` y `macos-15`. Sólo ejecuta jobs en repositorios públicos. GitHub documenta [runners estándar gratuitos en repositorios públicos](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). No utiliza runners large/xlarge ni cambia planes, pagos, presupuestos o límites de caché.

El propietario ha solicitado no gastar dinero. Por ello los uploads de artefactos están deshabilitados por defecto; los logs de pasos permanecen en Actions. El almacenamiento de artefactos tiene una [cuota independiente](https://docs.github.com/en/billing/concepts/product-billing/github-actions), compartida con otros usos de la cuenta. Sólo activar `upload_artifacts` en una ejecución manual después de comprobar almacenamiento gratuito disponible y bloqueo de uso facturable; se conservan un día. No habilitarlo para resolver un error de facturación.

```powershell
git push origin ios/native-iphone
gh run list --repo Said129/harbor --workflow ios.yml
gh run view RUN_ID --repo Said129/harbor --log-failed
gh workflow run ios.yml --repo Said129/harbor --ref ios/native-iphone -f run_live_integration=true
```

El PR abierto ejecuta el workflow al actualizar la rama. Los pushes directos sólo lo ejecutan en `main`, evitando duplicar cada build del PR. Sin un PR abierto, lanzar manualmente con `gh workflow run ios.yml --repo Said129/harbor --ref ios/native-iphone`.

Stages: tests Windows/Linux → cargo Apple sin WASM → framework dinámico device arm64 y simulator arm64/x86_64 → validación de exports/install name → XCFramework → XcodeGen → dependencias SPM fijadas → build Swift/simulator → tests de ABI/modelos en iPhone simulator → integración real opt-in → build device unsigned → empaquetado/verificación de IPA unsigned. El runtime Rust del bridge queda dentro de su framework para evitar la colisión con Libdovi; ver ADR 0002. El primer gate Apple ocurre antes de compilar Swift. Si se autoriza el upload dentro de la cuota, produce logs, xcresult, XCFramework, apps simulator/device e IPA unsigned.

`HarborLive` es un scheme separado que activa explícitamente dos tests de servicios reales y un test de navegación XCTest UI. Usa URLSession, Codable, el framework Rust embebido, Keychain y la interfaz normal: no hay launch mode especial, estado inyectado ni respuestas falsas. Cinemeta y el addon de ejemplo oficial sólo son inputs de la prueba. El test UI conserva capturas en `LiveTests.xcresult` y comprueba apertura/cierre del player; no certifica imagen/audio ni disponibilidad del servidor de vídeo. Los ocho tests normales siguen sin depender de red. PR y dispatch de la misma rama comparten concurrency para evitar builds duplicados.

`scripts/ios/package-ipa.py` exige un build iPhoneOS/arm64, device family 1 y HarborCore embebido. Conserva permisos/symlinks, verifica la integridad de `Payload/Harbor.app` y genera un informe con commit, tamaño y SHA-256. No firma ni instala. Por defecto la IPA sólo existe temporalmente en el runner y no se sube a GitHub.

Para conservar únicamente la IPA y su informe, una ejecución manual puede activar además `save_draft_build=true`. Requiere el gate de integración real, verifica de nuevo hash/commit y crea un borrador de Release dirigido a ese commit. No publica una release final ni habilita uploads de Actions. Los [assets de Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) tienen límites distintos: cada archivo debe ser menor de 2 GiB, sin límite total de storage/bandwidth. El job Apple dispone de permiso contents write para ese paso; sólo se ejecuta por dispatch explícito, nunca al actualizar un PR.

Para ejecutar las mismas etapas en un Mac disponible en el futuro: `bash scripts/ios/build-rust.sh`, `xcodegen generate --spec ios/project.yml` y los comandos xcodebuild del workflow. `project.yml` es la fuente; el proyecto Xcode, Info.plist y frameworks son generados.

## Gate de iPhone físico

No existe aún una IPA firmada. El build unsigned comprueba código/enlace, pero no permite instalar normalmente en iPhone. Configurar signing/distribución por separado, sin guardar certificados o provisioning en Git. No contratar servicios ni membresías automáticamente.

La [guía de prueba desde Windows](SIDELOAD.md) describe la comprobación del hash y una vía de firma local con cuenta Apple gratuita. Esa instalación aún debe verificarse con la IPA y el dispositivo concretos.

Después del gate de CI, instalar una build válidamente firmada, añadir un addon real con una fuente disponible y comprobar Home → búsqueda → ficha → selector → reproducción. Registrar dispositivo/iOS/fuente, avance de time-pos, imagen/audio, seeking, subs/tracks, headers/ranges, rotación, cierres repetidos, memoria/temperatura y red interrumpida. No marcar el milestone completo hasta observar vídeo real en iPhone.

OpenGL ES es la superficie inicial para comprobar libmpv. El demo de MPVKit advierte de problemas con vídeo de 10 bits; Metal es una alternativa todavía experimental. HDR/DV/AV1/PiP/AirPlay y formatos de subtítulos necesitan pruebas específicas, no se deducen de la lista de dependencias.

## Mantener la paridad y upstream

Actualizar `docs/ios/parity-status.json` con estado, implementación y evidencia. Después:

```powershell
python scripts/ios/update-inventory.py
python scripts/ios/update-parity.py
```

La regeneración conserva el progreso del JSON y rechaza claves desconocidas. `features.json` registra grupos de funcionalidades reales y la matriz incluye además cada campo de Settings. Las entradas pendientes permanecen en alcance.

El repositorio conserva `upstream` para Harbor oficial y `origin` para el fork. Mantener los módulos iOS aislados y comparar cambios compartidos con tests antes de integrar `upstream/main`.
