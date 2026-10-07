# Revisión física de la IPA 42

El usuario revisó la última IPA de Descargas, cuyo informe identifica la fuente 42 (`5f1f556dd554a55c3be68adc525241ebbc910028`). Sus nueve fotografías y su mensaje del 7 de octubre añaden requisitos concretos. Ningún resultado de simulator certifica automáticamente estas correcciones físicas.

## Fuente 44: correcciones preparadas

- El gesto de ajustar/llenar el vídeo conserva los comandos reales de mpv y elimina el aviso sobre el formato.
- Continuar viendo conserva los destinos de reanudar desde la imagen y abrir la ficha desde el título de 43. Su imagen incluye ahora una superficie independiente que recibe el toque; las capas decorativas no lo interceptan.
- Los planes de catálogo cuyo título/nombre/ID es TorBox se excluyen antes de las solicitudes. El proveedor permanece instalado y sigue sirviendo fuentes; sus otros catálogos permanecen disponibles. Los planes antiguos también se excluyen del estado de Home y de la personalización.
- Submanhwa abre su portada y conserva el mismo WKWebView por propietario, con el almacén persistente separado que ya existía. Al volver no fuerza una navegación a `/entrar`. Se eliminan la cabecera añadida, las pestañas Cuenta/Leer/Gacha y el texto que afirmaba conservar la sesión. La navegación y los diálogos del propio sitio siguen disponibles; los enlaces que abren otra ventana se cargan dentro de este navegador. Debe comprobarse el acceso real y su duración tras reiniciar la aplicación.
- El color de la barra se elige entre los diez valores originales de `seek-bar-section.tsx` o con un color personalizado, se guarda y se aplica sólo al control real de búsqueda del reproductor. El usuario accede desde Vídeo y Apariencia.
- Guardar, favorito y visto mantienen sus operaciones reales. Tras una operación correcta muestran la etiqueta de la acción y una transición corta, adaptada a toque y a Reducir movimiento. No muestran éxito antes de guardar ni sustituyen los errores.
- El cargador incorpora el JSON original `harbor-loader.json` y el runtime MIT de lottie-web 5.13.0. La reproducción usa la animación SVG local, el fondo y logo reales y Conectando/Cancelar; no necesita red para animar ni servicios adicionales. Se añade una comprobación Apple de dibujo y avance del frame real.
- Calendario usa los nombres españoles de mes/día manteniendo el calendario y zona horaria del dispositivo. La ficha adopta la placa de título/logo, botones de 48 puntos, tipografía de sinopsis, créditos antes del reparto y campos informativos originales. Los títulos de filas mantienen los nombres del proveedor; su tipo se muestra debajo, sin inventar un título compuesto.

Estas son modificaciones de fuente. La compilación Apple, la revisión de sus imágenes y la prueba física siguen pendientes antes de declararlas resueltas en una IPA.

## Requisitos que siguen abiertos

- Anime: Top Picks for You, Top 100 on AniList, Award Winning Anime y las demás filas de la referencia, con datos reales y destinos de ficha utilizables. La implementación actual depende principalmente de los catálogos de addons.
- Discover: reemplazar el selector/cuadrícula genéricos por Recommended, carrusel, Browse your catalogs, Where to today?, Trending This Week, Browse by Genre, Top Rated, Your Discovery Queue y Award Winning de beta 0.9.130.
- Revisar los textos introducidos en las pantallas y usar las etiquetas/descripciones oficiales, traducidas sin añadir frases promocionales. Conservar mensajes necesarios de error o recuperación de operaciones nativas.
- Perfil PC/iPhone en ambos sentidos: beta 0.9.130 contiene `/identity/api/login`, la identidad Harbor y el protocolo revisionado de roster/perfil. Stremio y el nombre/avatar locales de iPhone todavía no implementan ese protocolo. Añadir el acceso Harbor real y la sincronización de identidad/perfil correspondiente, preservando las revisiones y los perfiles del servidor. No sustituirla con un nombre local igual ni escribir un roster vacío.
- Comprobar en el iPhone del usuario Continuar viendo, acceso persistente de Submanhwa y vídeo/ajustes después de instalar la fuente corregida con la misma identidad de firma.

La nueva lista conserva el objetivo móvil acordado y el trabajo previo. Ninguno de estos puntos se considera completo por estar enumerado aquí.

## Fuente 45/46: implementación y evidencia actualizadas

La fuente 45 añadió las filas reales AniList/MAL/premios, la composición inicial de Discover y acceso/sincronización Harbor mediante el protocolo revisionado de perfiles. Sus cuatro pruebas nuevas de roster preservan perfiles ajenos y conflictos de revisión; no equivalen a una sesión privada PC/iPhone comprobada. El [run 37670786042](https://github.com/Said129/harbor/actions/runs/37670786042) falló en compilación en dos asignaciones de Discover, antes de ejecutar esas pruebas.

La candidata 46 corrige esos errores y los avisos de firmas WebKit mediante delegados async. Adapta AnimeHero y PeekHero por separado, conserva los títulos/logos cuando una imagen no responde, incluye Top Picks en el hero y Seguir viendo en Anime y Continúa donde lo dejaste en Series, usando el estado de biblioteca existente. Las recomendaciones se recalculan al cambiar el historial. El arte procede del índice original, cotejado después de formatear su JSON, con actualizaciones del endpoint original. Se añade Sorpréndeme con una elección real sin repetir consecutivamente el mismo título. El selector de Discover reconoce los catálogos de Anime que declaran el tipo series. Biblioteca elimina dos explicaciones añadidas que no procedían de Desktop.

La animación original necesita un controlador separado: `goToAndStop` pausa el reloj de Lottie y no puede sustituir el método que regula el reloj nativo. Se elimina la modificación del contador público y se exige que cambie el SVG realmente dibujado. Reducir movimiento debe detenerlo en el frame original cero. El recorrido público existente recogerá Anime, sus filas Top 100/premios, Series y Discover, y comprobará que Sorpréndeme abre una ficha real.

Estos son cambios de fuente pendientes del gate Apple y de la revisión de capturas. Descargas contiene la IPA 43 comprobada, no 44/45/46. El perfil privado PC/iPhone, la sesión Submanhwa y las tarjetas personales de progreso siguen pendientes de comprobación con la cuenta del usuario.

## Candidata 47

La siguiente fuente añade la línea del tiempo con la geometría original y arrastre táctil, y ajusta la agrupación de Biblioteca a ventanas móviles de 1/7/30 días. El color personalizado aparece también en el punto del control. Discover incorpora el logo dentro del carrusel, flechas, indicadores y el panel original de imágenes ampliables, datos y sinopsis; usa textos del diccionario español original sin cambiar los parámetros del proveedor. Los votos y la lógica completa de clasificación de Desktop conservan trabajo pendiente.

Manga incluye las tres tarjetas Colecciones/Universos/Biblioteca y sus destinos. Las seis selecciones editoriales y treinta universos provienen de la referencia; los títulos se buscan en las fuentes reales permitidas por los filtros o la biblioteca local. Se mantienen los carruseles de 9/7 segundos y los ajustes de Reducir movimiento. El recorrido UI existente añade las dos subpáginas y comprueba el encabezado real de Biblioteca. La compilación, las imágenes de estas nuevas pantallas y el funcionamiento con el servidor personal todavía no están verificados.

## Candidata 48

Discover incorpora los votos originales y su respuesta táctil, pista inicial descartable y clasificación según las reglas originales aplicables al pool nativo. Guarda antes de mostrar el cambio y conserva aislamiento de cuentas, eventos recientes, exclusiones y datos anteriores cuando una escritura falla. Los parámetros de género del proveedor vuelven a sus valores originales; se traduce sólo lo visible. Se retiran las dos explicaciones añadidas de Ajustes y la etiqueta de «Mejor valorado» aplicada a cualquier título. Los iconos/textos/reglas de origen quedan registrados, sin afirmar que estén integrados todos los proveedores del algoritmo Desktop.

La build 46 no generó una IPA: terminó con tres asignaciones erróneas en los catch de sincronización de perfil. La fuente 47 corrige esas líneas y conserva todos los incrementos de interfaz; su comprobación Apple continúa. Los votos/caché de arte de 48 son locales por ahora. Descargas sigue conteniendo la IPA 43 comprobada.
