# Regresión de rendimiento de la build 85

## Confirmación posterior del propietario

El propietario confirmó «funcionan bien los añadidos y los arreglos» antes de solicitar las mejoras de fuentes/búsqueda/subtítulos de la 87. Se registra su aceptación de los arreglos de la 86; no es una medición nueva de FPS ni una comprobación física de la 87.

El propietario comunica lentitud general al entrar y navegar por la build 85, además de una espera larga al tocar la imagen de Continuar viendo. Indica que la IPA anterior era más fluida. Este informe físico invalida la suposición de que el recorrido UI de CI bastaba para acreditar fluidez con una biblioteca privada grande.

Dispositivo comunicado por el propietario: iPhone 14, iOS 26.6.2. La versión se registra tal como la indica; el runner Apple no sustituye la comprobación en ese teléfono.

## Causa localizada y corrección preparada

La build 84 ordenaba la biblioteca por una cadena de fecha. La 85 corrigió la compatibilidad de fechas cloud y pasó a ordenar por `activityTimestamp`, pero lo calculaba creando formateadores ISO en cada comparación. `LibraryModel.items` repetía el parsing y el orden completo en cada consulta de SwiftUI. Las tarjetas nuevas también calculaban episodios/vistos en su cuerpo y descargaban metadata que la ficha volvía a solicitar antes de reproducir.

La candidata 86 conserva la semántica corregida de fechas numéricas/ISO, rewatch y siguiente episodio, con estos cambios:

- Preparar un snapshot inmutable de biblioteca en el actor de caché, al cargar o guardar datos. Identidad, metadata y fechas se calculan una vez; orden y lista de Continuar viendo quedan preparados fuera del hilo de interfaz.
- Reutilizar dos parsers ISO protegidos por un lock, incluidos los episodios, en lugar de construir formateadores por comparación. Los registros originales y campos desconocidos se conservan.
- Calcular la presentación de cada tarjeta cuando cambian sus datos, evitando descomprimir/ordenar episodios en cada actualización de su cuerpo.
- Compartir solicitudes y conservar metadata de Continuar viendo en memoria durante cinco minutos, con un máximo de 64 entradas y claves que separan cuenta, addons configurados y ajustes de metadata. No guardar credenciales en disco ni incluirlas en diagnósticos.
- Abrir la ficha/reproducción con la metadata ya cargada de la tarjeta, evitando otra petición obligatoria. Los datos faltantes siguen cargándose por el recorrido habitual.
- Si se toca una tarjeta antes de terminar su hidratación, la ficha se une a la petición compartida que ya está en curso, en lugar de iniciar otra descarga. Las fichas usan la misma caché acotada por cuenta/addons/configuración.
- Evitar sincronizaciones de biblioteca simultáneas para la misma sesión y decodificar una vez el conjunto de vistos al comprobar una serie.

## Verificación

`LibraryPerformanceTests` compara el coste de ordenación de la 85 con el snapshot y cien lecturas, sobre 250 registros con fechas ISO. También comprueba actualización sin mutar datos anteriores, campos del proveedor, fechas ISO/numéricas, solicitudes compartidas, separación por cuenta/addons/idioma, reintento tras fallo, apertura de metadata ya preparada y primer toque durante una descarga compartida todavía en curso. La suite de continuidad existente conserva sus comprobaciones de capítulos y rewatch.

La build 86 corrige la regresión de lentitud de la 85 y está entregada en `C:/Users/Said/Downloads/Harbor-unsigned.ipa`. Fuente de app `c3e3d28abc46b868417f655b4167394c2a48b22c`; [compilación arm64 38450204545](https://github.com/Said129/harbor/actions/runs/38450204545) aprobada. Por petición del propietario se conservan resultados aprobados del mismo código: 76 métodos y una omisión PiP del simulador, con los dos fallos de red de un intento posterior registrados por separado. Las tres pruebas UI de la 86 pasaron; se reutiliza la revisión visual previa para diseño/recursos sin cambios, sin afirmar que se revisaron capturas nuevas de la 86. La fluidez física en el iPhone 14 sigue pendiente de confirmación. Procedencia y límites en [DELIVERY_2026-10-13.md](DELIVERY_2026-10-13.md).

Comprobaciones locales: formato de los documentos/YAML y `git diff --check` aprobados. `vp check` no analiza Swift; la validación nativa corresponde al gate Apple. La compilación Linux exigida por `AGENTS.md` se intentó y no pudo iniciar `cargo metadata` porque `cargo` no está instalado en este host Windows. No se modificaron TypeScript ni Rust.

El trabajo pesado fuera de `body` sigue las recomendaciones de [Apple sobre rendimiento SwiftUI](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) y [capacidad de respuesta](https://developer.apple.com/documentation/xcode/improving-app-responsiveness).
