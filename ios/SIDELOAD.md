# Instalar y comprobar Harbor para iPhone

La build 87 está entregada en `C:/Users/Said/Downloads/Harbor-iPhone-87.ipa` y como última versión en `Harbor-unsigned.ipa`. Corrige consultas/filtros de fuentes anime y añade búsqueda de contenido, historial borrable y sincronización opcional de subtítulos externos SRT/VTT. Fuente `925fdd05b39f8ba0cdb3329c4c16879a5f31efe6`, [compilación 38474226961](https://github.com/Said129/harbor/actions/runs/38474226961) aprobada. Catorce métodos afectados tienen resultados aprobados: once conservados y tres ejecutados en la revisión final; las demás áreas mantienen la evidencia aceptada de la 86. Se revisaron 3 capturas nuevas de búsqueda/historial. Addons y URLs configuradas se comparten por Stremio; los ajustes generales siguen locales. La cifra privada de trece fuentes de Core Nexus y la comprobación física de la 87 siguen pendientes. Informe: [DELIVERY_2026-10-14.md](../docs/ios/DELIVERY_2026-10-14.md).

La IPA está sin firmar y requiere iPhone con iOS 17 o posterior. El gate de simulador/dispositivo compilado no acredita instalación ni reproducción en el iPhone físico del propietario.

## Firma e instalación

1. Abre la herramienta de firma que ya utilizaste para instalar Harbor y selecciona tu iPhone conectado y desbloqueado.
2. Carga `C:/Users/Said/Downloads/Harbor-unsigned.ipa`. Completa la autenticación Apple directamente en esa herramienta si la solicita; las credenciales no se introducen en el chat ni en el repositorio.
3. Conserva la misma identidad de firma y el bundle ID `site.harbor.iphone`. Instala la actualización sobre Harbor para conservar datos, sin desinstalar la app anterior ni cambiar el requisito mínimo de iOS.
4. Abre la app y comprueba tus addons y biblioteca. La guía y el informe de esta entrega están junto a la IPA en Descargas.

El paquete tiene 37104770 bytes y SHA-256 `d11b5368b019f54f1d45f6ad0da045cd43707dacb7e59966c42bd8954413f77d`. Para comprobar la copia:

```powershell
Get-FileHash -LiteralPath 'C:/Users/Said/Downloads/Harbor-unsigned.ipa' -Algorithm SHA256
```

## Cuenta y fuentes

Usa la misma cuenta Stremio que en Harbor Desktop para recuperar su colección sincronizada de addons y probar continuidad. Las URLs configuradas y el token de sesión se guardan en Keychain; la contraseña no se conserva. El perfil portátil Harbor utiliza su propia cuenta y sincronización, separadas de Stremio. Si falla la red, conserva los datos anteriores y reintenta desde Cuenta.

La reproducción requiere una URL HTTP(S) resuelta y disponible. Un addon configurado con TorBox u otro proveedor puede entregar esa URL; esto no equivale a un cliente Debrid completo. Torrents/infoHash sin URL, resolución nativa de YouTube/NZB y DRM no están soportados. El addon público de ejemplo prueba el protocolo y la navegación; su servidor de vídeo antiguo no certifica todos los transportes ni fuentes privadas.

## Comprobación física y privada pendiente

Con una fuente disponible del propietario, recorre Home → búsqueda → ficha → selector → reproducción. Comprueba imagen, audio y avance real del tiempo; pausa/avance/retroceso; reanudación; cambio de fuente; pistas/subtítulos y siguiente episodio. Comprueba además PiP, giro con bloqueo del sistema, gestos de tamaño e interrupciones. AirPlay ofrece selección de salida de audio; no se declara vídeo AirPlay.

Verifica biblioteca y progreso en PC/iPhone con la misma cuenta, aislamiento al cambiar de cuenta y el perfil Harbor. Submanhwa conserva su navegación por cuenta: comprueba acceso, cierre/reapertura y lectura directamente en el teléfono. No se han ejecutado giros, compras ni mensajes de Gacha. Los servidores Suwayomi/Xtream y addons privados requieren la configuración del propietario.

El simulador omitió el inicio real de PiP por falta de soporte AVKit en ese destino. Decodificar vídeo y alternar renderers no demuestra una ventana PiP física. La confirmación física de builds anteriores no se extiende a esta candidata ni a todas las fuentes/opciones. Se registran modelo/iOS y resultados seguros al hacer estas pruebas; los diagnostics exportables excluyen tokens y URLs privadas.

Los límites completos y la evidencia de esta fuente se conservan en [la entrega](../docs/ios/DELIVERY_2026-10-13.md). Se actualiza contenido editorial mediante sus fuentes validadas; cambiar el binario firmado exige otra instalación/firma y no se promete actualización silenciosa.
