# Plugins — reviewed difference against Desktop 0.9.132

Reference: `0834340cec5531650bfe78cd628628702e636987`. Native `HarborSection` currently has no Plugins destination and there is no native Harbor plugin repository/installation/runtime implementation. Existing Stremio addons and Suwayomi sources do not implement this separate feature. The Plugins room remains required and incomplete; the reference settings panel's Desktop-only label does not by itself establish an iOS incompatibility.

## Compatible behavior still required

The reference separates interpreted `harbor`/`provider-script` plugins from `android-extension` archives. The interpreted stream, manga and ebook kinds remain in scope. The actual reference implementation provides:

- Repositories: normalize HTTPS and GitHub links, detect kind/format, refresh listings, show disabled/error states, remove repositories and optionally install all listed entries.
- Installed plugins: enable/disable, install/uninstall, update checks, update, previous-version rollback and version/hash/file-change state.
- Configuration and health: declared settings, persisted values, permitted/learned hosts, request count and timing, diagnostic logs and automatic pause after repeated failures.
- Runtime: source/configuration initialization, declared methods, ready/operation timeouts, cancellation and disposal; a bounded idle pool; HTTP/gRPC and HTML parsing through the same host contract as the reference.
- Integration: stream requests and subtitle results; manga browse/search/detail/chapters/page URLs; ebook browse/search/detail/content.
- Plugins room: grouped catalog shelves, selected-plugin filter, submitted search with paging, hero selection, rearrangement and remembered selection/order. Catalogs must update after installation/removal/runtime changes and reject stale loads.
- Presentation: the reference room, picker, arrangement and settings states adapted to touch/iPad, including their interfaces and motion.

This list records actual source behavior to implement. It is not a set of completed functions, a replacement for a full method-by-method review, or a denominator for a completion percentage. There is no new empty navigation item or nonfunctional settings control in the native app.

## Narrow platform exclusion

The reference's local Android archive bridge starts a separate Java process with a classpath and DEX tools (`src-tauri/src/capstan.rs`, `capstan/locate.rs`). Apple's Developer Technical Support explicitly states that iOS applications cannot spawn child processes. Accordingly, that exact local JVM launcher cannot be carried into an ordinary iPhone/iPad IPA. This is an inference from the verified reference dependency and [Apple's platform explanation](https://developer.apple.com/forums/thread/747499).

Only that local subprocess/Android bridge is excluded by this dependency. It does not exclude the interpreted plugin system, ordinary Stremio addons or remote Suwayomi sources. It does not claim that every possible Java implementation is impossible. No account credentials or personal plugin configuration are sent to a replacement server as a workaround.

## Reuse candidates and next implementation

`src/lib/manga/plugins/sandbox.ts` contains a self-contained worker program and its message contract. `host-parse.ts` provides bounded DOM serialization. `worker-host.ts` defines initialization/call/bridge/result/cancel/timeout behavior. `src/lib/plugins/index.ts` and the three kind adapters define shared repository/installed management. The stream runtime and provider compatibility prelude are additional required adapters.

Apple exposes JavaScript evaluation through [JavaScriptCore](https://developer.apple.com/documentation/javascriptcore/jscontext). A native host can therefore be investigated while retaining the original interpreted contract; the browser worker also offers a reuse candidate through an isolated WebKit host. Choosing and validating that host remains implementation work. Source inspection is not evidence that either host already runs Harbor plugins correctly on iOS.

Relevant room sources: `src/views/plugins.tsx`, `src/views/plugins/plugin-picker.tsx`, `plugin-hero.tsx`, `plugin-arrange.tsx`; management sources: `src/views/settings/plugins-panel.tsx` and its children. No plugin execution or interface claim is approved by this audit.
