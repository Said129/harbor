# Next interim IPA: music and subtitle seeking

The user requested one further interim IPA before the final complete port. Build
93 remains the delivered candidate. Do not package a succession of feature IPAs.
This work does not finish Music parity or establish a global port percentage.

## Implemented, awaiting affected Apple execution

- Finish the previously uncommitted M3U importer, private audio copies, folder
  grants, cross-platform path matching, owner retirement and larger local index.
- Execute Desktop's original recording matching in shared Rust, including its
  version/tempo/backing-track/explicitness/duration decisions. Connect matches
  from genuine local files, Subsonic and the public SoundCloud connector to the
  existing Desktop source policy and native source picker.
- Preserve the current clock and pause state when selecting a music source.
- Add SoundCloud consent, public client discovery, browse/search/playlist
  transport and full unencrypted source resolution. More provider interfaces
  and the complete registry remain pending.
- Run the original Desktop LRCLIB module in the existing scoped runtime. The
  native lyric view follows the real music clock and taps seek the same player.
- Integrate the official Spotify iOS SDK at immutable source
  `8d3a71dc25282072f8aa8bb0611cea2324e18f28`. The official Spotify app owns audio
  and Free/Premium restrictions. Harbor requires the listener's own configured
  Client ID; development-mode app ownership still requires Spotify Premium.
  This has not been tested with an actual authenticated Spotify account.

## Subtitle investigation

The previous subtitle test kept one line on screen for 29.5 seconds. It could
not establish seeking across changing cues. New owned Matroska/H.264/PCM/SRT
media and a real mpv test cover embedded and imported cues after forward,
backward, paused and playing seeks. Baseline run `41299787345`, source
`7ee4a4ebfa1926e6c521540f1401eacd807a4d5a`, was dispatched without an IPA and
without changing the seek implementation. Its result must be collected before
claiming to reproduce or fix the reported drift. The user's hypothesis is not
yet a diagnosis.

### Current evidence, 2 November

The baseline run above completed successfully: its single local embedded and
external changing-cue seek case passed in 17.502 seconds. This did not reproduce
the physical-device fault. The user then confirmed that Software decoding also
drifts, and that voices still match the picture: only the subtitle text drifts.
Do not describe decoder changes or the local pass as a subtitle fix.

Focused run `41447516378`, source `4285c29eae331cfc48689e7680bf879fffb773c5`,
executes the new HTTP range seek case with four rendered subtitle captures,
plus the nine Music cases that never executed in run `41301181420` because of
two shadowed Swift parameters. That compilation fault is fixed. The accepted
two M3U and fifteen matching Rust passes from that run are reused only if the
respective source blob hashes still match. No IPA was requested from this run.

### Additional integration awaiting Apple execution

Original audio/DSP math is retained in Rust. Native audio preferences, the
nineteen original EQ presets, the graphic curve, EQ/preamp/balance/ReplayGain,
speed/pitch, volume ceiling, profile-owned listening profiles and actual signal
properties are connected to the native engine. The output chooser uses AVKit.
Unsupported effects remain a completion gap: the pinned FFmpeg build lacks
echo, crossfeed, shelf/pass/notch filters. They are rejected explicitly, never
silently removed. The initial settings view exposes the working graphic path;
the full parametric/effects interface still requires the appropriate runtime.

New audio cases cover live engine changes across pause/seek, retired requests,
original preset data, profile reload and routing/volume protection, and phone/
tablet render captures. They have not yet executed. The original lyrics offset
now affects a tapped line's seek destination as well as its highlighted line.

The official Spotify SDK now has content/artwork bridge requests, a connected
content browser and a global mini player. Actual Spotify authorization, Free
restrictions and authenticated browsing remain unverified. Original Music
labels have been transferred for all sixteen Desktop languages. The subsequent
source/setup increment also localizes the six mobile-specific Spotify and
SoundCloud explanations/errors in all sixteen languages, using the original
Desktop setup labels for the remaining form controls. A new native case checks
the 96 values against the compiled language bundles; execution is pending.

Both native runs stopped at Swift compilation; no selected native case executed.
`41447516378` and `41449579804` exposed an implicit `catch error` shadowing the
Spotify status property and nested callback captures requiring explicit `self`.
Those errors, and the same shadowing in the new audio preference loader, are
corrected. Run `41449579804` did execute and pass all thirteen original Rust
audio math cases before the Swift failure. Preserve that exact-source evidence.
The original artifacts are downloaded and SHA-256 verified under
`work/music-subtitle-94-review/{http-compile-41447516378,audio-compile-41449579804}`.

The user's concrete example is **Obsession, Stremio Community Subtitles**.
That provider publishes external VTT/ASS tracks. Its public source was inspected
at `skoruppa/stremio-community-subtitles`, especially `app/routes/subtitles.py`.
A further owned native case downloads changing WebVTT through the actual addon
file service after starting playback at eight seconds, then checks seeks and
captures rendered cues. It has not run yet and is not a claimed drift fix.

Run `41479583285`, source `49ecf48aab3144b6347b5a2b7391f4d7c1c9f400`,
executes the fifteen still-unexecuted native cases after the compile corrections:
M3U (3), lyrics (2), Spotify configuration (2), SoundCloud (2), audio/source
switching/phone-tablet captures (4), HTTP seeks (1), downloaded VTT seeks (1).
The accepted local seek case and exact-source Rust cases are excluded.

### Movie-version matching gap

Pinned Desktop's `src/views/player/hooks/use-track-autoload.ts` computes a movie
hash with an 1800 ms budget before subtitle lookup. Native iOS had only forwarded
an optional addon-provided hash. The original hash arithmetic is now in shared
Rust, and native IO reads precisely the first/last 64 KiB with HTTP 206 range
validation and a common 1800 ms deadline. Private video headers remain confined
to video requests; cross-origin redirects discard them. Computed hash/size
enrich the selected video's subtitle request, with the existing hints retained
as fallback if hashing is unsupported. Playback is not blocked or reloaded.
Two new native cases and the original two Rust arithmetic cases are pending.
This closes a concrete parity gap but does not establish the cause of seeking
drift or prove it fixed.

The next Spotify increment also uses the official playback speed and timestamp
to advance its position display between SDK events. Authorization has a bounded,
profile-fenced timeout and clears cancellation when returning from Spotify,
instead of leaving the form waiting indefinitely. These paths still require
actual-account execution; no Free/Premium playback claim is inferred from UI
captures or syntax checks.

### Completing the missing DSP runtime

`scripts/ios/music-dsp-runtime.py` and the `music-runtime` workflow scope build
the extra filters from the actual 1.0.0 release builder, MPVKit commit
`288527dffbc6d3e63cce147fc7b520c64a791603`, and exact FFmpeg commit
`38b88335f99e76ed89ff3c93f877fdefce736c13` (n8.1.2). Only a prospective
Libavfilter replacement is collected, for arm64 devices and arm64/x86_64
simulators; the application has not adopted it. The additional filters cover
the original reverb/crossfeed/shelf/pass/notch processing, signal metering and
audio transitions. Collection requires their real configure definitions for
each architecture and records source diffs, archive hashes and notices.
Actual native effect execution and an explicitly verified package integration
remain required. This workflow does not package an IPA or change libmpv.

Run `41483844236` was explicitly cancelled after inspecting the deployed
framework archives, not due to an observation timeout: the app's pinned newer
Package.swift still points to binary release 1.0.0, whose checked headers say
FFmpeg n8.1.2, libavutil 60.26.102 and libavfilter 11.14.102. Building n9.0.1
would be ABI-incompatible. Both downloaded original archives match the SHA-256
checksums in the app's package pin and in the 1.0.0 release source. The corrected
builder now asserts those exact ABI versions before collecting a replacement.
The original app dependency pin and IPA 93 have not changed.

The movie-hash run `41480784667` also reached its 1500-second build limit. Its
two native cases never executed, but its two original Rust arithmetic tests
passed. Verified artifact SHA-256:
`e7f808da6537a062df0869224dbb12be6f63ccf36a44bf6dfb3a044d992ba303`, preserved at
`work/music-subtitle-94-review/moviehash-timeout-41480784667`. The native build
log has no compiler error before timeout. Reuse those two Rust passes only
when the hash module source blob is unchanged. For fresh job phase/status,
GitHub's direct no-cache API was needed: the connector's step snapshot still
showed compilation while the actual job was already completing cleanup.

The user confirmed Auto-sync was **off** for the Obsession case. Automatic VAD
analysis is therefore not the active path in that example. Also inspected
mpv v0.41.0 `include/mpv/render.h` and `video/out/vo_libmpv.c`: render-context
updates are optional when advanced control is absent, and rendering implicitly
pulls the queued frame. Do not claim the missing optional update call as a
diagnosed fix or add a subtitle-delay reset without reproducing the fault.

Live handles at the next checkpoint: native fifteen-case run `41479583285`
(job `125394032213`), movie-hash run `41480784667` (job `125398207543`),
and DSP library run `41483844236` (job `125408869087`). The latter uses source
`b7844cf511b178a77d78d95a4b31fc6b7a55a6da`. Job-log download returned 404 while
the native job was live; that was an unavailable log, not a terminal job.

Future focused builds preserve compiler intermediates/products/module caches
under an architecture/Xcode/source key. This caches compilation only: the
explicitly selected new cases still execute, and their result rows remain
mandatory. The native build command gets 35 minutes within its 55-minute step
instead of a 25-minute cold-build limit. No running job was cancelled for this
change. Current validation results must still be collected from their handles.

The fifteen-case run `41479583285` subsequently terminated: **native build timed
out after 1500 seconds**, not a native test failure. All fifteen executions are
still unexecuted. Its verified artifact SHA-256 is
`d4eed0b10377097726da56733b0d1fef124b081916078a1eb8630b6320ed4413`, preserved in
`work/music-subtitle-94-review/native-timeout-41479583285`. The original build
log contains no compiler error before timeout and only the existing OpenGLES
deprecations. The new audio form is now split into seven opaque view sections
with explicit curve number types to reduce Swift constraint solving; this has
not yet proved a compile-time improvement.

The HTTP seek fixture is also strengthened: small delayed network chunks let
the cache limits apply before the entire clip is prefetched, and a new positive
byte range must be observed **after** loading. An initial metadata range cannot
satisfy the assertion. This changed case requires its own actual execution;
the accepted local seek test remains untouched.

The new preferred music source is now part of the existing profile settings
mirror, alongside shuffle/repeat/volume. It previously used a global defaults
key without inclusion in that mirror. A new isolated persistence case switches
independent owners and restarts the store to verify their choices stay separate.

## Validation approach

Keep previously accepted unchanged Music, Rust and app evidence. A focused
workflow builds once and executes explicitly selected changed cases. A small
`HarborChangedTests` target avoids compiling the entire historical test corpus
when only these new self-contained cases are required. No automatic full-suite
fallback is allowed. Source fixtures are test resources, never product media.

The first local `vp check` had no supported lint files; another attempt found
an unformatted new M3U provenance document. The document was formatted and the
changed JavaScript/JSON check then passed. Rust formatting and Python syntax
checks passed. Native compilation/execution remains separate. The previously
documented unavailable Windows MSVC linker and Linux host checks are not
reported as successful or rerun as substitutes for Apple execution.

## Required work before calling Music complete

Finish compatible source clients and their complete connection/catalog/player
flows, Spotify browsing/library integration, matching/recovery and source
selection journeys, original cached genre filters, music recommendations and
personal navigation, audio/DSP/quality controls, session restoration,
prewarming/gapless behavior where supported, mobile casting/routing, remaining
original artwork/visualizers/layouts/motion, all 16 languages, and affected
phone/tablet visual validation. Reconcile against pinned Desktop 0.9.132 source,
not merely the older partial inventory. Do not replace missing features with
inactive controls or claim physical-device validation from a simulator.

## Jellyfin source port added 2 November

The pinned Desktop Jellyfin music implementation now supplies native iOS home
rows, typed search, albums, playlists, favourite tracks, artist top tracks,
Instant Mix stations and direct/transcoded stream negotiation through the
existing cancellable Rust music ABI. The original Desktop artist-catalog
limitation is retained rather than advertising unavailable full pagination.

The native connection form saves only the resulting account token in the active
profile's Keychain entry. There is no persisted password, global account cache,
or credential embedded in remembered tracks. Requests retain reverse-proxy
subpaths, enforce an 8 MiB API-body limit and avoid forwarding the authorization
header to another origin. Late/cancelled authorizations cannot commit to a
retired profile. Stream start/stop reports are ordered from real player load and
termination events. Source matching and the preferred-source picker include
Jellyfin; Instant Mix now uses the shared radio detail and queue route.

Three new native journeys use an owned loopback server: original provider
requests plus real libmpv playback/seeking/reporting; Keychain restart and profile
retirement/cancellation; phone and tablet-size connection captures. Original
ported Rust cases are selected separately. Both native execution and visual
review are pending, and no real private Jellyfin server is claimed tested.
Provenance and adaptation boundaries are in `jellyfin-music-port-inputs.json`.

The changed JSON/YAML files pass formatter checks. `pnpm run check` cannot start
lint analysis when that changed selection has no supported lint source; this is
recorded as not applicable, not a successful lint pass. Windows's previously
recorded missing MSVC linker and unavailable Linux host remain unchanged. New
Rust compile/check/tests and Apple compilation will run in the affected CI job.
The earlier nineteen-case and corrected FFmpeg 8.1.2 jobs are still running;
their accepted or failed rows must be collected from their existing run IDs.

A fourth Jellyfin journey now checks disconnect while the public catalog is
still loading. The merged result also fences Jellyfin's credential revision,
so an old account's completed rows cannot appear after disconnection. That case
is pending execution and was not part of the original three-case dispatch.

SoundCloud typed search now follows Desktop's three parallel buckets: tracks
are required, artists and playlists tolerate independent source failure, with
its 12-item side limit and 50-item endpoint page ceiling. Artist cover upgrades,
20 top tracks and the 100-track playlist bound match the pinned connector.
The new typed-search journey plus the existing affected search/resolve journey
need execution on this new source; the unchanged transcoding preference case
need not be rerun after acceptance. These follow-up cases should use available
native compile caches rather than starting another duplicate cold build while
the current jobs are live.

Read-only investigation of mpv issue 18676 found a reported external PGS seek
state issue on 0.41/FFmpeg 8.1.2. That is not evidence for the user's Community
VTT case; no PGS workaround, subtitle reload or timing reset was added based on
it. Source: https://github.com/mpv-player/mpv/issues/18676.

Run `41489402451`, source `39c50ab4`, compiled the application but could not
compile the owned HTTP fixture: nested closures required `self.ready` and
`self.connections`. Its nineteen selected native cases never executed. Both
captures are now explicit. The verified artifact is preserved at
`work/music-subtitle-94-review/native-compile-41489402451.zip`, SHA-256
`08394467215ca872013148597e0412379105594e82e6f09399e3c7dbaff2c58c`.
Only the previously known OpenGLES deprecations precede those two test errors.

The redundant three-case build `41492339187` was deliberately cancelled after
proving its fixture source blob exactly matched the compiler-rejected blob
`2ddb487292e3d81680e6278a175f4201f8e1648d`. It was not cancelled because of
an observation timeout. Its native cases did not execute. Its real host
`cargo check` and **26 original Jellyfin cases passed**, with no warning/error
in those preserved logs. Artifact SHA-256:
`7d096453c009e0636f46bb55a0536566b43a907be73a329a290f0498bf1c1768`, at
`work/music-subtitle-94-review/jellyfin-original-41492339187.zip`.
Reuse those 26 passes only for Jellyfin tree
`0f338bc5a8c3fdf473b47bb840ec871de86a61d5`. The next corrected native selection
contains the nineteen unexecuted cases, all four Jellyfin journeys and the new
typed SoundCloud journey, for 24 explicitly required executions. It excludes
the already accepted unchanged local subtitle baseline. The in-progress Plex
source port is kept outside this corrective validation commit.

## Plex music source port added 2 November

The pinned Plex Rust connector now powers native home hubs, typed search,
albums, artists, playlists, radios and direct/transcoded audio. The connection
form accepts an explicit server token or an account token with a blank address
for original ranked local/remote/relay discovery. It does not yet replace the
shared Desktop video Plex login flow. The original first-library choice and
limited artist-catalog contract are retained.

Unlike the original metadata representation, a remembered/exported cover is a
connection-scoped `harbor-music-art` reference without a token or server URL.
Native rendering restores Plex's inner and outer transcoder authorization only
for the actual private request, bounds cover bytes/decoding/cache, rejects
remote inner sources and fences account changes. The shared public image path
continues to serve ordinary public Music covers. The mini-player and expanded
player supply their real profile playback session to cover rendering.

Three owned-server journeys cover actual Rust/HTTP catalog and radios, private
cover fetching and cache coalescing, remembered metadata without credentials,
real libmpv audio and seeks, Keychain restart, late profile authorization, and
phone/tablet-size connection and loaded-cover captures. The discovery help is
present in all sixteen app languages. Real-server use and native execution are
still pending. The package has not adopted the new DSP library and no IPA has
been packaged. Provenance is in `plex-music-port-inputs.json`.

The Plex validation selection must also execute the existing Jellyfin native
provider journey: the shared private-provider request gained a typed sum for
Plex/Jellyfin with transparent encoding, so its original JSON boundary needs
this affected compatibility check. The twenty-four-case corrective run uses
source `3193fb4d` and is kept independent of these new Plex files.

## Results collected after resume

Both `41495696602` (source `3193fb4d`) and `41496910543` (source `0f7deb9b`)
stopped while compiling new tests; no selected native case executed. The
Jellyfin/Plex test source had malformed shorthand member references where Swift
requires key paths, plus a missing environment key-path prefix. These are now
corrected, and the station list has an explicit element type. Preserved ZIPs:

- `native-corrected-41495696602.zip`, SHA-256
  `e37789b2668f0360bad66055a2f2c6a95616ce62362f9d0e23457eb45524cc42`.
- `plex-compile-41496910543.zip`, SHA-256
  `de53063380126de39284e5dbede7fde6a43f938aceeb49c2fc8a22c43b659b6f`.

The second run's real host cargo check and **22 original Plex cases passed**
without warnings. Retain those passes for Plex tree
`4816e1f3e17a31cb972b7010cf3a86d4ca0f0718`. The accepted full host Rust check is
reusable only for unchanged bridge/core trees `69950e235d2c64dbd5817ca742d9eff48ff755d7`
and `46951aae1f450e6013ca10958d9f7be0aaf311b7`. Native builds and cases remain
separate required evidence.

The new Plex description and Access token field are now regenerated into all
sixteen Localizable.strings files, using only those two labels. Other accepted
translations are preserved. Native bundle lookups are still part of the pending
UI case. The combined corrective selection is the deduplicated union of all
24 unexecuted cases and the three new Plex cases, for 27 actual executions.

DSP build `41489407298` succeeded. Its outer artifact ZIP is
`music-dsp-41489407298.zip`, SHA-256
`bf52d661b8657d8a7cc0c27b6c0cd3ba3d155124aeef74489a25e59f5f755cc6`.
The inner Libavfilter archive SHA-256 is
`b3d8406c8ebf61018709e18fac526e13910e032b870ff9fe35ac4a1ef2f6934a`.
All 14 requested filter definitions and device arm64/simulator arm64+x86_64
slices were checked, with the matching deployed 8.1.2 ABI. This proves the
component build, not application integration or actual native effect execution.
Those two gates are still open. No subtitle production seek fix or new IPA is
claimed by these build results.

## Audio runtime integration candidate, 3 November

The verified Libavfilter component and matching package manifest are retained
under ios/AudioRuntime and ios/MPVKitMusic. Only this one non-GPL binary target
differs from the pinned package; the original remote URLs/checksums and package
shims remain intact. The archive, manifest, shims and notices are verified before
preparing a separate generated XcodeGen specification. The default project
continues to select the original remote MPVKit package.

The native capability bridge checks the actual loaded filter registry before
accepting an audio plan. This allows the original six parametric filter types,
crossfeed, reverb and four effects only where their filters are available.
License notices are included in the app's existing legal screen. No user-facing
effects editor or default-runtime switch is claimed by this integration step.

A new native case exercises all six original parametric types and crossfeed/
reverb, then applies each original effect and bypass to a real audio core while
seeking and retaining pause state. The candidate also needs the affected audio
transport and HTTP subtitle cases because the linked filter library changes.
Those executions are pending. The independent 27-case corrective run remains
41540825290 on source 0e95ae05 and is not restarted.

Local preparation and Python parsing passed. The supported changed YAML/JSON/
Markdown files pass formatting. The scoped pnpm check has no JavaScript or
TypeScript input to lint and exits before lint analysis; no TypeScript changed.
Apple parsing, linking and native filter execution remain CI gates.

The candidate validation is run 41544752262, source
0c4a120262ca1c8123677ce835b21bc88a793cee, with exactly five selected cases:
extended original filters/effects, existing audio transport, source switching,
and the two new HTTP subtitle journeys. It requests no package. Keep its
handle and artifacts independent from the 27-case default-runtime run.

## Parametric editor source port

The native audio form now selects graphic or parametric mode, uses the original
nineteen presets for either mode, and retains the inactive mode's draft. The
parametric editor supports 24 enabled/disabled filters, all six types, numeric
frequency/gain/Q editing, correction strength, draft/applied response curves,
and strict Equalizer APO / AutoEQ text import/export and sharing. Import edits
the draft and keeps output routing, sample rate and volume ceiling intact.
Export incorporates the current strength and automatic headroom as Desktop does.

The parser, exporter and response calculation are compiled directly from the
pinned original src/lib/music/parametric-eq.ts into a bounded, pure JavaScriptCore
context. It has no network or account bridge. The generator records the input
and executable hashes; native loading verifies the exact program hash.
Original strict command/size/filter/range rejection is preserved. Curves update
after a short cancellable debounce rather than on every SwiftUI body evaluation.
The pure context is retained in native view state across draft changes, so
dragging a control does not recreate the executable context each time.

The form also exposes the original supported sample-rate choices, crossfeed,
reverb and five speed presets. Controls requiring extra filters check the actual
runtime registry. Named custom speed/pitch/reverb/key combinations now persist
per Harbor profile, replace a same-named combination and can be removed. Loading
one edits those four draft fields only. A new case checks restart, replacement,
other-profile separation, invalid-value rejection and preservation of EQ,
preamp, routing and volume ceiling. This case remains pending native execution.
The new correction round-trip/native-plan case and phone/tablet-size plus RTL
editor captures are pending Apple execution and visual review. The existing
audio-form capture is affected by these new controls; its Spotify half remains
unchanged. No new IPA or complete Music parity is claimed.

The focused runner now preserves explicit passed/failed/skipped rows and
exports attachments even when xcodebuild returns a failing test status. A
nonzero status, missing execution, duplicate/restarted session or failed export
still prevents a clean result. This does not alter either already live run or
convert partial evidence into a passing validation.

## First actual combined native executions

Run 41540825290, source 0e95ae05, built successfully and executed all 27
selected cases once: 25 passed and two failed. There was no restart or skip.
The complete original artifact is combined-native-41540825290.zip, SHA-256
5d7b69cf5cfda5d21b00fb25b40e9100c5f7ed33f78a7bf49fc9a11a52b769c9.
The failing xcodebuild status prevented that old runner from exporting
attachments or final rows, so retain the original log/xcresult and export its
captures separately without repeating any tests.

All Jellyfin/Plex, M3U import, SoundCloud, Spotify adapter/labels, preferred
source, audio processing/profile/transport and movie-hash cases passed. The
LRC parser/native clock case and the Community-style downloaded VTT seek case
also passed. Connection/audio/Community captures still need visual review.
This does not establish a real Spotify account connection or physical-device
subtitle behavior.

The lyrics failure was the deliberate late-owner response: the worker correctly
rejected its retired scope, but its plugin-scope error escaped the native lyrics
adapter instead of becoming cancellation. The adapter now validates its scope
on the error path too. Only the affected lyrics-load journey needs repetition.

The small-cache HTTP case failed with video position stuck at 3 seconds and
EMBEDDED CUE 0; it did not demonstrate the reported subtitle-only drift while
video/audio advance normally. Its original 30-second GOP fixture has a single
keyframe and no Cues. A separate HTTP fixture now uses one-second closed GOPs
and explicit video/subtitle cue positions, retaining the original fixture and
accepted local test bytes. The same strict range/seek/render assertions remain.
This is a harness investigation, not a production subtitle seek correction.
The original unindexed/tiny-cache failure remains recorded here.

The new generator follows the public Matroska Cues recommendations and element
positions: https://www.matroska.org/technical/cues.html and
https://www.matroska.org/technical/elements.html. The new fixture SHA-256 is
3c42770cb9b0448dd732cda0c760b99219903b3eaed0a78105c02f809c7cb6f4;
the unchanged original is
f245cb2e8002fd89c42742a6166feb88399f9953092bedb1be6b787714540a54.
Both the changed HTTP journey and new listening controls remain pending native
execution. No broad repeat of the 25 passing cases is requested.

Run 41546821220 exported the original attachments successfully without building
or executing tests. Its archive SHA-256 is
a8dcea27c9169778d21859bf520b06d2fece48c790c668ea9212b536d336ccd4.
All twelve captures were inspected: phone/tablet-size Jellyfin, Plex connection
and loaded private covers, audio settings, Spotify setup, and Community glyphs
4/1 visibly drawn after seeking to 17/5 seconds. Controls fit without overlap;
the old audio layout is superseded by the pending new editor. These are window
sizes on the iPhone simulator, not physical-iPad validation.

That inspection found untranslated capability words in the original music
labels and an unmapped generic Open label in Spotify. The three capability
translations now reuse the already translated Browse/Play/Library values in
all sixteen native bundles. Spotify uses its existing Open on Spotify key.
No provider, audio or credential behavior changed for this wording follow-up.

The build log also contains the original GLES deprecations, Xcode's optional
AppIntents notice and quoted-sibling-include warnings from the unmodified
Spotify binary headers. The project disables only that vendor include-style
category, retaining Swift/API warnings and the exact SDK bytes. The next
affected Apple build must check that configuration; no existing test pass is
repeated solely for this diagnostic setting.

The six-case listening-controls run is 41546828656 on source 2370ec6c. It
contains three new parametric/speed cases, the changed audio form, the corrected
lyrics ownership case and the indexed HTTP journey. The five-case binary
candidate run remains 41544752262; neither live run is restarted. No IPA is
requested by either run.

## Extended runtime actually executed

Candidate run 41544752262, source 0c4a1202, compiled and executed five cases
without restart: four passed and the original unindexed/tiny-cache HTTP case
failed with the same position=3.0 / EMBEDDED CUE 0 as the baseline. The extended
case actually found all 14 filters and avfilter 11.14.102, applied all six
parametric types plus crossfeed/reverb to a real audio core, then applied each
effect, played/seeks/paused and bypassed them successfully. The audio transport,
source-switch and Community seek cases also passed. Do not repeat these
unchanged executions solely because the aggregate run failed elsewhere.

Original artifact SHA-256:
f4bace714ff818dad1d1c5afdc739c93d84e179c9580ebdc6f479fded12b9f17.
Export-only run 41548648421 retained its two Community captures, archive
d68187a6bb967511cec4bf34df3faa8958389df3692293c57ee925db88a7d563.
Both were visually inspected: the expected glyphs remain visible at 17/5
seconds under the changed library. No test was repeated for that export.
The package metadata now records this scoped native evidence. The original
component-build runtime.json is preserved. No default-package adoption, device
app link, physical-device reproduction or complete validation is claimed.

## Last.fm source port

The original browser-token/session flow and recording POST fields now have a
native profile-owned adapter. CryptoKit implements the original sorted UTF-8
MD5 protocol signature; the existing Rust network executor sends bounded
public-only HTTPS POSTs with redirects disabled. Keys, shared secret and
session are scoped in Keychain; pending auth stays in memory, expires after
its documented hour, and cannot save through a retired owner or account.
The native connection form shares the profile's metadata API key and retains
the original translated authorize/finish/profile/disconnect controls.

The native audio player's existing seek-resistant half-song/four-minute counter
now calls Last.fm after Subsonic bookkeeping. A failed Subsonic submission
cannot prevent Last.fm, matching Desktop's dispatcher; a Last.fm failure
affects the separate bookkeeping status, not playback. Spotify App Remote's
scrobble path remains separate unfinished work.

Three new native journeys cover the original signature vector, real owned HTTP
auth/session/submission and Unicode form fields, private-stream exclusion,
restart, actual player-clock eligibility/seek/duplicate/error separation,
Subsonic failure fallback, late-owner response rejection, and phone/tablet-size
forms with sixteen-language labels. Those cases and real-account use remain
pending. Source hashes and primary references are in lastfm-music-port-inputs.json.

Last.fm validation is run 41549661329 on source
42889557f2afceada9ec82c50332453de285c52c, ref ios/music-lastfm-94, with exactly
those three new cases and the verified runtime candidate selected. It requests
no IPA. The separate six-case controls/lyrics/indexed-HTTP run 41546828656 is
still live on its original source; keep that handle rather than restarting it.

## Listening controls: preserved results and visual follow-up

Run 41546828656 on exact source
2370ec6c25debee01ece5a83675ccc900515b9c1 executed exactly six cases without
restart: five passed and only the indexed HTTP subtitle journey failed.
The passing cases cover APO/headroom/profile routing, parametric rendering,
saved speed combinations, the audio/Spotify forms and the corrected lyrics
owner cancellation. The latter now cancels a retired profile cleanly.
Archive SHA-256 is
99dc7a2764564e392e41f9844bd06d113a6750e84e57ca9c66ba6ac8fc98e6a9.
Keep those five executions; do not rerun unaffected behavior because of the
separate subtitle failure.

All nine exported captures have been inspected. Phone and tablet-size layouts
are readable, with two actual follow-ups: the phone's equalizer mode value
truncates, and RTL mirrors the technical frequency axis. The mode now has its
own full-width row; only the two technical plots force left-to-right
coordinates while the surrounding interface keeps its chosen direction.
These small layout changes await subsequent visual confirmation. The old
Spotify Open wording in this source was already corrected in 57dbd09f.
These are simulator window sizes, not physical-iPad evidence.

The indexed HTTP failure reaches position 29.667, playing, with no text and
no playback error. Its old unlabeled wait does not identify the failing
phase. The follow-up keeps all targets, cache limits and cue assertions,
labels every seek phase, and attaches a bounded owned-cue timeline and
HTTP range offsets on failure. No production subtitle reset, reload,
decoder switch or speculative mpv option has been introduced.
The user's Obsession/Community case has Auto Sync disabled; the physical
subtitle-only drift after seeking is still unresolved.

## Spotify confirmed-position listening

The original half-song/four-minute Last.fm submission now has a separate
Spotify recorder driven by actual SDK getPlayerState responses rather than
the UI's interpolated position. Only one bounded request runs at a time.
Profile, credential and connection revisions reject stale callbacks.
Advertisements, episodes, known seeks, pause transitions and disconnected
intervals cannot contribute assumed listening time. Reconnecting the same
recording keeps its submission flag; an observed natural repeat starts a
new recording. Background playback is owned by Spotify, and Harbor does
not extrapolate listening after its official SDK connection is suspended.

The new owned-HTTP journey checks those transitions, one submission per
recording, actual Unicode form fields through the existing Last.fm path,
credential replacement and error separation. It does not authenticate a
real Spotify account or prove an actual Free-account SDK connection.
Native execution of this new case is pending. Last.fm's separate three
auth/native-player/UI cases retain run 41549661329 and are not restarted.
No IPA has been requested or created by these validation runs.

## Last.fm affected result and the next consolidated selection

Run 41549661329 executed exactly three cases on 42889557: late-profile
authorization and native phone/tablet-size forms passed; the native listening
journey failed. Archive SHA-256:
6f18dc6c1349cc2ee3c96890a2e50b83ed30b1401e5952420cd672f4e49b7779.
All four form/connected captures were inspected. They exposed untranslated
help/links and credential rows with no permanent caption once filled.
Four labels now have native translations in all sixteen languages, and the
two secure rows keep their captions. This changed form needs affected visual
confirmation; the unchanged late-owner pass is retained. The build log
confirms the vendor quoted-header warnings are gone; original GLES and
optional AppIntents notices remain.

The failed journey also used URL.path to compare a trailing slash, although
Foundation normalizes that accessor. The assertion now checks the actual
URLComponents path. Code inspection found the native player's eligibility
counter was only submitted on end/start/stop, so it could not submit at the
threshold while the recording kept playing. It now checks eligibility after
confirmed native clock events, retaining the existing once-only guard.
Wait failures identify their exact phase. This corrected journey must execute;
the earlier failed result is not counted as a pass.

The Spotify/indexed-HTTP run 41553486953 on 7bc7c947 terminated during its
35-minute native build deadline: zero test executions. Its evidence archive
SHA-256 is d3ba01fc79981f2e6a53b8790d522b7c9c1b30137cac17d4d2a8560e0b9fd65f.
No Swift error is present in the retained build log. The next single build
consolidates those unexecuted cases, the new session journeys and the affected
Last.fm follow-up. A bounded resource log will distinguish compiler pressure
from slow type checking. Build allowance is 45 minutes, with compiler process
group cleanup on timeout; the test selection and all assertions stay explicit.

## Paused music session restoration

The native player now retains the Desktop recording/queue/origin/resume
semantics using profile-owned protected atomic files. Queue serialization runs
off the main actor only when its revision changes; ordinary position updates
write a small checkpoint every two seconds. Pause, queue changes, stopping and
app inactivity flush the latest state. A failed write cannot interrupt audio.
The bootstrap probes asynchronously and only constructs a music workspace
when saved state exists. The dock restores paused and does not fetch a stream
until Play. Scope, request and resolver fences reject late restore replies.
Unknown duration and a replaced source retain their own checkpoint rules;
an interrupted/corrupt queue can recover the separately saved recording.
The original audio seeking and source-switch commands are unchanged.

Two new journeys cover protected file restart plus actual native HTTP audio
resume, queue/origin restoration without autoplay, private resolved URL
exclusion, unknown/end positions, substitute recovery and a delayed old-profile
read. Native execution remains pending. Detailed provenance is in
music-session-port-inputs.json. No new IPA or complete Music parity is claimed.

The consolidated affected run is 41731990004, job 126251424479, on exact source
0c0f5989fbe2275d111d2373ea9aa2651b7d6a64, ref ios/music-session-recovery-94.
It selects the two new session cases, the failed native Last.fm journey,
the subsequently changed Last.fm form, the unexecuted Spotify recorder case
and the unexecuted labeled indexed-HTTP follow-up. The Apple syntax parser
has passed; build and actual execution remain pending. No IPA is requested.

## Live beat-effect controls

The native audio panel now exposes Desktop's echo, delay, spiral and wide
bank, all eleven original beat divisions and depth, with a bounded manual
BPM control. The existing shared Rust DSP builds the exact original chain;
no new math or audio library is substituted. The previously accepted direct
native filter execution is retained. Touch edits coalesce for 90 ms as in
the original hook, and acknowledge the serialized audio core before publishing.

The player's temporary effect state survives a recording change while its
panel stays open, and is cleared when that owning audio panel closes.
Navigating into another page of that panel preserves it. Panel leases reject
late cleanup from an older view. A close during replacement-file loading
changes the effect revision, forcing the new core to receive the cleared
plan. Saving EQ/output settings preserves the active effect, while Keychain
preferences retain only normal listening settings. Profiles and player
requests cannot borrow another session's effect command.

New native journeys cover real paused audio and saved-processing preservation,
a delayed replacement load and stale-panel cleanup, and the new controls in
phone/tablet-size and Arabic RTL captures. Only nine labels per language were
generated; all other translations were preserved. Those new executions are
pending. This adds the beat-effect bank; the complete DJ deck, scratch,
release effects, waveform and second deck remain unfinished Music work.
Source provenance is in music-beat-effects-port-inputs.json. No IPA is built.
