# Original seasonal world and native adapters

The existing nine-shelf native room is not the complete Desktop Spooktober
world. The original Desktop view mounts its own isolated HTML, CSS and module
runtime, with the complete catalog, reading shelves, editorial worlds, format
and sort menus, saved picks, music worlds, interactions, inline details,
navigation and scene animation. Translating the nine-shelf approximation would
leave that functional and visual gap open.

The new package prepares the actual original world from commit
`0834340cec5531650bfe78cd628628702e636987` for WebKit. One hundred two local
resources occupy about 1.76 MB compressed. The runtime, environment, layout,
styles, catalog data and artwork keep the committed original bytes. Three
package files are native adapters: its host HTML/JS and font declarations.
Original font binaries are excluded; the already bundled OFL Inter/Fraunces
files provide the two family names. Exact original typography remains open.

The upstream runtime manifest lists 131 files, but 53 hashes/sizes differ from
the actual committed text blobs because it predates Git line-ending
normalization. Packaging authenticates every input against the pinned Git
blobs, records those differences, and preserves the original compiled runtime.
It does not weaken the check to accept arbitrary changed checkout files.

The resource actor verifies the pinned archive hash, every requested file hash
and extraction checksum. A local URL scheme serves only declared resources
and the two bundled fonts. Native poster loading can resolve the same
declared images without HTTP; its existing HTTP branch is unchanged.

Each controller uses an ephemeral WebKit store and a profile-scoped native
preference adapter for the original saved-picks, motion and Twilight-team
keys. Failed writes preserve the last durable value. Native messages require
the current profile lease, visible main frame and local world origin; the
document receives no account token, user-file reader or arbitrary native call.
Original meta, track, video, playlist, external, back and reload intents have
typed native projections. The original callback and music converters are
executed directly for sixteen reference cases.

The actual Desktop view appends Harbor's theme and music-mark CSS after the
original runtime mounts. Both exact committed sheets and the original music
loading glyph are now bundled. Native appearance supplies the selected color
tokens, system/bundled font choice, interface language, RTL direction and IMDb
badge setting. Changed tokens are removed when switching themes. The two
music status labels retain all 32 original translations across 16 languages.

The playlist mark follows player identity, queue origin and phase, without
tracking the playback clock. It uses the original four bars, paused state and
loading glyph, follows cards replaced by the runtime, and removes stale marks
when hidden or disposed. Sixteen expectations execute the actual original
React indicator and mark. This adapter does not yet implement remote music
playback or replace the app's seasonal route.

## Validation and remaining integration

The first Apple run, 40783739531, built the app but failed to compile the
test target because WebKit returns an optional content rule. None of its five
cases executed. That optional is now explicitly unwrapped. The archive reader
also explicitly selects ZIPFoundation's throwing initializer, addressing both
new warnings from that run.

The follow-up selects those five unexecuted cases plus two new appearance and
indicator cases. It covers offline catalog search, movie routing, Books
filtering, inline book detail, back, late profile-message rejection, actual
loaded WebKit fonts, theme/font/RTL/IMDb changes, all six playlist marks and
card replacement. Twelve compact/regular originals are required. Apple
compilation, execution and visual inspection of this source remain pending.
Approved Home entry and Trakt cases are retained without replay.

This prepares the replacement engine; the old room is still the app's active
route in this commit. Wiring the normal room route, the six Desktop playlist
interfaces, full music source selection/playback, loading scene, native return
focus and complete ordinary phone/tablet navigation remains required. These
items have not been excluded from the full port. No claim of complete room or
full Desktop parity is made, and no IPA is produced by this gate.
