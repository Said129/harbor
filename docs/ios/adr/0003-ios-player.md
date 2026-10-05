# 0003 — libmpv embebido

## Context

Harbor principal ya usa libmpv con observación de propiedades. Contenedores/subs/advanced settings hacen insuficiente un AVPlayer como único motor.

## Options

AVPlayer único; libmpv + XCFrameworks MPVKit; compilar stack FFmpeg/mpv propio; motor VLC; libmpv con AVPlayer complementario.

## Decision

Primer experimento: libmpv de MPVKit, revisión fija y checksums SPM; render API OpenGL ES sobre superficie UIKit. APIs cliente/events como fuente de verdad; VideoToolbox cuando libmpv lo soporte. Arquitectura permite motor AVFoundation complementario futuro para rutas adecuadas. No ejecutar mpv externo ni trasladar windows/IPC Desktop.

Actualización 2026-10-05: el propietario confirma audio pero pantalla azul uniforme en varias fuentes del iPhone 14. El mapper directo iOS de mpv limita los formatos que CoreVideo puede importar en GLES; el fallo de 10 bits está documentado por mpv y el demo fijado. La ruta predeterminada pasa a `videotoolbox-copy`, como el player embebido Apple de Harbor Desktop, con `gpu-hwdec-interop=no` para evitar esa importación. Mantiene decodificación acelerada con copia de frames a RAM y conserva fallback de mpv a software; no fuerza NV12 de 8 bits ni elimina HDR del alcance. `mpvHwdec` ofrece auto/on/off, con ajuste persistente y cambio durante la reproducción. Auto/on prefieren la ruta VideoToolbox compatible; off decodifica en CPU. La copia puede consumir más memoria/ancho de banda que zero-copy y debe medirse en dispositivo.

Fuentes de la decisión: [mapper iOS de mpv 0.40](https://github.com/mpv-player/mpv/blob/v0.40.0/video/out/hwdec/hwdec_ios_gl.m), [pantalla azul con formato de 10 bits](https://github.com/mpv-player/mpv/issues/9633), [contrato hwdec copy/software](https://github.com/mpv-player/mpv/blob/v0.40.0/DOCS/man/options.rst). La coincidencia del síntoma es una inferencia; no se ha recibido codec/pixfmt ni un log de la fuente privada del propietario.

## Advantages

Conserva misma semántica de comandos/propiedades, FFmpeg y libass, amplitud de formatos sin reescribir decodificación. Artefactos existentes permiten probar enlace temprano.

## Disadvantages

OpenGL ES está deprecated; evaluar render Metal después del experimento. El [demo iOS de la revisión fijada](https://github.com/mpvkit/MPVKit/blob/f82e06d4f5ef4fc4aa9faba3782a462dbbef870c/Demo/Demo-iOS/Demo-iOS/Player/OpenGL/MPVViewController.swift) advierte de problemas con vídeo de 10 bits. Es un riesgo de esta superficie inicial, no una imposibilidad de iOS ni una eliminación de HDR. El soporte Metal de MPVKit se declara experimental en su README. Binarios/transitivas son grandes; licencias y redistribución requieren inventario antes de distribuir. PiP/AirPlay/HDR no quedan resueltos al enlazar libmpv.

## Consequences

No declarar codecs ni HDR como Parity sin archivos/dispositivos comprobados. Observar time-pos/duration/pause/tracks/end-file; teardown sincronizado del render/audio. Comandos y cambios de propiedades de playback usan APIs asíncronas y sus replies se inspeccionan: el hilo de render no debe esperar al core mpv. Configurar video-timing-offset=0 evita su espera anticipada de frames en el hilo UI; medir sincronización A/V y frame pacing en dispositivo. No emitir URLs ni logs mpv completos. Fuentes: [MPVKit](https://github.com/mpvkit/MPVKit), [mpv render API](https://github.com/mpv-player/mpv/blob/master/include/mpv/render.h).

El simulator utiliza `hwdec=no`, como el demo iOS de la revisión fijada de MPVKit; no representa el decodificador VideoToolbox de un teléfono. La prueba de H.264/HEVC conserva las aserciones de imagen y tiempo sin bajar la profundidad de color. Device sigue prefiriendo `videotoolbox-copy`; comprobar sus buffers/codec/perfil en el iPhone físico es un gate separado.
