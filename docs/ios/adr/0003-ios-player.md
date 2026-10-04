# 0003 — libmpv embebido

## Context

Harbor principal ya usa libmpv con observación de propiedades. Contenedores/subs/advanced settings hacen insuficiente un AVPlayer como único motor.

## Options

AVPlayer único; libmpv + XCFrameworks MPVKit; compilar stack FFmpeg/mpv propio; motor VLC; libmpv con AVPlayer complementario.

## Decision

Primer experimento: libmpv de MPVKit, revisión fija y checksums SPM; render API OpenGL ES sobre superficie UIKit. APIs cliente/events como fuente de verdad; VideoToolbox cuando libmpv lo soporte. Arquitectura permite motor AVFoundation complementario futuro para rutas adecuadas. No ejecutar mpv externo ni trasladar windows/IPC Desktop.

## Advantages

Conserva misma semántica de comandos/propiedades, FFmpeg y libass, amplitud de formatos sin reescribir decodificación. Artefactos existentes permiten probar enlace temprano.

## Disadvantages

OpenGL ES está deprecated; evaluar render Metal después del experimento. El [demo iOS de la revisión fijada](https://github.com/mpvkit/MPVKit/blob/f82e06d4f5ef4fc4aa9faba3782a462dbbef870c/Demo/Demo-iOS/Demo-iOS/Player/OpenGL/MPVViewController.swift) advierte de problemas con vídeo de 10 bits. Es un riesgo de esta superficie inicial, no una imposibilidad de iOS ni una eliminación de HDR. El soporte Metal de MPVKit se declara experimental en su README. Binarios/transitivas son grandes; licencias y redistribución requieren inventario antes de distribuir. PiP/AirPlay/HDR no quedan resueltos al enlazar libmpv.

## Consequences

No declarar codecs ni HDR como Parity sin archivos/dispositivos comprobados. Observar time-pos/duration/pause/tracks/end-file; teardown sincronizado del render/audio. Comandos y cambios de propiedades de playback usan APIs asíncronas y sus replies se inspeccionan: el hilo de render no debe esperar al core mpv. Configurar video-timing-offset=0 evita su espera anticipada de frames en el hilo UI; medir sincronización A/V y frame pacing en dispositivo. No emitir URLs ni logs mpv completos. Fuentes: [MPVKit](https://github.com/mpvkit/MPVKit), [mpv render API](https://github.com/mpv-player/mpv/blob/master/include/mpv/render.h).
