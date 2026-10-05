# Harbor para iPhone: desarrollo

Port nativo SwiftUI, exclusivamente iPhone (device family 1), con iOS 17 como mínimo inicial. Este es el comienzo del primer recorrido funcional, no una release con paridad Desktop. El fork de trabajo es Said129/harbor; el CI ya ejecuta etapas Apple. El estado observado de compilación, tests y reproducción se registra en la [evidencia](../docs/ios/VALIDATION.md) y la [matriz de 706 entradas](../docs/ios/FEATURE_PARITY.md).

La app consulta manifests, catálogos, búsqueda, metadata y streams reales. Instala Cinemeta sólo cuando no existe un registro de addons en Keychain; los catálogos se descubren del manifest. Una lista intencionalmente vacía permanece vacía. Se pueden instalar URLs configuradas de addons, habilitar/deshabilitar, reordenar y desinstalar. El parsing, trust y ranking ejecutan el código original de harbor-core mediante una ABI C versionada. Libmpv integrado usa MPVKit fijado a una revisión concreta; no hay WebView ni proceso mpv externo.

Home y Ajustes permiten iniciar sesión con la misma cuenta Stremio usada en Harbor Desktop. Hay formulario nativo de correo/contraseña y acceso oficial mediante ASWebAuthenticationSession. Antes de completar el acceso se descarga la colección real de addons: conserva URLs configuradas, orden y flags, y guarda sesión/colección juntas en Keychain. Home se carga con esos addons. Al volver a abrir la app se sincronizan; un fallo conserva la copia anterior. Instalar, eliminar o reordenar conectado actualiza la colección de Stremio; activar/desactivar sigue siendo local. Cerrar sesión elimina la sesión de este iPhone y recupera la lista de invitado, sin revocar otros dispositivos. El propietario confirma que el login corregido funciona en iPhone 14; callback, reinicio y ediciones completas de cuenta siguen pendientes de comprobación física. No se incluyen credenciales en CI.

Sólo se resuelven fuentes HTTP(S) directas en este momento. Hay una primera implementación de progreso local y reanudación descrita abajo. Los clientes nativos de los cinco proveedores Debrid, el P2P local, biblioteca, sincronización del progreso y las demás entradas de la matriz siguen pendientes. Una URL directa de un addon configurado con Debrid no equivale a implementar Debrid completo. Las ofertas con otras vías no se ocultan; muestran errores explícitos al seleccionarlas. Los addons guardados únicamente de forma local en otro dispositivo no aparecen en la colección de la cuenta.

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

Compara el módulo TypeScript Desktop real con la DLL/C ABI, sin red. Los tres tests Swift de persistencia/reinicio/corrupción pasan en Apple CI, junto con cinco tests del bridge y diagnostics, un test real de Keychain, uno de inicialización de libmpv y dos de conservación y compatibilidad de la colección de addons. El comportamiento mpv de resume todavía requiere reproducción en iPhone. Continue Watching, historial completo y sincronización de cuentas siguen pendientes. Los resultados y commits comprobados están en VALIDATION.

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

`HarborLive` es un scheme separado que activa explícitamente dos tests de servicios reales y un test de navegación XCTest UI. Usa URLSession, Codable, el framework Rust embebido, Keychain y la interfaz normal: no hay launch mode especial, estado inyectado ni respuestas falsas. Cinemeta y el addon de ejemplo oficial sólo son inputs de la prueba. El test UI conserva capturas en `LiveTests.xcresult` y comprueba límites del viewport, la consulta completa de búsqueda e inicialización real de mpv/render antes de cerrar el player; no certifica imagen/audio ni disponibilidad del servidor de vídeo. Los trece tests normales siguen sin depender de red. Uno de ellos usa el controlador libmpv/GLKView real con dos vídeos de prueba de 8/10 bits y verifica píxeles distintos y avance del tiempo; esas imágenes también se conservan con la evidencia. Los builds simulator usan firma ad hoc local (`CODE_SIGN_IDENTITY=-`) para comprobar Keychain, sin cuenta Apple ni certificado; el build device sigue sin firmar. PR y dispatch de la misma rama comparten concurrency para evitar builds duplicados.

`scripts/ios/package-ipa.py` exige un build iPhoneOS/arm64, device family 1 y HarborCore embebido. Conserva permisos/symlinks, verifica la integridad de `Payload/Harbor.app` y genera un informe con commit, tamaño y SHA-256. No firma ni instala. Por defecto la IPA sólo existe temporalmente en el runner y no se sube a GitHub.

Para conservar la IPA, su informe y las capturas de integración, una ejecución manual puede activar además `save_draft_build=true`. Requiere el gate de integración real, verifica de nuevo hash/commit y crea un borrador de Release dirigido a ese commit. No publica una release final ni habilita uploads de Actions. Los [assets de Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) tienen límites distintos: cada archivo debe ser menor de 2 GiB, sin límite total de storage/bandwidth. El job Apple dispone de permiso contents write para ese paso; sólo se ejecuta por dispatch explícito, nunca al actualizar un PR.

Para ejecutar las mismas etapas en un Mac disponible en el futuro: `bash scripts/ios/build-rust.sh`, `xcodegen generate --spec ios/project.yml` y los comandos xcodebuild del workflow. `project.yml` es la fuente; el proyecto Xcode, Info.plist y frameworks son generados.

## Gate de iPhone físico

El propietario confirma instalación, apertura y login corregido en su iPhone 14. Al reproducir varias fuentes observa audio con una pantalla azul uniforme; el nuevo default usa VideoToolbox copy-back para evitar el mapper directo CoreVideo/GLES. Los builds de CI siguen sin firmar: comprobar código/enlace no permite instalarlos directamente. Firmar cada actualización localmente sin guardar certificados o provisioning en Git. El acceso está confirmado; la corrección de imagen y los controles de reproducción aún requieren comprobación física.

La [guía de prueba desde Windows](SIDELOAD.md) describe la comprobación del hash y la firma local con cuenta Apple gratuita. Para actualizar la app se conserva la misma identidad de firma y bundle; no se necesita borrar los datos para aplicar la actualización de vídeo. Ajustes → Reproducción y el menú de vídeo del player permiten elegir Automática, Activada o Software; conservan la opción Desktop `mpvHwdec`.

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
