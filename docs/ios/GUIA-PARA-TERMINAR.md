# Guia para terminar el port de Harbor iOS (escrita el 8 de noviembre de 2026)

Esta guia es para continuar el trabajo con otra herramienta (por ejemplo ChatGPT con acceso al repositorio) cuando Claude ya no pueda. Esta en espanol a proposito.

## 1. Donde esta todo

| Cosa                                      | Valor                                                                                                                      |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Repositorio local                         | `C:\Users\Said\Documents\Codex\2026-10-11\podrias-ser-capaz-de-seguir-este\work\harbor-ios`                                |
| Remoto de GitHub                          | `Said129/harbor`                                                                                                           |
| Rama de desarrollo                        | `ios/music-subtitle-94`                                                                                                    |
| Rama que ejecuta CI                       | `ios/music-validation-94` (se copia de la de desarrollo antes de lanzar CI)                                                |
| Referencia Desktop 0.9.132 (solo lectura) | `C:\Users\Said\Documents\Codex\2026-10-11\podrias-ser-capaz-de-seguir-este\work\harbor-revision\parity132\desktop-0.9.132` |
| Auditoria (script que genera todo)        | `scripts/ios/parity-audit-2026-11-04.py`                                                                                   |
| Resultado de la auditoria                 | `docs/ios/PARITY_AUDIT_2026-11-04.md` y `parity-audit-2026-11-04.json`                                                     |
| Filas pendientes (generado)               | `docs/ios/PENDING_ROWS_2026-11-08.md`                                                                                      |
| Registro de trabajo                       | `docs/ios/music-subtitle-94-work.md` (una seccion por ronda)                                                               |
| Mensaje para el dueno                     | `C:\Users\Said\Downloads\Harbor\MENSAJE-PARA-SAID.md`                                                                      |

El equipo de Windows no tiene el SDK de Apple. **Todo lo que se compila o se prueba pasa por GitHub Actions** (macOS). Python 3 y `gh` estan instalados; `gh` ya tiene la sesion de `Said129`. No hay que introducir contrasenas ni tokens.

## 2. Estado al escribir esto

- Auditoria (lectura de codigo, **no** prueba en el movil): **87,2 % ponderado**, **75,0 % solo portado**, 99,4 % portado o parcial. Son 949 filas: 489 portadas (D), 159 parciales (P), 4 faltantes (M), 297 excluidas con motivo (X).
- El porcentaje ponderado cuenta cada parcial como medio punto y no cuenta las excluidas.
- La rama de desarrollo compila en CI y las pruebas nuevas de las rondas 21 a 24 pasan (142, 27, 55, 103 y 179 de 180 casos; el que faltaba era un test mal escrito y se corrigio; su repeticion final seguia en curso al escribir esto).
- **No hay IPA generada** (ver seccion 6).

## 3. Reglas del dueno (hay que respetarlas)

1. Solo se porta lo que sirve en iPhone o iPad. Cada exclusion se registra en `scripts/ios/parity-audit-2026-11-04.py` con una linea de motivo.
2. No dar fechas ni estimaciones de tiempo. No dar porcentajes sin que salgan de la auditoria (es lectura de codigo, no ejecucion).
3. Una sola IPA, al final. No generar IPA por cada cambio.
4. No cambiar ajustes del repositorio ni saltarse restricciones de GitHub.
5. Commit, push y lanzar CI se hacen sin pedir permiso. Nunca escribir contrasenas, claves ni tokens.
6. El inicio de sesion de Stremio **lo quito el dueno** antes de empezar el port: no se porta (login, perfil, biblioteca en la nube, reparacion, sincronizar coleccion de addons). No mostrar avisos tipo "inicia sesion en Stremio".
7. Dar actualizaciones cortas en espanol.

## 4. Como se trabaja (el ciclo de una ronda)

1. Elegir filas pendientes de `docs/ios/PENDING_ROWS_2026-11-08.md`. Leer el fuente de Desktop de cada fila y el codigo de iOS antes de tocar nada.
2. Cambios pequenos: la logica en funciones puras en un archivo nuevo de `ios/Harbor/Services` o `ios/Harbor/Models`, y en las vistas grandes (`DetailView`, `EpisodeList`, `PlayerView`, `HarborService`) solo unas lineas que llamen a esa logica.
3. Cada ronda lleva su archivo de pruebas `ios/HarborTests/Rxx...Tests.swift` y se registra en `ios/project.yml` (bloque `HarborChangedTests`, una linea `- path: HarborTests/NombreTests.swift`).
4. Textos nuevos de interfaz: en ingles, exactamente el texto de Desktop, con `DesktopInterfaceText.value("...")`. Luego sincronizar traducciones (seccion 5).
5. Actualizar la auditoria: anadir lineas `indice veredicto nota` al final del bloque `BEHAVIORS` (justo antes de `""")` y `SETTINGS = expand("""`) o del bloque `SETTINGS` en `scripts/ios/parity-audit-2026-11-04.py`. Si una fila aparece dos veces, **gana la ultima linea**. Despues ejecutar `python -I scripts/ios/parity-audit-2026-11-04.py`, que regenera el `.md` y el `.json` con los totales. Una fila solo pasa a D si el hueco que decia su nota queda cerrado; si no, queda P con la nota actualizada.
6. Anadir una seccion al registro de trabajo, hacer commit y push, y lanzar CI.

Notas de Swift que ya dieron errores:

- Swift 5 en modo normal, iOS 17 minimo, `@MainActor @Observable`.
- No llamar `description`, `hash` ni `debugDescription` a una propiedad de una subclase de `NSObject` (rompe la compilacion; paso con el delegado de XMLTV).
- `PlayerView.swift` esta al limite del compilador (expresiones demasiado largas): no anadir modificadores a su cadena; usar un `ViewModifier` en un archivo propio.
- Los archivos deben quedar con saltos de linea LF. Antes de cada commit revisar que no haya CRLF ni marcas de conflicto. `docs/ios/desktop-locales-0.9.132.json` hay que convertirlo de CRLF a LF despues de sincronizar.

## 5. Traducciones

```
python -I scripts/ios/sync-interface-locales.py --reference <ruta de desktop-0.9.132> --only-labels-file <json con la lista de textos nuevos>
```

- Nunca con una lista vacia.
- El JSON de textos debe estar en UTF-8 **sin BOM** (con PowerShell 5.1 hay que escribirlo con `[IO.File]::WriteAllText(..., (New-Object Text.UTF8Encoding($false)))`).
- Solo anade lineas a los 16 `Localizable.strings` y a `docs/ios/desktop-locales-0.9.132.json`; los textos que Desktop no traduce se quedan en ingles.

## 6. CI, pruebas e IPA

Lanzar una validacion enfocada (sin IPA):

```
gh workflow run ios.yml --repo Said129/harbor --ref ios/music-validation-94 -f validation_scope=focused -f validation_only=true -f music_runtime_candidate=true -f upload_artifacts=true -f apple_runner=macos-15-intel -f "native_test_selection=HarborChangedTests/Clase/testNombre,HarborChangedTests/OtraClase/testOtro"
```

- Antes de lanzar, subir el commit a la rama de CI: `git push origin ios/music-subtitle-94:ios/music-validation-94`.
- Un lanzamiento nuevo en la misma rama **cancela** el que esta en marcha. Para correr varias validaciones a la vez, subir el mismo commit a ramas temporales nuevas (por ejemplo `ios/r25-a`) y lanzar en cada una; borrarlas despues con `git push origin --delete <rama>`.
- Todos los casos de una misma ejecucion deben ser del mismo objetivo: o todos `HarborChangedTests/...` (lo que esta en `project.yml`) o todos `HarborTests/...` (el resto). Mezclarlos hace fallar la ejecucion al arrancar.
- Una ejecucion dura entre 25 y 40 minutos. Ver estado: `gh run view <id> --repo Said129/harbor --json status,conclusion,jobs`.
- Resultados: `gh run download <id> --repo Said129/harbor --name focused-results --dir <carpeta>`; dentro hay `focused-results.json`, y `logs/focused-build.log` y `logs/focused-tests.log` (los errores de compilacion salen con `error:`).
- La suite completa (`validation_scope=full`) **ya no es una senal fiable**: tiene unos 27 casos que fallan tambien en el commit anterior a todo este trabajo (pruebas de preparacion de interfaz que se niegan a correr si el simulador ya tiene datos, casos solo de iPad, textos de musica). No se deben usar como criterio de verde.

**Para generar la IPA final** (solo cuando se decida que el port esta terminado): lanzar el mismo comando con `validation_only=false` y una seleccion pequena (por ejemplo un solo test que compile todo). Genera el artefacto `iphone-unsigned-ipa` con `Harbor-unsigned.ipa` y su `.json`. La IPA sale **sin firmar**: el dueno la firma e instala el mismo en su movil.

## 7. Problemas conocidos

- `MobileSourcesAndSubtitlesTests/testAddonSubtitleLoadsOnlyChosenFileWithoutDuplicatingOrStoppingVideo` es **intermitente** en CI (tambien fallo en el commit viejo, 2 de 4 veces). Es un mpv real en el simulador. Su mensaje de error ahora imprime el estado del reproductor. En el movil conviene cargar un subtitulo de un addon un par de veces para ver si se selecciona.
- Los tests de Trakt de la pagina de inicio dependian de la fecha real; ya usan una fecha fija (`Date(timeIntervalSince1970: 1_793_230_800)`).
- Nada de lo nuevo se ha ejecutado en un dispositivo ni contra servicios reales: solo se compila y se prueba con tests unitarios en CI.

## 8. Que queda (resumen honesto)

El detalle esta en `docs/ios/PENDING_ROWS_2026-11-08.md` (163 filas: 159 parciales y 4 faltantes). Lo que queda se divide en tres tipos:

1. **Logica ya escrita y probada pero sin conectar a ninguna pantalla** (reglas de paginas dobles de manga, continuar la cola de musica, reescanear carpetas de musica, reglas de ranking de subtitulos, ranking de busqueda por popularidad, catch-up de TV en vivo, orden diario de Discover, linea de equipo en comun...). Conectarlas es trabajo de pantalla y es lo mas rentable.
2. **Funciones grandes que faltan**: busqueda de anime (AniList, Jikan, Kitsu), mas rieles de TMDB que tiene Desktop, filtro de categorias en la biblioteca de manga (Suwayomi), vista de detalle de episodio, progreso de las listas de AniList y MAL sin tener que abrir su pantalla, la normalizacion de nombres de filas de addons, pestana de equipos favoritos de deportes.
3. **Cosas que quiza no tienen sentido en iPhone** (decidir y excluir con motivo): DLNA por multidifusion (necesita un permiso que Apple no da libremente), video por AirPlay, fuentes personalizadas de subtitulos (el reproductor solo conoce fuentes fijas), atajos de teclado reasignables (solo iPad con teclado), sustituir la fuente de titulos por Sentient (necesita archivos de fuente).

Las filas cuyo texto de hueco dice "earlier review Partial" son parciales por una revision antigua que no se ha vuelto a leer: conviene releerlas contra el codigo (a menudo ya estan hechas).

## 9. Orden sugerido para acabar

1. Conectar las piezas de la categoria 1 (cada una es pequena y ya tiene pruebas).
2. Releer las filas "earlier review Partial" y cerrar o excluir con motivo.
3. Decidir las exclusiones de la categoria 3 y registrarlas en el script de auditoria.
4. Regenerar la auditoria, lanzar CI enfocado con todas las pruebas nuevas, corregir lo que falle.
5. Cuando el dueno diga que esta terminado: generar la IPA (seccion 6) y entregar el artefacto.
