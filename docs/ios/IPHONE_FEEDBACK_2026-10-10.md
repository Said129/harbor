# Continuidad Desktop/iPhone para la única IPA final

Este incremento se acumula con las correcciones del [9 de octubre](IPHONE_FEEDBACK_2026-10-09.md). La IPA 84 de Descargas permanece intacta; estos cambios de fuente todavía no están compilados ni entregados.

## Causa y comportamiento

La biblioteca nativa trataba `timesWatched` como si describiera únicamente el vídeo actual. Desktop lo usa como contador histórico: un capítulo completado podía ocultar la serie durante el capítulo siguiente, y una película vista anteriormente podía reanudarse desde cero aunque se estuviera volviendo a ver.

- Separar el contador histórico de la bandera y el progreso del vídeo actual. Mantener los capítulos a medias y las películas que se vuelven a ver; aplicar a las películas el umbral de finalización del 90 % de Desktop. Conservar el capítulo terminado como punto desde el que elegir el siguiente.
- Aceptar fechas cloud ISO o numéricas en milisegundos, tanto para ordenar la biblioteca como para comparar la posición de reanudación. Resolver las coordenadas desde `video_id`, incluidos los identificadores Kitsu de tres segmentos, sin trasladar posiciones a otro capítulo o título.
- Al reproducir desde la ficha o «Continuar viendo», elegir el siguiente capítulo disponible sin ver cuando el actual haya terminado. Mantener un capítulo que se vuelve a ver a medias, separar especiales y conservar el punto original cuando no haya otro capítulo disponible. Los episodios no emitidos quedan fuera de la selección automática.
- Cargar metadata real para los logos y los títulos de los capítulos en las tarjetas. Mostrar el capítulo seleccionado y «A continuación» cuando corresponda, con progreso visual cero para ese capítulo nuevo. Esta presentación no escribe una posición ficticia en Stremio. Imagen y título conservan sus recorridos táctiles separados hacia reproducción y ficha.
- Actualizar `timeWatched`, `overallTimeWatched`, `timesWatched`, `flaggedWatched`, coordenadas y `video_id` según el vídeo actual, preservando los campos desconocidos del proveedor y el bitfield de capítulos vistos. Reiniciar el vídeo pone a cero la bandera actual sin borrar el historial. Un mismo capítulo completado no incrementa varias veces el contador por repetir la escritura final.
- Reutilizar los textos oficiales para favoritos, quitar de Seguir viendo, A continuación y tiempo restante. No añadir mensajes al gesto de tamaño del reproductor.

Las fuentes de referencia de Desktop se registran con sus hashes en [beta-vector-provenance.json](beta-vector-provenance.json): `stremio.ts`, `detail-resume-advance.ts`, `use-cw-advance.ts`, `use-stremio-sync.ts`, `continue-card.tsx` y las traducciones oficiales. Se mantiene la referencia pública 0.9.128 junto con las capturas 0.9.130 del propietario.

## Verificación pendiente

`LibraryContinuityTests` prepara seis comprobaciones nativas: historial y nueva reproducción; película terminada y ancla de serie; fechas numéricas y coordenadas anime; elección del siguiente capítulo, tarjeta y rewatch; escritura compatible con Stremio y conservación de datos; reinicio y rechazo de snapshots inválidos. Usan registros locales sintéticos y la misma lógica de producción, sin credenciales ni cuentas privadas.

Estas pruebas aún no se han ejecutado. Windows no dispone de Xcode; la instrucción del propietario reserva la compilación Apple y la validación completa de servicios/UI para una única IPA final. No se declara probado el recorrido físico PC/iPhone ni el acceso a cuentas privadas. La compilación Linux exigida por `AGENTS.md` también queda pendiente de un entorno Linux; no se sustituye por una compilación Windows.

Comprobación local realizada: `pnpm run check --no-error-on-unmatched-pattern` pasó para los cinco documentos/JSON modificados, después de aplicar el formato requerido a tres JSON. `git diff --check` pasó. La herramienta no analiza Swift y no se presenta como validación nativa. No se modificaron TypeScript ni Rust.
