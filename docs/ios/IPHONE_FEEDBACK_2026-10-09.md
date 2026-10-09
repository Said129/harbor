# Submanhwa: bloqueo de anuncios solicitado el 9 de octubre de 2026

El propietario pide bloquear la publicidad al navegar dentro de Submanhwa. Este añadido se incorpora a la única IPA final solicitada junto con las correcciones anteriores. La build 84 entregada no incluye estos cambios; no se inicia una compilación ni se genera una IPA intermedia.

## Implementación

- `SubmanhwaAdBlocker` compila reglas de contenido nativas de WebKit y las instala antes de cargar la primera página. Bloquea solicitudes a redes publicitarias conocidas y oculta contenedores de anuncios específicos de Submanhwa.
- La inspección de la página pública, sin cuenta ni cookies privadas, identificó solicitudes de `jads.co` y `juicyads.com`, un popunder a `massive-hall.com` y los contenedores `.home-ad`, `.home-ad-label`, `.ads-large`, `.ads-sqre1` y `.ads-sqre2`. No se ejecutaron los scripts de publicidad.
- Las ventanas de la propia web conservan su navegación en el navegador integrado. Los enlaces externos pulsados explícitamente siguen permitidos, salvo los dominios publicitarios bloqueados. Las ventanas externas abiertas por scripts se rechazan.
- Se conserva `WKWebsiteDataStore` persistente e independiente por cuenta. El bloqueo no borra cookies, almacenamiento ni credenciales. No se añaden cabeceras, pestañas, avisos ni contadores de publicidad a la interfaz.

La implementación utiliza [WKContentRuleList](https://developer.apple.com/documentation/webkit/wkcontentrulelist), [WKContentRuleListStore](https://developer.apple.com/documentation/webkit/wkcontentruleliststore) y el [formato de reglas de contenido de WebKit](https://webkit.org/blog/3476/content-blockers-first-look/). Se filtran dominios publicitarios concretos; no se bloquean indiscriminadamente todos los recursos externos que necesita la web.

## Comprobación y límites

`SubmanhwaAdBlockerTests` prepara una comprobación de las reglas reales en WebKit con HTML local: anuncios ocultos, imagen de lectura intacta, formulario y almacenamiento disponibles, JavaScript del sitio activo y estilos limitados al dominio de Submanhwa. Otra prueba comprueba límites de dominio, ventanas no solicitadas y enlaces explícitos. Son fixtures locales: no acreditan un inicio de sesión privado, lectura de capítulos reales ni giros de Gacha.

Las pruebas nativas están pendientes de la validación Apple de la entrega final. Este equipo Windows no dispone de Swift/Xcode y la instrucción del propietario descarta compilaciones intermedias. Las comprobaciones locales de repositorio no sustituyen esa validación.

Comprobación local: `pnpm run check --no-error-on-unmatched-pattern` sobre los tres archivos Swift y estos tres documentos terminó correctamente para los documentos compatibles; la herramienta no analiza Swift. `git diff --check` no detectó errores de espacios. No se modificaron TypeScript ni Rust en este incremento.

El filtro incluye las redes observadas y otras redes publicitarias conocidas. No garantiza bloquear todos los anuncios: el sitio puede cambiar de proveedor o servir publicidad desde sus propios dominios. Cualquier ajuste futuro debe conservar la lectura y el acceso a la cuenta.
