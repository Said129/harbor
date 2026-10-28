# Reproducción Trakt de la referencia 0.9.132

Referencia conservada: `0834340cec5531650bfe78cd628628702e636987`.
La ejecución Apple 40604874961 del commit
`e1367aeb8072860c05a87340ef285c26042a8411` compiló y completó 22 comprobaciones:
20 aprobadas y dos fallidas. No se ha generado otra IPA.

## Comportamiento

El reproductor envía inicio, pausa y final a la cuenta Trakt del perfil activo.
Mantiene el umbral de 150 segundos para descartar avances y muestras cortas,
la posición más avanzada, el final real y el umbral del 90 % al salir. Cambiar
de episodio termina la identidad anterior y espera el reinicio de carga antes
de iniciar la siguiente. Los saltos de posición resincronizan el inicio con el
límite de treinta segundos de Desktop. La entrega es secuencial y no bloquea
los controles de reproducción.

Un final fallido se reintenta una vez tras 800 ms; 409 confirma que ya estaba
registrado. Desde el 70 % se intenta la escritura de historial y, si hace falta,
la resolución de numeración del catálogo. Los especiales pueden resolverse como
película por título y año. Una respuesta HTTP correcta sin elementos añadidos o
existentes no confirma el historial. Un fallo de búsqueda sigue pendiente.

La cola guarda hasta cincuenta finales en el llavero, por propietario y conexión
Trakt. Una identidad durable de conexión sobrevive a renovar el token y reiniciar
la app; una nueva conexión no recibe la cola de la cuenta anterior. Confirmar una
petición antigua no borra un final más reciente del mismo título. Las respuestas
tardías de otro perfil o de una cuenta desconectada no continúan escribiendo.
No se usa ninguna cuenta Stremio. Desactivar la fila de progreso importado no
desactiva el registro de reproducción de una cuenta Trakt conectada.

## Comparación ejecutada y selección pendiente

Se ejecutaron sin red los siete módulos originales: `trakt/ids.ts`,
`trakt/scrobble.ts`, `trakt/history.ts`, `trakt/scrobble-hook.ts`,
`tracker-resolve/match.ts`, `tracker-resolve/resolve.ts` y `trakt/resolve.ts`.
La fixture conserva hashes, entradas y resultados: 17 identificadores, 77 cuerpos,
55 escrituras de historial, ocho secuencias de respuesta, catorce recorridos del
hook, diez coincidencias de especiales y siete rutas de resolución. El hook real
se ejecuta con un reloj y efectos React controlados; no se afirma haber ejecutado
el reproductor Desktop completo ni autorizado una cuenta personal.

Diez casos nativos nuevos comparan esos resultados y comprueban persistencia,
renovación, cola, respuestas retenidas y entrega del ciclo de reproducción. Se
seleccionan además seis casos afectados: cuatro de propiedad de la cuenta,
el texto de los dieciséis idiomas y el montaje de los componentes Trakt.

El montaje vuelve a comprobar únicamente los componentes visuales modificados:
se usa el SVG rojo original que importan `continue-card.tsx` y `trakt-panel.tsx`,
con SHA-256 `233a8e88af346e7573181d458421c869a7c7ea063514a1d733812145d5fb27ff`.
La autorización usa las claves y traducciones originales. La nota de servidor
Harbor tiene traducción propia en los dieciséis idiomas. Dos recorridos nuevos
comprueban esa nota en español e inglés en iPhone/iPad.

Se conserva pendiente el recorrido de privacidad de iPhone que falló al segundo
arranque, sin relajar las aserciones ni repetir automáticamente el arranque. Si
falla, se guardan registros del sistema y diagnósticos del simulador. La selección
completa suma 16 casos nativos, tres preparaciones y tres recorridos UI: 22
ejecuciones y 18 capturas previstas. Se obtuvieron las 18 capturas y pasaron los
tres recorridos UI, incluido el segundo arranque y la restauración de privacidad
del iPhone que antes fallaban. Los catorce casos nativos aprobados se conservan.

Los dos fallos restantes son concretos: la fixture de resolución usa IDs planos,
mientras que el tipo Codable nativo espera su envoltorio interno, y Swift resolvió
incorrectamente una expresión de fallback opcional del número de episodio TVDB.
Este último produjo también un aviso de compilación. Se corrigen la lectura de
la fixture y el fallback explícito; solo esos dos casos vuelven a seleccionarse
con la nueva biblioteca Trakt. Los arreglos aún requieren ejecución Apple.

## Límites

La conexión OAuth personal al proxy comunitario, reproducción y rendimiento en
el iPhone 14, segundo plano y PiP físicos siguen sin certificar. No se declara
completo el port ni las listas, historial visible, recomendaciones o calendario.
Se conservan los fallbacks de traducción que ya tiene la referencia Desktop;
añadir sus claves no certifica una traducción total de toda la aplicación.
