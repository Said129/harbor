# Regresión de rendimiento de la build 85

El propietario comunica lentitud general al entrar y navegar por la build 85, además de una espera larga al tocar la imagen de Continuar viendo. Indica que la IPA anterior era más fluida. Este informe físico invalida la suposición de que el recorrido UI de CI bastaba para acreditar fluidez con una biblioteca privada grande.

## Causa localizada y corrección preparada

La build 84 ordenaba la biblioteca por una cadena de fecha. La 85 corrigió la compatibilidad de fechas cloud y pasó a ordenar por `activityTimestamp`, pero lo calculaba creando formateadores ISO en cada comparación. `LibraryModel.items` repetía el parsing y el orden completo en cada consulta de SwiftUI. Las tarjetas nuevas también calculaban episodios/vistos en su cuerpo y descargaban metadata que la ficha volvía a solicitar antes de reproducir.

La candidata 86 conserva la semántica corregida de fechas numéricas/ISO, rewatch y siguiente episodio, con estos cambios:

- Preparar un snapshot inmutable de biblioteca en el actor de caché, al cargar o guardar datos. Identidad, metadata y fechas se calculan una vez; orden y lista de Continuar viendo quedan preparados fuera del hilo de interfaz.
- Reutilizar dos parsers ISO protegidos por un lock, incluidos los episodios, en lugar de construir formateadores por comparación. Los registros originales y campos desconocidos se conservan.
- Calcular la presentación de cada tarjeta cuando cambian sus datos, evitando descomprimir/ordenar episodios en cada actualización de su cuerpo.
- Compartir solicitudes y conservar metadata de Continuar viendo en memoria durante cinco minutos, con un máximo de 64 entradas y claves que separan cuenta, addons configurados y ajustes de metadata. No guardar credenciales en disco ni incluirlas en diagnósticos.
- Abrir la ficha/reproducción con la metadata ya cargada de la tarjeta, evitando otra petición obligatoria. Los datos faltantes siguen cargándose por el recorrido habitual.
- Evitar sincronizaciones de biblioteca simultáneas para la misma sesión y decodificar una vez el conjunto de vistos al comprobar una serie.

## Verificación

`LibraryPerformanceTests` compara el coste de ordenación de la 85 con el snapshot y cien lecturas, sobre 250 registros con fechas ISO. También comprueba actualización sin mutar datos anteriores, campos del proveedor, fechas ISO/numéricas, solicitudes compartidas, separación por cuenta/addons/idioma, reintento tras fallo y apertura de metadata ya preparada. La suite de continuidad existente conserva sus comprobaciones de capítulos y rewatch.

La validación Apple completa, el resultado numérico de rendimiento, la revisión visual y una nueva IPA están pendientes. Se conserva la entrega 85 y el respaldo 84 hasta que la candidata pase su validación. No se atribuye una medida física del iPhone a la comparación de CI.

Comprobaciones locales: formato de los documentos/YAML y `git diff --check` aprobados. `vp check` no analiza Swift; la validación nativa corresponde al gate Apple. La compilación Linux exigida por `AGENTS.md` se intentó y no pudo iniciar `cargo metadata` porque `cargo` no está instalado en este host Windows. No se modificaron TypeScript ni Rust.

El trabajo pesado fuera de `body` sigue las recomendaciones de [Apple sobre rendimiento SwiftUI](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) y [capacidad de respuesta](https://developer.apple.com/documentation/xcode/improving-app-responsiveness).
