# Objetivo vigente: Harbor para iPhone

Actualizado por petición del propietario el 2026-10-06. Este alcance sustituye la obligación anterior de portar todas las opciones adaptables de Desktop. La referencia visual sigue siendo Harbor Desktop beta 0.9.130; el checkpoint público 0.9.128 y sus diferencias siguen documentados.

Crear un Harbor nativo para iPhone fiel a la identidad, los iconos y las interfaces originales, con las funciones principales, todo lo esencial y una selección amplia de configuraciones útiles en móvil. La fidelidad 1:1 se aplica a las funciones seleccionadas, adaptando su interacción a pantalla táctil. La aplicación no necesita reproducir cada herramienta avanzada de Desktop.

## Conservar y terminar el trabajo empezado

Conservar todo lo ya implementado, incluidos Música, eBook, Manga, Live TV/VOD, Deportes, calendarios, colecciones y personalización. No retirar pantallas, opciones, activos ni datos para reducir el alcance. Terminar y corregir los incrementos nativos ya empezados, incluida la importación y los filtros de subtítulos que están en el árbol de trabajo.

La instantánea [mobile-scope.json](mobile-scope.json) registra las entradas que tienen implementación parcial y los archivos del incremento abierto. Preservar una función parcial significa cerrar su recorrido ya empezado y sus fallos, no incorporar automáticamente todas las subfunciones Desktop todavía sin empezar. Las investigaciones de referencias se conservan, pero una entrada marcada Investigating sin cliente nativo implementado no convierte todas sus variantes en un requisito nuevo.

## Prioridades del trabajo restante

1. **Cuenta y addons:** acceso con la cuenta habitual, recuperación de addons configurados, orden y preferencias; instalación, configuración, activación y eliminación; errores comprensibles sin perder datos.
2. **Navegación y contenido:** Home y secciones directas, catálogos, búsqueda, imágenes y ficha, temporadas y episodios. Mantener la identidad original, tamaños legibles y navegación táctil; cerrar fallos de imágenes, carga y resultados parciales.
3. **Reproducción:** vídeo y audio reales, ocultación de controles, pausa, avance, reanudación, cambio de enlace, pistas de audio y subtítulos, idiomas, desfases, aspecto/ajuste a pantalla y siguiente episodio. Priorizar estabilidad, ciclo de vida de iOS y funciones útiles en móvil como PiP y AirPlay según soporte comprobado.
4. **Biblioteca y continuidad:** favoritos, pendientes, vistos, progreso local/cloud, continuar viendo y episodios, manteniendo cuentas y datos aislados.
5. **Configuración móvil:** idioma y apariencia, temas e iconos, preferencias de audio/subtítulos, reproducción automática, reanudación, pasos de avance, límites razonables de caché/red, filtros de contenido y spoilers, addons y gestión de archivos/almacenamiento. Conservar además todos los ajustes que ya tengan implementación.
6. **Funciones ya iniciadas:** completar los recorridos actuales de descargas, TV/VOD, Música, lectores, Deportes, calendarios, colecciones y personalización sin expandir cada sección a todo su catálogo de herramientas Desktop.
7. **Compatibilidad necesaria:** resolver las fuentes y formatos que requiere el recorrido principal con los addons del usuario. Un servidor remoto o servicio opcional debe ser explícito; la existencia de cinco clientes Debrid en Desktop no obliga a implementar sus cinco bibliotecas y paneles avanzados antes de entregar móvil.

## Opciones que dejan de ser obligatorias

Para funciones aún sin empezar, no perseguir paridad con selección de GPU/renderers de PC, ventanas múltiples y tray, hotkeys/gamepads de Desktop, sidecars y scripts de shell, SVP/RTX, editores de código de temas/CSS/JS/HTML, motores arbitrarios de plugins, webhooks/administración remota, estudios de grabación/GIF/DVR o herramientas avanzadas de diagnóstico. Otras funciones amplias aún sin empezar, como todas las integraciones sociales/AI, proveedores de metadata, paneles Debrid, estadísticas y editores avanzados, quedan opcionales salvo que sean necesarias para una prioridad móvil concreta.

Esta decisión es de alcance del producto, no una afirmación de que iOS prohíbe esas funciones. Ninguna exclusión retira una implementación existente o un incremento nativo abierto. No añadir controles sin efecto para imitar Desktop.

## Entrega y criterio de finalización

El objetivo termina cuando funcionan los recorridos prioritarios, se cierran los incrementos nativos empezados, la interfaz móvil y los activos originales son coherentes, y una IPA verificable queda en Descargas con instrucciones de instalación y limitaciones concretas. La evidencia de build, servicios, reproducción y dispositivo se mantiene en [VALIDATION.md](VALIDATION.md); compilar no certifica por sí solo el funcionamiento físico.

Hacer comprobaciones proporcionadas a cada cambio: implementar, verificar el recorrido afectado, solucionar el fallo si aparece y continuar. Mantener las comprobaciones de entrega de vídeo real, servicios, interfaz, dispositivo y paquete; evitar repetir pruebas amplias cuando no haya cambios o fallos que lo justifiquen.

El 9 de octubre el propietario restableció el proceso habitual para las próximas entregas: validación completa con `validation_scope=full`, servicios públicos y recorrido UI activados, además de compilación y paquete para iPhone. La validación reducida de la build 84 fue una excepción para dos fallos ya identificados tras varias pruebas generales; no es la política para las entregas siguientes. No repetir la build 84 ya entregada sólo por este cambio de proceso.

El inventario completo de Desktop permanece como referencia y conserva sus estados reales. Sus 859 entradas no son una lista obligatoria de entrega ni el denominador del nuevo porcentaje de avance. Medir el progreso del objetivo móvil por los recorridos anteriores y su evidencia, sin convertir opciones excluidas en funciones terminadas.

Mantener la IPA anterior hasta que una nueva pase sus comprobaciones. Continuar sin contratar servicios, planes o runners de pago ni alterar facturación. El cambio de alcance no declara terminado el trabajo.

## Referencias y requisitos añadidos el 6 de octubre

La petición posterior conserva el alcance móvil esencial y exige máxima fidelidad en las pantallas elegidas. Referencias: las capturas Desktop de `2026.10.06-20.25` a `20.45`, las cuatro de `20.54` y `20.57_1`, en la carpeta Radeon ReLive del usuario. La IPA 24 no cumple todavía esa fidelidad; la 29 entregada contiene mejoras funcionales anteriores, no estos cambios nuevos.

- Perfil/cuenta: estructura Harbor, avatar original/foto/nombre/color, con controles reales y datos aislados por cuenta.
- Catálogos: búsqueda, filtros de tipo y addon, agrupación por proveedor, carteles y personalización. Las categorías directas no repiten el título bajo la cabecera Harbor.
- Fichas de películas/series/anime: hero/logo/datos/acciones, sinopsis, episodios, reparto, información y recomendaciones reales cuando las fuentes las proporcionan. No inventar datos ni mostrar acciones sin implementación.
- Calendario: cabecera, mes/anterior/siguiente/Hoy, celdas y eventos, inicio de semana y tamaño; fuentes adicionales sólo con datos reales.
- Manga: hero, biblioteca, búsqueda y filtros de extensiones/idiomas, manteniendo Suwayomi y archivos locales.
- Biblioteca: reproducir la cabecera y pestañas, contadores, búsqueda, filtros, orden y agrupación por fechas de la captura `2026.10.06-21.06.png`, con títulos y progreso reales.
- Corregir el fallo físico comunicado: los carteles de búsqueda y el resto de listados deben abrir su ficha al tocar la imagen.
- Continuar viendo y posición PC/iPhone usando la misma cuenta: leer/escribir progreso real y refrescar al volver al primer plano, sin mezclar cuentas.
- Reproducción: siguiente episodio, fuente automática según calidad/filtros configurados, idiomas de audio/subtítulos por prioridad, segunda pista, exclusión CAM/TS y controles/paneles Harbor. Añadir pellizco para adaptar/llenar; conservar el ajuste manual de zoom.
- Campañas: actualización de contenido con datos oficiales compatibles y respaldo válido. Una actualización de código de la IPA firmada requiere reinstalación/firma; no prometer instalación silenciosa.
- Submanhwa: acceso a la cuenta del sitio, lectura y sección Gacha/Mudae desde Harbor. Sesión del sitio persistente y aislada por cuenta; no ejecutar giros, compras o mensajes en nombre del usuario.

Registrar implementación y evidencia por recorrido; esta lista nueva no declara terminadas las funciones existentes.
