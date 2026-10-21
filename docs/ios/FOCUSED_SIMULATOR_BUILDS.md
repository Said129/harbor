# Compilación de validaciones enfocadas

Las validaciones de plugins estaban construyendo tres binarios Rust de Release: iPhone físico, simulador Apple Silicon y simulador Intel, aunque todos sus casos se ejecutan en un único host de simulador. También repetían tres comprobaciones explícitas de la dependencia compartida antes de que `cargo rustc` compilara esa dependencia.

El modo nuevo `build-rust.sh --simulator-only` compila la arquitectura del host, conserva los mismos flags de Release y el mismo ABI y crea un XCFramework exclusivamente de simulador para esa validación. `package-core.py` exige que las arquitecturas reales coincidan con las solicitadas y sigue verificando todos los símbolos exportados y el install name de cada slice. El modo completo predeterminado conserva los tres destinos y las dos plataformas del XCFramework.

El workflow elige este modo sólo con `validation_only=true` en los dos ámbitos de plugins. La construcción de la IPA final conserva el modo completo, incluidas la arquitectura de iPhone físico y ambas de simulador. No cambia el código Rust ni las funciones de la aplicación.

El shell real se ha ejecutado con herramientas inertes para comprobar los tres recorridos válidos y el rechazo de dos entradas inválidas. La validación enfocada invoca una compilación, y la completa tres; las pruebas locales no compilaron, empaquetaron ni eliminaron binarios. La sintaxis Python y el formato YAML se han comprobado. Falta validar el empaquetado y enlace reales con Apple; no se repiten las suites funcionales aprobadas únicamente para comprobar esta herramienta.

La ejecución `39623835388`, fuente `611784ae29de26991c5aba30c72e288a9b43ad6e`, conserva el proceso anterior y no contiene esta optimización posterior. No se atribuye a esa ejecución una mejora de tiempo que no haya medido.
