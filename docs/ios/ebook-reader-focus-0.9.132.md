# Concentración del lector de Desktop 0.9.132

La referencia `harbor-reader.tsx` revela los controles al interactuar, los oculta
tras 2200 ms cuando está activo el modo de concentración y anima la transición
durante 300 ms. El lector nativo conservaba el ajuste, pero ocultaba el pie de
forma permanente y dejaba visible la barra superior.

`EBookReaderChrome` reproduce la inactividad y cancela el temporizador anterior
en cada interacción. El lector anima el pie, oculta la navegación y recupera los
controles al tocar la lectura. El modo impreso usa la misma visibilidad. Los
ajustes siguen perteneciendo al perfil y se conservan al volver a abrir la app.

En iOS se suspende la ocultación mientras hay una hoja abierta, se carga un
capítulo, aparece un error, la app está inactiva o está activo VoiceOver. Reducir
movimiento elimina la animación del pie. La salida del lector cancela el trabajo
pendiente sin retener su estado.

Hay dos comprobaciones nativas nuevas y dos recorridos nuevos para iPhone/iPad:
activación real del ajuste, panel abierto más allá del intervalo, ocultación,
recuperación al tocar, reapertura y giro conservando el capítulo, y desactivación.
La compilación Apple, los resultados reales y la revisión de las capturas siguen
pendientes. Las comprobaciones anteriores de áreas intactas se conservan y no se
seleccionan de nuevo. Este incremento no genera una IPA ni completa por sí solo
el port.
