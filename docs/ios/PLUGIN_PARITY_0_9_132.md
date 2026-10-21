# Plugins — reviewed difference against Desktop 0.9.132

Reference: `0834340cec5531650bfe78cd628628702e636987`. Interpreted plugins remain required. A native repository client, catalog store, isolated WebKit runtime, manager and settings normalizer have now been implemented, followed by management/editor views and a runtime pool. Their individual execution status is recorded in the linked implementation documents; source presence does not establish full parity. Existing Stremio addons and Suwayomi sources are distinct features.

The earlier assumption that the full Plugins catalog room was independently compatible is superseded by the actual dependency review below. Its visibility is conditional in Desktop itself; do not add an empty native destination to represent that room.

## Compatible behavior still required

The reference separates interpreted `harbor`/`provider-script` plugins from `android-extension` archives. The interpreted stream, manga and ebook kinds remain in scope. The actual reference implementation provides:

- Repositories: normalize HTTPS and GitHub links, detect kind/format, refresh listings, show disabled/error states, remove repositories and optionally install all listed entries.
- Installed plugins: enable/disable, install/uninstall, update checks, update, previous-version rollback and version/hash/file-change state.
- Configuration and health: declared settings, persisted values, permitted/learned hosts, request count and timing, diagnostic logs and automatic pause after repeated failures.
- Runtime: source/configuration initialization, declared methods, ready/operation timeouts, cancellation and disposal; a bounded idle pool; HTTP/gRPC and HTML parsing through the same host contract as the reference.
- Integration: stream requests and subtitle results; manga browse/search/detail/chapters/page URLs; ebook browse/search/detail/content.
- Presentation: compatible source pickers, management, declared settings, health and reading interfaces adapted to touch/iPad, including their interfaces and motion.

This list records actual source behavior to implement. It is not a set of completed functions, a replacement for a full method-by-method review, or a denominator for a completion percentage. There is no new empty navigation item or nonfunctional settings control in the native app.

## Narrow platform exclusion

The reference's local Android archive bridge starts a separate Java process with a classpath and DEX tools (`src-tauri/src/capstan.rs`, `capstan/locate.rs`). Apple's Developer Technical Support explicitly states that iOS applications cannot spawn child processes. Accordingly, that exact local JVM launcher cannot be carried into an ordinary iPhone/iPad IPA. This is an inference from the verified reference dependency and [Apple's platform explanation](https://developer.apple.com/forums/thread/747499).

Only that local subprocess/Android bridge is excluded by this dependency. It does not exclude the interpreted plugin system, ordinary Stremio addons or remote Suwayomi sources. It does not claim that every possible Java implementation is impossible. No account credentials or personal plugin configuration are sent to a replacement server as a workaround.

### Consequence for the conditional Plugins room

In `streams/plugins/runnable.ts`, `providesOwnRows` returns true only for `format === "android-extension"`. `pluginCatalogueSources` additionally requires `extensionsSupported()`. `available.ts` derives its room-availability flag from that list; `chrome/nav-items.tsx:312` filters the Plugins navigation item with that flag. Consequently, Desktop 0.9.132 itself hides this room when the installation contains only interpreted plugins. Its grouped catalog shelves, selected-plugin picker, hero, paging/search and arrangement views belong to the excluded local Android catalog bridge in this pinned version.

The iOS port keeps the same absence of that conditional room for its compatible interpreted stream plugins, rather than inventing catalogs that those plugins do not provide. This dependency exclusion does not remove their stream execution, subtitle results, management/settings/health, repository grouping in the stream picker, or the separate interpreted manga/ebook integrations. Unknown Desktop navigation/preferences fields must still survive synchronization. A future reference adding interpreted stream catalogs would require a new review; it is not assumed here.

## Reuse candidates and next implementation

`src/lib/manga/plugins/sandbox.ts` contains a self-contained worker program and its message contract. `host-parse.ts` provides bounded DOM serialization. `worker-host.ts` defines initialization/call/bridge/result/cancel/timeout behavior. `src/lib/plugins/index.ts` and the three kind adapters define shared repository/installed management. The stream runtime and provider compatibility prelude are additional required adapters.

The compatible host now uses isolated WebKit workers and the pinned browser worker/prelude. Its validated and pending subsets are recorded in the runtime/network implementation documents. The new pure response adapter, request builder and playback producer are described in [the stream integration record](PLUGIN_STREAM_ADAPTER_0_9_132.md); their newly added native cases have not yet executed. This source audit does not approve their execution or full parity.

Relevant room sources: `src/views/plugins.tsx`, `src/views/plugins/plugin-picker.tsx`, `plugin-hero.tsx`, `plugin-arrange.tsx`; management sources: `src/views/settings/plugins-panel.tsx` and its children. No plugin execution or interface claim is approved by this audit.
