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

El inventario completo de Desktop permanece como referencia y conserva sus estados reales. Sus 859 entradas no son una lista obligatoria de entrega ni el denominador del nuevo porcentaje de avance. Medir el progreso del objetivo móvil por los recorridos anteriores y su evidencia, sin convertir opciones excluidas en funciones terminadas.

Mantener la IPA anterior hasta que una nueva pase sus comprobaciones. Continuar sin contratar servicios, planes o runners de pago ni alterar facturación. El cambio de alcance no declara terminado el trabajo.
