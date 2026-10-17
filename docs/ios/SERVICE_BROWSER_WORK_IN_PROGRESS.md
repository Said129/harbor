# Navegador de servicios — integración en curso

La referencia es Desktop 0.9.132, `src/views/service.tsx`, sus vistas móviles y `src/lib/providers/service-catalog.ts`. Este trabajo completa el navegador que abre cada proveedor desde las filas existentes y añade una entrada «Explorar servicios» desde sus ajustes. Todavía no está compilado ni validado en Apple. No crea una IPA intermedia.

La interfaz usa los 27 logotipos originales, el color de cada marca, la región configurada, 14 categorías y un selector flotante. «Todo» presenta Top 10 y más películas/series; cada filtro presenta su cuadrícula. Incluye acceso real a los ajustes de metadatos si falta una clave, reintento, carga progresiva y volver arriba. Los tres mensajes móviles nuevos están traducidos a los 16 idiomas admitidos.

Las consultas completas incluyen suscripción, contenido gratuito y anuncios, sin heredar el mínimo de votos del resumen del inicio. Los géneros de películas y televisión se distinguen donde lo hace Desktop. Se conservan hasta 200 títulos con portada por tipo y se descartan duplicados. Hay dos peticiones simultáneas como máximo por carga. Las páginas de cada tipo avanzan únicamente tras una respuesta correcta; un fallo conserva los títulos que sí llegaron y permite reintentar la página pendiente. Las respuestas de un propietario, filtro o configuración anteriores se descartan.

La geometría predeterminada del logotipo en la guía y los ajustes se mantiene: altura 22, anchura máxima 110 y margen horizontal 12. Las medidas mayores solo se usan en el navegador nuevo. El resto de descubrimiento conserva su cuadrícula y su paginación originales.

Las entradas usan el desplazamiento y fundido de 0,32 segundos de la referencia móvil (16 puntos en el índice y 14 en el catálogo), con su curva original `cubic-bezier(0.16, 1, 0.3, 1)`. Las tarjetas responden con escala 0,96, y la categoría elegida desde el menú se desplaza hasta quedar visible. La carga inicial presenta 18 espacios de portada con pulso; «Reducir movimiento» y el paso a segundo plano lo desactivan. Una página repetida se deduplica y permite continuar a páginas posteriores. Estas animaciones aún requieren revisión en Apple.

Se prepararon cinco métodos de modelo y dos recorridos reales de interfaz (iPhone/iPad). Cubren parámetros de catálogo, categorías incompatibles con un tipo, límite y orden de páginas, concurrencia, respuesta tardía de otro propietario, reintento parcial y cambio de categoría. Los recorridos abren el índice de proveedores, un catálogo sin clave, un filtro y el editor real de metadatos. La carga con una clave personal y la revisión de las capturas aún no están demostradas. No se presenta una interfaz sin datos como prueba de consulta real a TMDB.

La validación preparada ejecutará esos siete métodos, guardará seis capturas y dos grabaciones de los recorridos para revisar los estados y movimientos reales. Conservará los resultados del asistente inicial únicamente cuando su ejecución haya terminado con éxito. No repetirá las pruebas anteriores de áreas intactas.

El navegador y su sincronización se comprobarán juntos en `services-complete`: 24 ejecuciones afectadas, diez capturas y dos grabaciones, con una sola compilación. Los siete casos del navegador forman parte de ese total. Las dos revisiones de código intermedias se etiquetan como revisiones de fuente; no se presentan como ejecuciones previas aprobadas. La referencia validada que se conserva es el asistente inicial.

El mosaico específico de servicios y toda su personalización dentro del inicio de Desktop siguen pendientes del bloque de inicio y sincronización. Este navegador no completa por sí solo el port 1:1 ni la sincronización de todos los ajustes.
