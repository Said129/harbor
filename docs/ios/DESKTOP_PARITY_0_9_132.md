# Objetivo vigente — Harbor Desktop 0.9.132 → iOS/iPadOS 1:1

El propietario fijó este alcance el 17 de octubre de 2026: portar las funciones de Harbor Desktop **0.9.132 (Beta)** que sean compatibles y tengan sentido en iPhone/iPad. **Games queda excluido expresamente**, incluidas sus bibliotecas y herramientas para juegos de PC. El 18 de octubre excluyó también **los perfiles infantiles y la sección infantil**, con sus interfaces, controles parentales y límites diarios. Esta decisión sustituye el alcance de funciones móviles seleccionadas del 6 de octubre. Se conserva lo implementado dentro del alcance vigente.

La referencia de código es `0834340cec5531650bfe78cd628628702e636987`, identificada por la [publicación oficial 0.9.132](https://github.com/harborstremio-linux/harbor-linux-builds/releases/tag/beta-v0.9.132). El código de ese commit se recuperó desde la red de forks en `Said129/harbor`; su `package.json` declara 0.9.132. La aplicación Desktop instalada también declara 0.9.132. El código Desktop histórico de esta rama sigue en 0.9.21: se usa como historia del port, sin reemplazarlo ni confundirlo con la referencia actual.

## Criterios de equivalencia

Actualización y aclaración del propietario del 27 de octubre: terminar primero iOS/iPadOS conservando el sistema existente de perfiles y cuenta de Harbor; eliminar el sistema de cuentas/sesiones y la sincronización autenticada de Stremio. Conservar los datos mediante migración recuperable y mantener la compatibilidad con el protocolo abierto de addons. No se pide inventar otro sistema de perfiles. Esta excepción se incorpora al port sin reducir el resto de la equivalencia. El alcance se registra en [INDEPENDENT_APP_SCOPE.md](INDEPENDENT_APP_SCOPE.md). Desktop, Android y Android TV quedan para después de terminar iOS; su orden posterior es flexible.

- Comparar recorridos y resultados completos, además de pantallas y nombres de opciones. Un interruptor sin un comportamiento real no completa una función.
- Incluir todas las interfaces, animaciones, transiciones, secciones y estados de carga, vacío y error que correspondan al alcance compatible. Esta ampliación fue confirmada expresamente por el propietario el 17 de octubre. Revisar la composición visual y el movimiento frente a la referencia, además de la lógica, adaptando el tamaño y la interacción a iPhone/iPad y respetando Reducir movimiento.
- Adaptar la interacción a pantalla táctil, iPad, selector de documentos, compartir, audio y ciclo de vida de iOS. Conservar la identidad de Harbor.
- Registrar cada exclusión adicional con el comportamiento Desktop afectado, su dependencia concreta de PC y el motivo de que carezca de aplicación móvil. Una función pendiente o difícil de implementar no se excluye automáticamente.
- Respetar también las exclusiones explícitas del propietario. Kids y los perfiles infantiles no forman parte de esta entrega; los perfiles normales y su aislamiento de cuentas siguen incluidos. Conservar los campos Desktop no utilizados al sincronizar, sin crear controles ni rutas infantiles en iOS ni borrar datos de Desktop.
- Conservar cuentas, configuraciones, fuentes, identificadores y progreso. Diferenciar coordenadas internas de reproducción y numeración visible de anime.
- El propietario corrigió la petición anterior sobre temporadas el 19 de octubre: no se debe imponer una temporada única a todo el anime. Conservar las presentaciones por temporadas y de lista continua de Desktop, según el orden elegido y los datos del proveedor. La lista continua de las builds anteriores es evidencia histórica, no una regla vigente que permita borrar temporadas. La referencia usa TVDB por defecto (`aired`) y permite otros órdenes disponibles, incluido `absolute`; la agrupación visible nunca modifica los identificadores de fuentes, vistos o progreso.
- Mantener las pruebas aprobadas para archivos y comportamientos intactos; ejecutar las afectadas por cada incremento y registrar su procedencia. Las comprobaciones en simulador no se presentan como pruebas físicas.
- Mantener el mínimo iOS/iPadOS 17 mientras ninguna necesidad verificada justifique cambiarlo. Entregar paquetes sin cuentas ni certificados personales.

## Trabajo y evidencia

El lector incorpora brillo, ancho de página en iPad, concentración persistente
e importación TTF/OTF por perfil, con vista previa y borrado. Las nuevas pruebas
de Core Text y los recorridos del lector están preparados; la comprobación
Apple y del resultado visual sigue pendiente. [Estado del lector](ebook-reading-display-0.9.132.md).

La validación `39763655130` aprobó los nueve casos nativos seleccionados de
metadatos, adaptaciones y EPUB local. Su árbol y registro originales se
autenticaron y quedan conservados sin repetición. Las interfaces de ese bloque
siguen en ejecución; no se presenta como cierre visual ni del port completo.

Libros incorpora las listas independientes de Marcados, Favoritos y Leer
después, además de filtros de lectura y finalizados. Quitar una marca conserva
el archivo y su progreso. La migración local respeta los perfiles y conserva
los datos ante fallos de almacenamiento; tres comprobaciones nativas nuevas
están preparadas y pendientes de Apple. No implica sincronización remota ya
aprobada. [Alcance de las listas](ebook-library-0.9.132.md).

En integración, 22 de octubre: la ficha de Libros incorpora los volúmenes,
búsqueda y orden de capítulos, lista/cuadrícula y paginación de Desktop. Abrir
un capítulo conserva su ruta original aunque se cambie el orden visible. Los
datos usan las escalas originales de puntuación y los recuentos de ediciones,
lectores y traducciones. Ocho comprobaciones locales aprobaron; tres casos
nativos nuevos y sus interfaces Apple siguen pendientes.
[Alcance y validación de la ficha](ebook-detail-0.9.132.md).

Actualización del 22 de octubre: se integra el motor original de metadatos y
descubrimiento de libros, su caché y clave opcional por perfil, fuentes de
lectura verificadas, colecciones y recomendaciones. Se corrigen el acceso a
fuentes locales de lectura, los toques en portadas y el foco del editor. Se
conservan doce aprobaciones nativas del bloque conjunto y las cuatro de HTML;
el incremento nuevo todavía requiere su compilación y recorridos en Apple.
[Implementación, evidencia y pendientes de Libros](ebook-metadata-0.9.132.md).
La próxima IPA sigue reservada al alcance completo validado.

El propietario pidió una **única próxima IPA con todos los cambios pendientes del port**, sin generar una IPA por cada añadido. Las comprobaciones parciales de desarrollo conservan sus resultados y capturas, y se ejecutan sin empaquetado de IPA. La siguiente entrega instalable queda reservada a la integración completa y validada del alcance 1:1; los avances parciales no cambian ese criterio.

El inventario reproducible de esta referencia se registra por separado de las matrices históricas. Los estados anteriores conservan su evidencia original: no se convierten automáticamente en equivalencia con 0.9.132. El 19 de octubre se retiró el 75 % conversacional como indicador fiable: se había repetido sin recalcularlo. No hay un porcentaje actual auditado ni una fecha defendible. Las actualizaciones deben distinguir cambios implementados, resultados realmente comprobados y trabajo pendiente; un despacho de CI, un test nuevo o una corrección del sistema de pruebas no equivale automáticamente a más funciones portadas. La revisión visual y de animaciones conserva todo el alcance acordado.

Orden de trabajo: continuidad y episodios; cuenta y sincronización; fuentes y plugins; reproducción y subtítulos; biblioteca, descubrimiento y personalización; TV/VOD y deportes; música y lectura; almacenamiento, copias, avisos y ayuda. Esta agrupación organiza el trabajo y no reduce el alcance.

### Actualización del 21 de octubre

La integración `679b6290e55a19f0ae75c29e883304c6f19b3aa2` conserva 24 casos nativos aprobados y tres aprobaciones adicionales: consulta pública de película, preparación del perfil y regreso de iPhone. También dejó tres casos fallidos y tres cierres por una expresión regular al procesar traducciones. Las tres imágenes originales del regreso se revisaron; las animaciones y la validación física siguen abiertas. El catálogo de plugins `fbdb2c62bae375b9df45d1a8987a1e9f50b8341b` aprobó sus ocho casos nuevos, con una advertencia de concurrencia pendiente de recompilar.

La fuente `a488db07303df8a59993a42abc85c494dfc3efd4` incorpora los arreglos de esos fallos, la operación explícita de reinicio de reproducción, la corrección de la advertencia y el codec gRPC. La [validación 39504615361](https://github.com/Said129/harbor/actions/runs/39504615361) aprobó 12 de sus 13 casos y compiló sin advertencias nuevas. Quedó un fallo de separación de líneas CRLF en trailers gRPC, corregido en el bloque siguiente y aún pendiente de validar. Se conservan esas 12 aprobaciones y las 35 recientes de los dos bloques anteriores. [Resultados, causas y límites](PLUGIN_FOLLOWUP_0_9_132.md).

El transporte asíncrono real de Plugins está implementado y su [primera validación 39510296663](https://github.com/Said129/harbor/actions/runs/39510296663) aprobó ocho contratos Rust. Clippy detectó después una API atómica renombrada en el compilador actual; se corrige sin suprimir advertencias. La compilación para iOS, los casos Swift y la consulta pública TLS/HTTP2 todavía no llegaron a ejecutarse. El cliente de descargas de repositorios añade cuatro casos nuevos pendientes. [Implementación, resultados y límites](PLUGIN_NETWORK_0_9_132.md).

Plugins aún necesita integrar ese transporte, gestor, contraseñas, productores y pantallas. Continúan todos los demás pendientes compatibles de funciones, sincronización, interfaces y animaciones. No hay una IPA nueva ni un porcentaje global auditado. El registro siguiente conserva la historia de los incrementos y queda sustituido por esta actualización en los puntos que todavía figuraban como pendientes.

### Registro anterior, 20 de octubre, 10:18 UTC

Los apartados posteriores conservan la historia de cada incremento. Este estado sustituye sus resultados que todavía figuraban como pendientes:

- Conexión pública de TVDB: los seis contratos nativos y la consulta real con imagen aprobaron en [39239642918](https://github.com/Said129/harbor/actions/runs/39239642918). Se conservan los dos árboles originales de Xcode y los siete resultados reales.
- Motor de órdenes de episodios: los nueve casos nativos nuevos aprobaron en [39241847884](https://github.com/Said129/harbor/actions/runs/39241847884). Están implementados los seis modos de la referencia. Ese resultado no certifica por sí solo las vistas ni las franquicias completas.
- Panel de órdenes conectado a ficha y reproductor: [39320374824](https://github.com/Said129/harbor/actions/runs/39320374824) aprobó diez casos nativos y los dos recorridos nuevos de interfaz de iPhone/iPad. Se conservaron sus árboles originales de Xcode y se inspeccionaron las ocho imágenes originales. La revisión visual sigue siendo parcial; los vídeos no aprueban por sí solos el movimiento. El registro de esa fuente conserva dos advertencias de interpolación en pruebas; la compilación posterior de `9fe1671` confirma su corrección, sin repetir las interfaces aprobadas.
- Franquicias de anime: detección de relaciones y raíces, selector de entradas reales, caché pública acotada y protección ante cambios de perfil incorporados en `ee03d0a4b2fee30f9e9db9bb5a770e04c67f5dff`. [39327069185](https://github.com/Said129/harbor/actions/runs/39327069185) aprobó sus nueve casos nativos y los dos contratos públicos reales. Se conservan los árboles originales y los once resultados; su fuente todavía contiene las advertencias de pruebas ya corregidas después. [Alcance y pendientes del incremento](ANIME_FRANCHISE_0_9_132.md).
- Combinación de episodios entre entradas: `9fe1671f904f5f016b83eb743730d0cd6380633c` conecta la reproducción, los subtítulos, los vistos y la reanudación con la fuente real. [39329283077](https://github.com/Said129/harbor/actions/runs/39329283077) ejecutó sus veinticuatro casos nativos: veintitrés aprobaron y uno falló por faltar la identidad obligatoria del addon en el dato sintético de prueba. También aprobó el contrato público del episodio 99. No aparecieron advertencias nuevas. Los resultados nativos se autentican contra el registro original de Xcode; el recolector antiguo rechazó el tamaño 24 y no conservó ese árbol canónico. No se presenta una evidencia inexistente. La corrección del dato sintético y del recolector está incluida en el bloque siguiente.
- Películas y especiales: `71be530b5c4c1782d1e0566b30f3cabdb3718ad4` incorpora filas combinadas, tarjeta de película, resolución de metadatos reales, identidad de reproducción y compatibilidad con reanudaciones antiguas. La [ejecución 39406575431](https://github.com/Said129/harbor/actions/runs/39406575431), iniciada una sola vez, selecciona diez casos nuevos, el caso fallido reparado, dos casos afectados y un contrato público nuevo. Sus resultados Apple siguen pendientes. Se conservan los éxitos anteriores de partes intactas. [Comportamiento y límites del incremento](ANIME_FRANCHISE_EXTRAS_0_9_132.md).
- Perfiles e inicio: [39237920401](https://github.com/Said129/harbor/actions/runs/39237920401) conservó siete recorridos de interfaz aprobados y tres preparaciones aprobadas; falló el regreso con sesión expirada en iPhone. No se repiten los aprobados. El fallo y la revisión visual pendiente impiden dar por cerrado el bloque.

Siguen abiertos la validación del bloque nuevo de películas/especiales y los pendientes de anime descritos en su documento; la sincronización completa de cuentas, perfiles y ajustes; las opciones y secciones restantes de Desktop; y la revisión completa de interfaces, estados y animaciones. La lista de pendientes de anime aún necesita contrastar la navegación mixta con el comportamiento real de la referencia antes de tratarla como una exigencia de equivalencia. No se ha generado una IPA nueva. Este registro es evidencia de avances concretos y no un porcentaje de equivalencia global. El inventario de 0.9.132 sigue siendo un índice de auditoría, no un denominador de funciones terminadas.

Incidencias comunicadas al fijar el objetivo: el reproductor todavía muestra `T5 · E23` para el episodio absoluto 99 de Super; «Continuar viendo» debe incluir el anime guardado con identificador IMDb en Anime, además de su presencia en Shows. La ficha y su lista de episodios ya tienen la presentación continua de la build 91, cuya evidencia se conserva.

El objetivo permanece **en curso**. Ni la build 91 ni la existencia de un inventario significan que el port 1:1 esté terminado.

La rectificación del 19 de octubre se integra en el modelo: el suplemento de anime conserva las temporadas del proveedor como presentación predeterminada y ofrece la lista continua por elección cuando existe una correspondencia completa y no ambigua. Cambiar la presentación no vuelve a descargar la ficha ni las imágenes; ambas variantes conservan exactamente los identificadores y las claves de vistos. La selección utiliza los valores Desktop `aired` y `absolute` de `tvdbSeasonType` y pertenece al documento de ajustes del perfil. «Continuar viendo» vuelve a proyectar sus rótulos al cambiar esa elección. Se restauran también los metadatos persistidos por builds que imponían una temporada única. **Este incremento todavía no completa el panel de órdenes de TVDB ni los órdenes DVD, alternativos o regionales de Desktop.** Sus tres casos nuevos de modelos pasaron con el SDK de Apple en la [ejecución 39229215940](https://github.com/Said129/harbor/actions/runs/39229215940), fuente `7ec9a586e571d2ee6c42accc0bfeb1e56aa95b24`. La revisión de las vistas y sus imágenes sigue pendiente.

## Primer incremento validado

El 19 de octubre se comprobó el cierre de los servidores originales de Harbor. El propietario pidió investigar la continuidad de TVDB y después precisó que se conservara el sistema existente con un arreglo. Se mantiene el protocolo público de Desktop y se usa el intermediario compatible de la continuación comunitaria. [Investigación, límites y comportamiento](TVDB_SERVICE_CONTINUITY.md). El cambio `a00d672c9edc9aaba0dbe34cbd7515c1b329379b` incorpora el cliente público nativo, conserva los identificadores y ambas presentaciones, y mantiene la lista original si el suplemento falla. La [ejecución 39236580472](https://github.com/Said129/harbor/actions/runs/39236580472) selecciona seis casos nuevos de contrato/identidad/fallos y uno de conexión e imagen pública real. **Sus resultados de ejecución siguen pendientes; no se ha generado una IPA ni se ha completado el panel de órdenes de TVDB.** Los accesos de cuentas no se redirigen con este arreglo.

La build 92 corrige los rótulos de episodio y la continuidad de anime IMDb. [Entrega 92](DELIVERY_2026-10-17_92.md), [ejecución](https://github.com/Said129/harbor/actions/runs/39026561340), fuente `7c904bac067752f5ce16ad22e4b4f75b47c71859`. Siete casos afectados y tres imágenes revisadas; validación física pendiente. El inventario completo permanece en revisión y el objetivo sigue activo.

La validación posterior del reproductor real [39145147124](https://github.com/Said129/harbor/actions/runs/39145147124), aplicación `49110c6786903d6480c2febe101d8210f2a4fb9b`, pasó los dos recorridos funcionales de iPhone e iPad y sus dos preparaciones aisladas. Usa un vídeo sintético propio servido por un addon de prueba: exige un fotograma renderizado, `T1 · E99`, avance manual a `T1 · E100` y peticiones originales `tt4644488:5:23` y `tt4644488:5:24`. No introduce opciones de prueba en producción ni incluye el vídeo en la aplicación. No aparecieron advertencias nuevas. Las cuatro capturas de `XCUIApplication.screenshot()` resultaron recortadas al girar y no aprueban la presentación completa; falta comprobar una captura de pantalla completa antes de cerrar la revisión visual. No se presenta como prueba física ni de un vídeo real de Dragon Ball.

## Apariencia de perfiles normales en integración

El registro de perfiles pasa a ser la autoridad de nombre, color y avatar. La cabecera y el editor de cuenta lo consultan mediante la misma proyección que el selector. Las fotos propias se normalizan a JPEG de hasta 384 píxeles y se guardan en registros locales inmutables: primero se conserva la imagen y después se confirma su referencia junto a los metadatos, en una única escritura del perfil. Un fallo al guardar conserva el estado anterior. La lista sincronizable no incluye las fotos, sus referencias locales ni sus marcadores de cuenta. Un avatar de catálogo elegido en Desktop sustituye la foto local; un avatar remoto nulo conserva esa foto, conforme al comportamiento de referencia.

La copia de la apariencia anterior se realiza una sola vez. Si falla, se conservan los datos originales y se permite reintentar. Una foto eliminada explícitamente no reaparece al reiniciar. El selector permite cargar una foto con el selector de Fotos de iOS, verla antes de guardar o volver al avatar predeterminado. Las lecturas durante el dibujo usan la caché; la carga desde almacenamiento se realiza al preparar el perfil.

La [validación conjunta 39172205813](https://github.com/Said129/harbor/actions/runs/39172205813), que congela la aplicación `4ff6de8e85283bd2145ef4c204bfb03f675f8f61`, compiló y aprobó los 25 casos de modelos nuevos, corregidos o afectados. Su resultado canónico y su árbol original de Xcode se conservan junto a los 51 casos anteriores de partes intactas. También aprobó el recorrido de idiomas de iPhone: se revisaron las cuatro capturas originales en francés, japonés, árabe y español, conservando el nombre personal y la dirección de lectura. No se introdujeron advertencias nuevas.

La ejecución completa terminó con un fallo en el recorrido de perfiles de iPhone al intentar escribir sin foco de teclado después de pulsar el borde del campo de nombre. La captura del selector es una revisión parcial, no una aprobación de ese recorrido. Los dos recorridos de iPad no llegaron a ejecutarse. Se conservan los 26 casos aprobados y quedan tres recorridos pendientes, sin repetir los modelos aprobados. La zona completa del campo de nombre pasa a solicitar foco explícitamente y la prueba exige que aparezca el teclado antes de escribir; **esta reparación aún necesita ejecución**. Esta integración no completa por sí sola la sincronización de todos los perfiles, sus espacios de datos y sus ajustes, ni cambia el criterio de entrega de una única IPA final.

La revisión del arranque bloqueado detectó además que el selector podía desaparecer en cuanto se aceptaba el PIN, antes de terminar de enlazar las cuentas y los datos personales. Ahora permanece visible durante toda esa operación; el selector de arranque utiliza el mismo idioma y dirección de lectura que el presentado desde Cuenta. Dos recorridos nuevos de interfaz, todavía sin ejecutar, comprueban creación, avatar, nombre compartido entre editores, PIN incorrecto, desbloqueo y persistencia tras reiniciar en iPhone e iPad. Las comprobaciones de idiomas se adaptan a la identidad normal: el nombre personal debe conservarse al cambiar el idioma de la interfaz. Una lectura inicial fallida de la apariencia antigua puede reintentarse; una apariencia ya migrada no depende de volver a leer esa copia anterior. El selector de Fotos del sistema y la revisión completa del movimiento todavía requieren comprobación.

## Inicio y perfil predeterminado en preparación

Se añade a Cuenta la configuración de inicio de Desktop: cada inicio, cada 15 o 30 minutos y nunca, además de un perfil predeterminado sin PIN. Los ajustes de inicio pertenecen al documento compartido del hogar incluso cuando el perfil activo tiene preferencias independientes. El reloj de selección permanece local; aceptar un perfil predeterminado o cerrar el selector no reinicia ese reloj ni permite eludir un PIN. Los avisos de regreso se posponen mientras hay reproducción o una presentación del sistema abierta.

Los ocho casos nuevos de modelos de inicio pasaron junto a los tres de agrupación de episodios en la [ejecución 39229215940](https://github.com/Said129/harbor/actions/runs/39229215940): once casos reales, ninguno fallido ni omitido y ninguna advertencia nueva. El árbol original de Xcode y los registros autenticados se conservan; no se repiten para comprobar las vistas. El comando obligatorio `pnpm run check` no admite estos archivos Swift y termina sin archivos compatibles; no se presenta como una comprobación aprobada de Swift.

La [ejecución de interfaz 39233004336](https://github.com/Said129/harbor/actions/runs/39233004336), fuente de automatización `c6793804c5abf25538c24a826e5fa5e5b7aca40e`, conservó exactamente la aplicación y los casos `7ec9a586e571d2ee6c42accc0bfeb1e56aa95b24`. Confirmó la corrección del foco del nombre dentro del primer recorrido, pero este falló al localizar la entrada de PIN: el identificador del contenedor sobrescribía los identificadores de sus controles. Ningún caso completo de esa ejecución aprobó; los otros doce quedaron sin ejecutar. Se conservan el registro, la jerarquía de accesibilidad, la imagen original y las grabaciones.

El arreglo `c81bd5c8503e31f2bec973e70c2dfb23eedb4259` retira únicamente ese identificador del contenedor del PIN. La [validación corregida 39237920401](https://github.com/Said129/harbor/actions/runs/39237920401), automatización `a7ca4e128e7fc5226cdbca03f3131fa1d77aebd0`, vuelve a seleccionar los nueve recorridos pendientes y cuatro preparaciones necesarias, conservando los modelos aprobados y los idiomas de iPhone ya aprobados. Si un grupo falla, guarda sus originales e intenta los grupos de otros dispositivos que sean independientes. **Los resultados corregidos, las cuarenta capturas previstas y las grabaciones siguen pendientes; no son una aprobación de interfaz ni una IPA.**

La primera selección de TVDB compiló la aplicación, pero no ejecutó ningún caso porque el destino de integración no pertenece al esquema de modelos. La [validación corregida 39239642918](https://github.com/Said129/harbor/actions/runs/39239642918), fuente `c6acef10ef54943f6c6cf6a82c127f7fd0f38228`, selecciona los seis modelos en `Harbor` y la única consulta pública en `HarborLive`. Sus dos árboles de resultados se autentican por separado; también se conservan los resultados parciales si algo falla. El cliente y los siete casos de TVDB no cambiaron con esta reparación de automatización. Su aprobación de ejecución sigue pendiente.
