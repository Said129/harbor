# Sistema e interfaces — integración en curso

Este trabajo pertenece a la única próxima IPA del port completo de Desktop **0.9.132** para iPhone/iPad. No autoriza una entrega intermedia ni completa la auditoría general. La estimación comunicada sigue siendo **aproximadamente 75 %**, provisional.

## Código incorporado, pendiente de Apple

- Almacenamiento: medir documentos, datos de Library, cachés y temporales dentro del contenedor. Evitar contar Caches dos veces, seguir enlaces simbólicos o bloquear el hilo de la interfaz. Medir al abrir la página.
- Imágenes: mostrar el uso real y vaciar las cachés de memoria y HTTP. Las peticiones anteriores pueden terminar para sus vistas, pero no rellenan la nueva caché ni eliminan una petición nueva de la misma imagen. Los libros, las descargas, los perfiles y el progreso no se borran.
- Acerca de: identidad de la build móvil y referencia Desktop, compatibilidad, avisos legales, repetir la guía y restaurar los consejos descartados. La guía conserva la configuración existente y su estado sobrevive al cierre.
- Navegación: los 16 archivos de vectores usados por `src/chrome/nav-items.tsx` se copian sin modificar sus fotogramas. Se activan al mantener pulsado un botón o al pasar el puntero, con un único ciclo salvo Shows mientras se interactúa. Se detienen al quedar inactivos o en segundo plano; el ajuste de iconos animados y Reducir movimiento conservan los iconos estáticos.

Los vectores y sus hashes están en [el manifiesto de animaciones](desktop-navigation-animations-0.9.132.json). El renderizador nativo Lottie 4.6.1 se fija al commit `0aff16288f8dc1e3dab35cbf5cf45979673fd3df`; SwiftPM verifica el hash de su artefacto publicado. La configuración mantiene iOS/iPadOS 17 y ambos tipos de dispositivo.

Los JSON originales de `DesktopAnimations/nav` se excluyen del formateador, igual que la animación original de carga: deben conservar exactamente los bytes cuyos hashes verifican las pruebas. Git conserva también sus finales de línea originales, incluido el vector de música. El resto del código y de los manifiestos sigue pasando por las comprobaciones habituales.

## Lo que esta integración todavía no demuestra

La guía móvil actual tiene cuatro páginas. Es una base para el recorrido: todavía falta trasladar y comparar las etapas configurables del onboarding Desktop (splash, idioma, bienvenida, diseño, TMDB, Stremio, servicios, subtítulos, gustos y final). Por tanto, no se marca como equivalencia completa del onboarding.

Tampoco se consideran completadas todas las animaciones por haber incorporado las de navegación. [El inventario visual de la referencia](desktop-visuals-0.9.132.json) conserva pendientes las interfaces, transiciones, vectores restantes y estados de cada sección compatible. Hace falta comparar recorridos y capturas en ambos tamaños, incluidos errores, carga, vacíos y Reducir movimiento.

## Validación afectada prevista

Doce métodos nativos nuevos comprueban el cálculo de espacio, cancelación y conservación de archivos; las descargas compartidas y el vaciado concurrente de imágenes; la migración y persistencia de la guía y sus consejos; variables de traducción; y los vectores originales y su movimiento. Dos recorridos de interfaz abren Almacenamiento y Acerca de, vacían imágenes, restauran consejos y repiten la guía en iPhone/iPad. Las capturas se revisan después de ejecutar las pruebas; su existencia no sustituye a esa revisión.

Se conservan los casos aprobados de funciones intactas mediante comparación de archivos y valores. La CI de esta integración usa `validation_only=true`: omite compilación de dispositivo, empaquetado y guardado de IPA. El resultado de Apple y la revisión visual aún están pendientes.

La ejecución de idiomas `39028548982`, fuente `c78569d6a1579b3cca2f4c736c5b66de7f96f119`, compiló y aprobó el método nativo que comprueba los 16 catálogos. Su prueba de interfaz falló después de pulsar Français: el arranque de la prueba fijaba `-uiLanguage es` en el dominio de argumentos, y la jerarquía capturada siguió mostrando Configuración/Español. Se elimina ese argumento de la prueba que cambia idiomas; no se modifica el funcionamiento del selector para ese diagnóstico. El método nativo aprobado se conserva con su resultado y fuente, mientras que el recorrido de idiomas de iPhone y el de iPad pendiente se ejecutan junto a los recorridos nuevos de sistema. El fallo original queda registrado y no se presenta como una ejecución aprobada.
