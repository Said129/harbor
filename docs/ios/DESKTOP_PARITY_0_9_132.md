# Objetivo vigente — Harbor Desktop 0.9.132 → iOS/iPadOS 1:1

El propietario fijó este alcance el 17 de octubre de 2026: portar las funciones de Harbor Desktop **0.9.132 (Beta)** que sean compatibles y tengan sentido en iPhone/iPad. **Games queda excluido expresamente**, incluidas sus bibliotecas y herramientas para juegos de PC. Esta decisión sustituye el alcance de funciones móviles seleccionadas del 6 de octubre. Se conserva todo lo ya implementado.

La referencia de código es `0834340cec5531650bfe78cd628628702e636987`, identificada por la [publicación oficial 0.9.132](https://github.com/harborstremio-linux/harbor-linux-builds/releases/tag/beta-v0.9.132). El código de ese commit se recuperó desde la red de forks en `Said129/harbor`; su `package.json` declara 0.9.132. La aplicación Desktop instalada también declara 0.9.132. El código Desktop histórico de esta rama sigue en 0.9.21: se usa como historia del port, sin reemplazarlo ni confundirlo con la referencia actual.

## Criterios de equivalencia

- Comparar recorridos y resultados completos, además de pantallas y nombres de opciones. Un interruptor sin un comportamiento real no completa una función.
- Adaptar la interacción a pantalla táctil, iPad, selector de documentos, compartir, audio y ciclo de vida de iOS. Conservar la identidad de Harbor.
- Registrar cada exclusión adicional con el comportamiento Desktop afectado, su dependencia concreta de PC y el motivo de que carezca de aplicación móvil. Una función pendiente o difícil de implementar no se excluye automáticamente.
- Conservar cuentas, configuraciones, fuentes, identificadores y progreso. Diferenciar coordenadas internas de reproducción y numeración visible de anime.
- Mantener las pruebas aprobadas para archivos y comportamientos intactos; ejecutar las afectadas por cada incremento y registrar su procedencia. Las comprobaciones en simulador no se presentan como pruebas físicas.
- Mantener el mínimo iOS/iPadOS 17 mientras ninguna necesidad verificada justifique cambiarlo. Entregar paquetes sin cuentas ni certificados personales.

## Trabajo y evidencia

El propietario pidió una **única próxima IPA con todos los cambios pendientes del port**, sin generar una IPA por cada añadido. Las comprobaciones parciales de desarrollo conservan sus resultados y capturas, y se ejecutan sin empaquetado de IPA. La siguiente entrega instalable queda reservada a la integración completa y validada del alcance 1:1; los avances parciales no cambian ese criterio.

El inventario reproducible de esta referencia se registra por separado de las matrices históricas. Los estados anteriores conservan su evidencia original: no se convierten automáticamente en equivalencia con 0.9.132. La estimación conversacional del 75–80 % no es una medición auditada ni un criterio de finalización.

Orden de trabajo: continuidad y episodios; cuenta y sincronización; fuentes y plugins; reproducción y subtítulos; biblioteca, descubrimiento y personalización; TV/VOD y deportes; música y lectura; almacenamiento, copias, avisos y ayuda. Esta agrupación organiza el trabajo y no reduce el alcance.

Incidencias comunicadas al fijar el objetivo: el reproductor todavía muestra `T5 · E23` para el episodio absoluto 99 de Super; «Continuar viendo» debe incluir el anime guardado con identificador IMDb en Anime, además de su presencia en Shows. La ficha y su lista de episodios ya tienen la presentación continua de la build 91, cuya evidencia se conserva.

El objetivo permanece **en curso**. Ni la build 91 ni la existencia de un inventario significan que el port 1:1 esté terminado.

## Primer incremento validado

La build 92 corrige los rótulos de episodio y la continuidad de anime IMDb. [Entrega 92](DELIVERY_2026-10-17_92.md), [ejecución](https://github.com/Said129/harbor/actions/runs/39026561340), fuente `7c904bac067752f5ce16ad22e4b4f75b47c71859`. Siete casos afectados y tres imágenes revisadas; validación física pendiente. El inventario completo permanece en revisión y el objetivo sigue activo.
