# 0004 — Secretos separados de preferencias

## Context

Desktop usa localStorage y settings.json. Las URLs addon configuradas también pueden incluir tokens en path/query/base64.

## Options

Copiar localStorage a JSON; Keychain para secretos con Application Support para datos; SQLite para todo; UserDefaults para todo.

## Decision

Keychain AfterFirstUnlockThisDeviceOnly para sesiones/keys y addon records configurados. Application Support, files con protección y escrituras atómicas para progreso/watchlist y preferencias versionadas. Caches para temporales. UserDefaults sólo flags no sensibles. SQLite podrá incorporarse con la biblioteca completa según volumen.

## Advantages

No guardar keys en preferencias/backup ni exponer URLs sensibles. Foundation/Keychain permiten integración OS y tests de contratos storage.

## Disadvantages

Keychain no sincroniza todos los datos por sí solo y puede fallar. Requires migration/version handling; tokens no se exportan con themes/settings.

## Consequences

Fallo de lectura NO significa store vacío: mostrar error y no sobrescribir. Addon manifests/URLs quedan en Keychain; sólo IDs no secretos/counts en logs. Escritura persistente previa a actualizar estado visible. Progreso separado de credenciales y futura reconciliación de cuentas.

## Implementación de progreso local

`ResumeStore` es un actor Foundation: I/O y llamadas C puras fuera del hilo de UI, documento v1 en Application Support, escritura atómica y protección `completeUntilFirstUserAuthentication`. Sólo persiste claves de contenido/episodio, milisegundos y timestamp; no guarda URLs de reproducción, artwork, addons ni tokens. Un store corrupto, inaccesible o de versión desconocida no se convierte en vacío; quedan deshabilitadas las escrituras. Una escritura fallida no modifica el estado en memoria. Checkpoints con timestamp anterior o igual al persistido se descartan para evitar sobrescritura por tareas de cierre retrasadas.

Las reglas de claves, validación, autosave y reanudación se portan desde TypeScript a `harbor-core/src/resume.rs`, con pruebas contra el módulo Desktop real. Desktop conserva su implementación actual; el nuevo contrato permite migración futura. IDs de episodios sin temporada/número usan una clave adicional por video para conservar su progreso independiente.

No se ha ejecutado todavía el código Swift/almacenamiento en Apple. Los tests de restart/corrupción/escritura esperan simulator; los checkpoints en lifecycle y la reanudación mpv necesitan verificación física. No representan biblioteca, historial completo ni sincronización cloud.
