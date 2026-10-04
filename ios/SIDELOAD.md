# Prueba física desde Windows sin membresía de pago

Esta guía prepara la siguiente comprobación del port. Todavía no hay una instalación física verificada de Harbor. El CI crea una IPA **sin firmar**; debe firmarse correctamente antes de instalarla. La app requiere iOS 17 o posterior y sólo declara iPhone.

## Obtener y comprobar el build

El pipeline genera `Harbor-unsigned.ipa` y `Harbor-unsigned.json` con el commit, tamaño y SHA-256. Los uploads de Actions están desactivados por defecto para respetar el coste cero. La aparición de “BUILD SUCCEEDED” no implica que haya un archivo descargable.

Una ejecución manual con `run_live_integration=true` y `save_draft_build=true` puede conservar ambos archivos en un **borrador de Release** del fork después de pasar todos los tests/builds/verificaciones. [GitHub documenta Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) con hasta 1000 assets, cada uno menor de 2 GiB, sin límite total de almacenamiento o bandwidth. Esta vía no usa almacenamiento de artifacts de Actions. El borrador no se publica como release final ni contiene una firma Apple. Iniciar sesión con la cuenta propietaria para verlo y descargar sus assets.

Una vez disponible el archivo, comparar su hash desde PowerShell con el informe de ese mismo build:

```powershell
Get-FileHash -LiteralPath 'C:\ruta\Harbor-unsigned.ipa' -Algorithm SHA256
```

## Firma e instalación local

[Sideloadly](https://sideloadly.io/) publica una versión Windows y afirma permitir firma/instalación con una cuenta Apple gratuita, sin membresía de pago. Sus instrucciones actuales para Windows requieren las versiones web de iTunes e iCloud, distintas de las versiones de Microsoft Store. Consultar sus requisitos antes de modificar instalaciones existentes; no se instala ni elimina software automáticamente con esta guía.

1. Descargar Sideloadly desde su sitio oficial e instalar los componentes Apple que indique para Windows.
2. Conectar el iPhone por USB, desbloquearlo y aceptar la confianza del equipo si iOS lo solicita.
3. Abrir Sideloadly, seleccionar ese iPhone y cargar la IPA comprobada.
4. Introducir la cuenta Apple y completar autenticación directamente en la herramienta. Estas credenciales no van en el chat, repositorio ni GitHub Secrets para este flujo local.
5. Usar la instalación normal con Apple ID, conservando la versión mínima iOS 17. No activar inyección de tweaks, cambio del requisito iOS ni JIT; Harbor no los necesita.
6. Completar la confianza del desarrollador y Developer Mode si el dispositivo lo solicita. [Apple explica Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
7. Abrir Harbor. Si la instalación falla, registrar sólo código/mensaje seguro; no compartir un log de autenticación completo.

Según [Apple](https://developer.apple.com/help/account/basics/about-your-developer-account), los perfiles Personal Team expiran a los siete días y permiten hasta tres apps por dispositivo. Sideloadly anuncia renovación de firmas. Esto sirve como vía de pruebas personales; todavía hay que comprobarla con esta IPA y el iPhone concreto. No activa TestFlight ni publicación en App Store.

## Comprobar la reproducción real

Registrar commit, modelo de iPhone y versión iOS. Instalar un addon real con una fuente que el propietario pueda utilizar. El addon oficial de ejemplo sirve para comprobar el protocolo, pero su servidor de vídeo antiguo devolvió HTTP 403 desde Windows; no sustituir la fuente por datos falsos ni dar por hecha su disponibilidad.

Recorrer Home → Buscar → ficha → Streams → seleccionar fuente → player. Confirmar **imagen, audio y avance del tiempo**, luego pausa, seeking, volver al selector y abrir/cerrar de nuevo. Comprobar progreso tras relanzar la app, rotación, pistas/subtítulos cuando la fuente los tenga y una interrupción de red. Exportar diagnostics desde Ajustes: sólo eventos/counts/códigos permitidos. Nunca registrar URLs de reproducción ni tokens.

La apertura del player en un test UI no completa este gate. El milestone sólo se marca logrado después de observar reproducción en el iPhone físico.
