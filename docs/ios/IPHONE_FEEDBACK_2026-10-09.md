# Correcciones y añadidos para la única IPA final, 9 de octubre de 2026

El propietario pide bloquear la publicidad al navegar dentro de Submanhwa. Este añadido se incorpora a la única IPA final solicitada junto con las correcciones anteriores. La build 84 entregada no incluye estos cambios; no se inicia una compilación ni se genera una IPA intermedia.

## Implementación

- `SubmanhwaAdBlocker` compila reglas de contenido nativas de WebKit y las instala antes de cargar la primera página. Bloquea solicitudes a redes publicitarias conocidas y oculta contenedores de anuncios específicos de Submanhwa.
- La inspección de la página pública, sin cuenta ni cookies privadas, identificó solicitudes de `jads.co` y `juicyads.com`, un popunder a `massive-hall.com` y los contenedores `.home-ad`, `.home-ad-label`, `.ads-large`, `.ads-sqre1` y `.ads-sqre2`. No se ejecutaron los scripts de publicidad.
- Las ventanas de la propia web conservan su navegación en el navegador integrado. Los enlaces externos pulsados explícitamente siguen permitidos, salvo los dominios publicitarios bloqueados. Las ventanas externas abiertas por scripts se rechazan.
- Se conserva `WKWebsiteDataStore` persistente e independiente por cuenta. El bloqueo no borra cookies, almacenamiento ni credenciales. No se añaden cabeceras, pestañas, avisos ni contadores de publicidad a la interfaz.

La implementación utiliza [WKContentRuleList](https://developer.apple.com/documentation/webkit/wkcontentrulelist), [WKContentRuleListStore](https://developer.apple.com/documentation/webkit/wkcontentruleliststore) y el [formato de reglas de contenido de WebKit](https://webkit.org/blog/3476/content-blockers-first-look/). Se filtran dominios publicitarios concretos; no se bloquean indiscriminadamente todos los recursos externos que necesita la web.

## Comprobación y límites

`SubmanhwaAdBlockerTests` prepara una comprobación de las reglas reales en WebKit con HTML local: anuncios ocultos, imagen de lectura intacta, formulario y almacenamiento disponibles, JavaScript del sitio activo y estilos limitados al dominio de Submanhwa. Otra prueba comprueba límites de dominio, ventanas no solicitadas y enlaces explícitos. Son fixtures locales: no acreditan un inicio de sesión privado, lectura de capítulos reales ni giros de Gacha.

Las pruebas nativas están pendientes de la validación Apple de la entrega final. Este equipo Windows no dispone de Swift/Xcode y la instrucción del propietario descarta compilaciones intermedias. Las comprobaciones locales de repositorio no sustituyen esa validación.

Comprobación local: `pnpm run check --no-error-on-unmatched-pattern` sobre los tres archivos Swift y estos tres documentos terminó correctamente para los documentos compatibles; la herramienta no analiza Swift. `git diff --check` no detectó errores de espacios. No se modificaron TypeScript ni Rust en este incremento.

El filtro incluye las redes observadas y otras redes publicitarias conocidas. No garantiza bloquear todos los anuncios: el sitio puede cambiar de proveedor o servir publicidad desde sus propios dominios. Cualquier ajuste futuro debe conservar la lectura y el acceso a la cuenta.

## Reproductor: incremento conservado para la misma entrega final

La petición anterior añade estos fallos físicos y comportamientos. La fuente abierta los aborda sin recompilar la IPA:

- PiP: registrar AVKit durante la inicialización del reproductor, conservar el controlador durante los cambios de renderer y producir el primer frame aunque el vídeo esté pausado. Esperar la posibilidad y activación reales de AVKit, registrar su fallo y restaurar una sola salida inline; un fallo de preparación opcional no impide la reproducción normal.
- Giro: solicitar horizontal al conectar la presentación a su ventana, antes de terminar la transición. Mantener la orientación durante la conexión, reproducción y cambios de episodio; restaurarla al cerrar la última presentación. El cargador original aparece en horizontal, con espacio reservado para Cancelar y un título de respaldo si el logo no carga.
- Episodios: título, miniatura y descripción activan el episodio; visto, revelar spoilers y desplegar información conservan acciones separadas. Cancelar la selección automática conserva la lista de fuentes y evita que una resolución anterior presente después un vídeo.
- Fuentes: añadir Cambiar fuente a los controles habituales y conservar el punto de reproducción real al volver a elegir un enlace.
- Retroceso: usar búsqueda relativa exacta de mpv y objetivos táctiles de 44 puntos, sin estimar el tiempo desde la interfaz.
- Reanudación: sustituir los diálogos genéricos por el panel Harbor original. Cargar en pausa, esperar la elección del usuario, buscar al punto real y evitar guardar progreso o avanzar de episodio mientras siga abierto. Volver al principio cerca del final conserva un checkpoint real de cero.

`PlaybackControlTests` prepara comprobaciones de mpv pausado/reanudación/avance/retroceso, activación real de PiP y restauración de orientación con presentaciones solapadas. Siguen pendientes del gate Apple final. El simulador no acredita por sí solo el giro con bloqueo físico ni el comportamiento PiP en el iPhone del propietario. No se presentan estos fallos como resueltos en la build 84.

## Discover: cola y composición original

La entrada usa la composición de `discovery-queue-cta.tsx`: seis fondos reales, degradado, Explore con la flecha original y contador. El carrusel Recomendado conserva su panel lateral en horizontal y lo sitúa debajo en vertical. Las etiquetas de catálogos, viajes, géneros, recomendaciones y acciones se resuelven desde los textos oficiales, sin añadir titulares propios.

La cola sustituye `CinemaHero` por la composición específica de `queue.tsx` y `feed-hero.tsx`: posición, Ver detalles, título y metadata reales, Reproducir ahora/Guardar/Omitir/No me interesa, flechas y tira horizontal de 200 puntos. Los controles se distribuyen en filas para caber en iPhone. El icono Tide Info se copia sin modificar; Guardar, Omitir y el pulgar invertido reutilizan los glifos Harbor originales. La etiqueta refleja el tipo real de contenido, sin atribuirle una fuente de tendencias no consultada.

Omitir oculta la selección durante 14 días. No me interesa conserva la exclusión entre aperturas. Ambas preferencias se guardan por cuenta antes de quitar el título de la interfaz, preservando los votos anteriores y los almacenes que todavía no tenían estos campos. Si falla la escritura, el título se mantiene. Los catálogos de historial se excluyen de las recomendaciones y la cola. El cambio de cuenta invalida resultados de metadata anteriores y cierra la cola de la cuenta previa.

Se preparan dos pruebas nativas de migración, persistencia, caducidad, aislamiento y conservación de datos dañados. El recorrido UI nuevo abre la cola con catálogos públicos reales, omite un título y abre la ficha siguiente. No se han ejecutado: forman parte de la validación completa de la entrega final. `beta-vector-provenance.json` registra los archivos de referencia y hashes del activo y las traducciones.

Comprobación local del incremento conservado: `pnpm run check --no-error-on-unmatched-pattern` pasó para los once documentos, catálogos de activos y archivos JSON modificados. Se verificaron los hashes de las tres referencias de la cola y su icono, la copia exacta de Tide Info y los archivos de los cinco catálogos nuevos. Se corrigió una línea vacía sobrante al final de Discover; después `git diff --check` pasó. Estas comprobaciones no analizan ni ejecutan Swift y no certifican los recorridos privados.
