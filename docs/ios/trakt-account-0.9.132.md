# Trakt: conexión y continuidad

Referencia Desktop: `0834340cec5531650bfe78cd628628702e636987` (0.9.132).
Este incremento pertenece al port completo y a su única IPA final. Está
implementado y pendiente de compilar y ejecutar en Apple; no completa Trakt.

## Comportamiento implementado

- Conexión por código, copia temporal local, cancelación, caducidad, denegación,
  espera progresiva y nombre opcional. La autorización se guarda en el llavero
  del propietario antes de publicarse; un cambio de perfil descarta la respuesta.
- Renovación de sesión compartida entre peticiones concurrentes. Si el proveedor
  ya rotó el token al abandonar el perfil, se conserva solo en la misma cuenta
  que inició la petición. Desconectar o sustituir la cuenta impide restaurarla.
  Un fallo temporal no borra la sesión guardada.
- Importación de los últimos cuarenta progresos, deduplicación, identificadores
  y coordenadas de la referencia. Se conserva el porcentaje real y la fecha del
  proveedor para reanudar con la duración efectiva sin anular descartes recientes.
- Fuente desactivada por defecto, distintivo Trakt y combinación con la biblioteca
  y Simkl. No crea marcadores ni consulta la cuenta Stremio. La historia privada
  excluye el progreso compartido; desactivar o cambiar el propietario retira las
  tarjetas inmediatamente. Caché de cinco minutos y treinta segundos al regresar,
  con reintentos acotados que conservan las tarjetas si falla la red.
- Peticiones JSON limitadas a ocho MiB, sin cookies ni redirecciones. El token
  Bearer solo viaja a la API Trakt; la renovación requiere el refresh token en
  el proxy comunitario. Se repara el origen retirado de la referencia usando
  `harborcommunity.site`. Una respuesta pública 405 no demuestra un acceso
  personal correcto; esa conexión no está certificada todavía.

## Evidencia y comprobación seleccionada

Se ejecutaron los módulos originales de conversión de progreso y autorización
con transportes controlados: 28 casos de progreso y siete de autorización, sin
peticiones a proveedores. La fixture conserva también los hashes de configuración
y cliente; incluir sus hashes no afirma haber ejecutado esos dos módulos.

La selección Apple contiene diez casos nativos nuevos y dos combinaciones
afectadas de Simkl e historia privada. Incluye montajes reales de ajustes,
autorización pendiente/denegada y tarjeta con imagen decodificada en ambos tamaños.
Tres preparaciones de invitados propios permiten dos recorridos nuevos de fuente
Trakt en iPhone/iPad y el recorrido de privacidad de iPhone pendiente. Se esperan
18 ejecuciones y veinte imágenes originales como objetivo inicial.
La ejecución 40595901859 terminó con 17 aprobadas y un fallo al segundo arranque
de la app en el recorrido de privacidad de iPhone. Los doce casos nativos y los
dos recorridos de fuente Trakt pasaron; no se vuelven a seleccionar los intactos.
Se autenticaron y revisaron las 18 capturas obtenidas. Se detectó un recurso PNG
equivocado para el distintivo y textos de autorización sin traducir. Sus arreglos
se comprueban en la selección de reproducción siguiente. Las capturas de
privacidad restaurada/desbloqueada siguen pendientes.
Se conservan los aprobados intactos y no se repite el fallo de foco sin corregirlo.

## Pendientes conservados

Listas y su sincronización bidireccional, historial, recomendaciones y calendario.
El registro automático está implementado en el incremento siguiente y pendiente
de ejecución Apple; véase `trakt-scrobble-0.9.132.md`. Este incremento no sustituye esas
funciones por controles sin efecto ni declara el port completo, el rendimiento
físico o una IPA nueva como aprobados.
