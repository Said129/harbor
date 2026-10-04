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
