# Original seasonal world and native adapters

The existing nine-shelf native room is not the complete Desktop Spooktober
world. The original Desktop view mounts its own isolated HTML, CSS and module
runtime, with the complete catalog, reading shelves, editorial worlds, format
and sort menus, saved picks, music worlds, interactions, inline details,
navigation and scene animation. Translating the nine-shelf approximation would
leave that functional and visual gap open.

The new package prepares the actual original world from commit
`0834340cec5531650bfe78cd628628702e636987` for WebKit. Ninety-nine local
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

## Validation and remaining integration

The selective Apple gate contains three resource/intent/persistence cases and
two cases that run the actual original runtime in WebKit, including offline
catalog search, movie routing, Books filtering, inline book detail, back, and
late profile-message rejection. Eight compact/regular originals are required.
Apple compilation, execution and visual inspection remain pending.

This prepares the replacement engine; the old room is still the app's active
route in this commit. Wiring the normal room route, the six Desktop playlist
interfaces, full music source selection/playback, loading scene, native return
focus and complete ordinary phone/tablet navigation remains required. These
items have not been excluded from the full port. No claim of complete room or
full Desktop parity is made, and no IPA is produced by this gate.
