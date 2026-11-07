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

The original measured eight-band visualizer also requires bandpass,
asetnsamples and anullsink, which are absent from the currently packaged
14-filter extension. The next component build enables those three definitions
using the same pinned FFmpeg/SDK/ABI. This prepares the actual original
analysis graph instead of fabricating animation levels. The accepted
14-filter archive and current application package remain in place; a new
component must be verified and exercised before integration. No meter,
spectrum or visualizer behavior is claimed implemented by this build change.

Beat-effect validation is run 41734304782, job 126259401921, on source
d5eacba8da14d4a8eab993bed5f12bab5be29862, ref ios/music-beat-effects-94.
It selects only the three new player/ownership/control journeys, including
the changed full audio form captures. The separate six-case session/Last.fm/
Spotify/indexed-HTTP run 41731990004 remains live on its original source.
Neither run is restarted or requests an IPA.

The additional analysis-filter component is run 41734710275, job
126260802189, source cb230f53dcf782eff0d7cb3586a5d8060a8306d9,
ref ios/music-meter-runtime-94. It is building device and both simulator
slices; the verified packaged 14-filter candidate remains unchanged.

## Measured music levels and spectrum

The native implementation now mirrors the pinned telemetry and spectrum
graph, its eight frequencies, playback-timed bounded history, RMS/peak
metadata and original display mapping. No random bars or volume-derived
values are used. Profile preferences control the level panel and visualizer.
Analysis consumers share leases; the last hidden/inactive consumer releases
the filter, and stale revisions cannot restart a retired audio core.
Reduced motion suppresses the spectrum animation. Measurement updates stay
inside the small meter views; system playback-clock publication is bounded.

Two new native journeys are prepared: generated stereo tones, silence and
seeks against the actual native graph; and shared-consumer retirement plus
phone, tablet and Arabic captures. The fixture is owned generated audio and
is included only in test resources. Detailed source hashes and adaptations
are in music-meter-port-inputs.json. Native execution waits for the additional
three analysis filters; the packaged 14-filter candidate is still unchanged.
No new IPA, verified meter behavior or completed Music parity is claimed.

## Consolidated native results, 3 November

Run 41731990004 on 0c0f5989 executed exactly the six selected cases without
a restart. Four passed: Last.fm authorization/native-clock submission, its
changed phone/tablet and sixteen-language form, profile-owned corrupt/late
checkpoint recovery, and confirmed Spotify position accounting. Preserve
these passes for their unchanged areas. The four exported Last.fm images
were opened and visually reviewed: translated copy, permanent credential
captions and connected state fit the phone and tablet layouts.
The artifact SHA-256 is
b523e08de144f3c282adbc6a168938c76e03c9e5441c1c873a052e4d1733c0a6.

The native HTTP checkpoint journey failed because its resolver used the
owned publisher's root URL, which deliberately returns HTTP 404. The test
now points at the existing /audio.wav endpoint. No production playback or
checkpoint workaround was added. Failure attachments now identify the
exact phase and both players' bounded public states.

The indexed HTTP subtitle case failed at the playing seek to 21 seconds.
Its trace observed 5.667 seconds, then 23.667 after a three-second observation
gap, then the correct CUE 6 at 24 seconds. Delay and FPS correction stayed
zero. The 21-second CUE 5 observation window was missed; the evidence does
not prove that this cue was rendered incorrectly or explain the user's
physical-device drift. The same assertion is retained, with three bounded
post-seek frame captures and draw timing added to distinguish the rendered
subtitle from observation delays. No production subtitle reset, decoder
change or seek-option workaround is applied.

The user confirms Auto Sync was disabled in the physical Obsession /
Community Subtitles example. The affected HTTP follow-up now explicitly
sets the same preference for that case and restores it afterward.

## Native queue editing

The queue panel now presents the current recording, raw upcoming items and
previous history like the original queue component. Native editing handles
reorder only upcoming items; swipe removal and play-next are available.
Clear removes upcoming items and priority-next while retaining the current
recording and history. Reordering does not reopen the decoder, seek or change
pause state. Owner, queue revision, current identity and active resolver
reject delayed actions from a replaced queue or profile.

Two new affected journeys cover multi-item moves, clear, invalid offsets,
retired queue/profile actions and phone/tablet/Arabic layouts. They reuse the
accepted original order planner instead of changing its shuffle math.
These executions and new captures remain pending. Only eight original
interface labels were selected; the existing catalogs already contained them,
so no translation catalogs changed. Provenance is in
music-queue-editing-port-inputs.json.

Local checks: the owned meter WAV's format, silence, independent tone
projections and eight original source hashes pass. The new eight-band graph
also produces all named band metadata in the separate Windows FFmpeg tool;
this is not Apple-runtime evidence. The required vp check accepts formatting
for the changed JSON/Markdown/YAML but exits because none are lintable source
files. Swift type checking and actual native execution remain the Apple
runner's responsibility; unchanged Windows Apple/Linux toolchain limitations
are retained without another retry.

The resource trace from the completed six-case run also shows simulator
services consuming CPU throughout compilation. The focused runner now boots
the selected simulator after build-for-testing, preserving its existing
runtime overlay preparation, destination, selections and assertions. This
changes validation scheduling only; no application option or timeout is
relaxed. Actual speed improvement must be measured in the next affected run.

The native compiler cache also now retains its input timestamps by verified
SHA-256 content. A new checkout normally gives every unchanged source a fresh
date. Only byte-identical files in the known native source/project/framework
roots can recover the cached date; changed bytes retain their new timestamp.
The manifest stays inside the existing intermediate cache. It cannot name
extra files to mutate, and symlink/out-of-root inputs are rejected. The helper
only runs in isolated CI, not against the user's checkout. This is preparation
for useful incremental builds; no build-speed claim is made before execution.

## Queued source replacement and analysis component

The queue can now choose another source for an upcoming or previous recording
without touching the current decoder. It runs the already accepted original
selectableSources and replaceQueueTrack program: one non-offline alternative
per service, original requested credits and collection identity retained.
Replacing a priority-next recording updates that priority to its chosen
source. A queue/profile revision invalidates an open chooser and late results;
lookup generations prevent a cancelled lookup from hiding a newer load.
The current source picker retains its playback-switch behavior.

A new affected journey searches the real owned local library through the
native session, captures the queued chooser on phone/tablet/Arabic, changes
only the pending source and checks that the current decoder stays untouched,
then verifies priority-next opens the selected owned file. Original policy
math is unchanged; the accepted 48 decision cases are not repeated.

The seventeen-filter component run 41734710275 succeeded on cb230f53. The
downloaded artifact matches GitHub SHA-256
1048d901b19c5b9ea62135e3e0140a978f99baa86b743dea3865d74b4637e57d;
its component is
1e38b1df04dc3f4bf990ec011b6a1074850955bd8bcf55be2a21e807430ac0ec.
Actual archive CPU tags cover arm64 device and arm64/x86_64 simulator, and
ten public headers, licenses and the upstream FFmpeg patch match the accepted
component. The candidate archive is replaced for the next affected execution;
the accepted fourteen-filter archive/evidence is preserved separately. New
native execution is explicitly unverified. The default project and delivered
IPA 93 remain unchanged.

## Beat-effect results and affected follow-up

Run 41734304782 on d5eacba8 executed all three selected cases without a
restart. The delayed replacement/old-panel ownership case passed and is
retained unchanged. The control case reported a pass, but visual review of
all five images found that the Arabic capture contained only the section
heading: model initialization had not produced controls before capture.
The two Spanish effect panels and revised audio forms fit their viewports.
This does not establish the missing Arabic controls as visually validated.

The section now shows a loading indicator while its model initializes,
disables a retired panel, and its capture waits for the actual owning lease.
The affected control case must run again, including the new meter switches
enabled by the seventeen-filter candidate. An assertion pass alone is not
accepted as proof that those controls rendered.

The native effect journey timed out during initial audio. Its host log
reports missing default output device ID 0 and a 0 Hz RemoteIO format.
The simulator host will receive the official BlackHole 2ch 0.7.1 package,
verified against SHA-256
57b540f27a3e29c37e310e01bee0fdfab76733087e47f997ef9dccf851400dcf
from the primary Homebrew cask. A small CoreAudio helper verifies a live
48 kHz default route before testing. It runs only in disposable macOS CI;
the driver/helper are not linked or embedded in Harbor, and no app audio
fallback, DSP bypass or test assertion is substituted. The failed journey
now attaches its exact phase and bounded player/output state.

The original evidence archive is retained with SHA-256
7aba03a686f9fe53221fa37aea2d724009ff5164a490c070a8e08a5e17a07315.
The next selection comprises nine new, failed or visually incomplete cases:
two meters, three queue operations/chooser cases, the corrected HTTP
checkpoint, indexed subtitle observation, and the two affected effect cases.
Unchanged Last.fm/Spotify/recovery and replacement-panel passes are excluded.

The affected run is 41744308491, job 126293354047, on exact source
4bec28886b74e84fe154a4573906054ff9ff23f1, ref ios/music-validation-94.
Apple's syntax parser and the isolated 48 kHz CoreAudio route preparation
both passed. Native build and the nine selected executions remain pending.
No IPA is requested by this run.

Further validations will reuse that branch so the native compiler cache can
be shared across its runs. GitHub's cache API showed older caches confined
to separate sibling refs; restore-key prefixes do not bypass that isolation.
The existing source-time manifest enables content-verified timestamp reuse
after this first prepared build. No compilation-speed result is claimed yet.
Primary reference:
https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching#restrictions-for-accessing-a-cache

The CI-only audio package download was independently checked before dispatch:
103,021 bytes and the pinned Homebrew SHA-256. A descriptive Harbor CI user
agent and binary Accept header are required by the upstream download endpoint;
its default Python request returned 406. The verified request is now used by
the CI setup. Primary package record:
https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/b/blackhole-2ch.rb

## Native build accepted; initial simulator installation incomplete

Run 41744308491 is terminal. Its source 4bec28886b compiled the app and
changed test target successfully with the seventeen-filter candidate.
Only the recorded OpenGLES/AppIntents baseline warnings appear. Both
pre-build and post-build CoreAudio route checks read a live 48 kHz device.
The simulator completed its initial migration/boot, but installation then
exceeded the old 90-second limit. None of the nine selected tests executed;
this is not a test pass or a demonstrated app/subtitle failure.

The downloaded 40,727-byte artifact 13283164123 matches GitHub's digest
cce84daa58b9e229a1545c1c48c94f8621590ada94962950db32e232a996d689.
Its original build log, resource trace, route proof and the complete job log
are retained outside the repository. No xcresult was produced.

Installation now has a bounded 300-second phase with its own output and
resource trace; boot/install/build results are recorded separately. The
next execution retains the same nine unexecuted cases and compiler cache,
without repeating earlier approved tests or requesting an IPA.

The new exact-source follow-up is run 41831413613, job 126579263610,
source 69f581ccc695a06cddc051dff91e086a6f0289e4, on the same validation
branch. It keeps the nine unexecuted cases. The earlier failed attempt to
dispatch the reusable ios-focused.yml directly returned 404 and created no
run; dispatch through the registered ios.yml entry point succeeded.

## Artwork colours and responsive expanded presentation

The five whole original colour functions are extracted from canonical Git
source, with independently checked input/program digests. A separate
evaluation of the complete original Desktop module agrees with the native
bundle on 73 cases; five malformed inputs are rejected. This is Node
evidence only. Nineteen vectors and an owned two-colour lossless image are
prepared for actual JavaScriptCore/ImageIO execution.

Mini-player/play/seek/spectrum colours now follow the actual cover, using
the original contrast, Oklch tone and sRGB mixes. Disabling colours removes
them immediately; only numeric content-hashed results are cached. Local
covers and the existing public/private artwork paths are reused off the UI
actor, with session/recording/credential fences. Original colour, level and
visualizer switches appear directly in the expanded player and retain all
sixteen original labels. Their selected translation update produced no
catalogue differences.

The expanded artwork grows with compact screens and sits beside metadata
and controls at tablet widths, retaining original maximums and spacing.
Two new focused native cases cover independent reference vectors, actual
image decoding, cancellation, profile/disable fences and phone/tablet/Arabic
captures. They remain unexecuted and the images unreviewed. The complete
expanded panels, visuals and other Music gaps are still pending; this does
not establish full Music or port completion. No IPA is packaged.

## Review of run 41831413613 and meter follow-up (4 November, handoff)

The handoff ZIP matched its published SHA-256 and all 16,970 manifest
entries. Run 41831413613 executed nine cases on 69f581cc: seven passed and
both meter cases failed. The seven passes are retained; only the cases whose
producers change below are selected again.

Of the 20 exported images, 18 were opened; the remaining two are
byte-identical (SHA-256) to an opened one. The HTTP offsets text was read. Subtitle
frames: embedded and external captures show CUE 1 at 5 s, CUE 4 at 17 s and
CUE 5 after the playing seek to 21 s. The three external 21 s frames
(observed, paused-after-seek and pending-cue) are byte-identical, i.e. the
same rendered CUE 5 frame held while paused. The fixture video is a static
red/green split, so these images prove cue selection for each target, not
alignment against moving video; they do not reproduce the physical drift.
Music images reviewed: measured phone levels and
eight bands (L -15.0 / R -21.1 dBFS, real analysis, no invented frames);
Spanish phone/tablet and Arabic beat-effect controls (the Arabic panel now
renders, unlike 41734304782); revised audio forms with both new switches;
editable queue on phone/tablet/Arabic. Two visual findings remain:

- The Arabic queued-source capture shows "no matching source" while the
  Spanish captures list the owned alternative. The picker started with
  loading=false, so any frame before its lookup task ran already claimed
  "none". Desktop's picker starts with useState(true). The case passed, but
  the image does not validate the RTL chooser.
- Arabic queue artwork placeholders were still loading in their capture.
  This is a capture-timing observation, not a confirmed defect.

The connector label "Local file" stays untranslated, as in Desktop, where
it comes from the native matcher's connector name.

Meter failures, from the job log and attachments:

- testOriginalMeasuredNativeBands... threw music-meter-unavailable after
  1.4 s from MusicAudioEngine.setMetering. The log cannot distinguish the
  initial enable from the disable after both seeks; mpv messages are off.
- testOwnedMeterConsumers... reached and attached the phone capture, then
  timed out about 10.9 s later with no tablet image. That fits either the
  wait for the closed phone views to remove harbor_meter or the tablet
  views' acquire wait; the old messages were identical. The new phase labels
  separate them. A release that fails in setMetering(false) is recorded
  silently and leaves the branch attached.

Changes, all from Desktop 0.9.132 behaviour (telemetry.rs, audio-meter.ts,
music-source-picker.tsx):

- The engine toggles only the labelled branch with `af add <graph>` and
  `af remove @harbor_meter`, synchronously, as Desktop's set_enabled does,
  instead of rewriting the whole audible chain. Processing changes still
  write processing plus meter, as Desktop's audio_filters does. A rejected
  toggle keeps a bounded diagnostic (operation, mpv status and message).
- The meter view no longer ends its polling loop on a missing or
  other-recording snapshot; like Desktop's monitor it keeps the live
  consumer, shows no stale reading and retries. Only real cancellation
  releases it.
- The source picker starts in its loading state and reports the settled
  candidate count through an optional callback.
- Tests: each meter toggle names its phase and includes the mpv diagnostic;
  release/acquire waits name their capture; the queued-source captures wait
  for the finished lookup and require the alternative in all three images.

No root cause is claimed until these run on Apple. This Windows host has no
Swift, Git, GitHub CLI, Python or Node; nothing here was compiled or
executed. Affected selection for the next run (seven HarborChangedTests
cases, one build):

    MusicMeterTests/testOriginalMeasuredNativeBandsFollowSeeksAndSilenceWithoutChangingTheListeningPlan
    MusicMeterTests/testOwnedMeterConsumersReleaseAnalysisAndRenderPhoneTabletAndArabicWithoutInventedFrames
    MusicQueueEditingTests/testQueuedSourceAlternativesUseTheOwnedLibraryAndPreserveCurrentAudioAndPriority
    MusicArtworkTests/testOriginalArtworkVectorsAndActualImageDecodingRetainTransparentAndStableTieSemantics
    MusicArtworkTests/testOwnedArtworkColoursRenderResponsivePlayerAndRespectDisableAndProfileRetirement
    MusicEffectsTests/testBeatEffectControlsRenderWithTouchTargetsOnPhoneTabletAndRightToLeft
    MusicAudioTests/testAudioAndSpotifyConnectionInterfacesRenderOnPhoneAndTablet

The two artwork cases have never executed; that build is also the first
Apple compilation of the uncommitted artwork sources; the second of them
mounts the changed MusicPlayerView and MusicMiniPlayer. The last two were
accepted before, but the audio form they capture gains the artwork-colour
switch. SharedMusicPlaybackMountTests also mounts the changed expanded
player, but it belongs to the HarborTests module (it depends on
SharedMusicPlaybackTests); it stays pending for the integrated validation
rather than widening this focused module.

Retained without re-execution, because nothing they exercise changes:
queue reordering and queue-control rendering (MusicQueueView, row and
cover are untouched), the paused HTTP checkpoint (session and checkpoint
code untouched), live beat effects (engine processing and effects paths
untouched; the new toggle is only reached through metering), and the HTTP
subtitle observation (no player or subtitle file changed).

The physical subtitle drift is unchanged. On iOS mpv composes subtitles in
the rendered frame (vo=libmpv, sub-add); no Harbor code changes sub-delay or
sub-fps on seek. No production subtitle change is made without the
owner's answer (previous lines vs. correct lines shifted) and the stream type.

Owner answer, 4 November: the displayed lines are the correct ones,
shifted by a few seconds; the stream came from AIOStreams (stream type
unknown). External subtitles are downloaded whole, written unchanged and
preloaded by mpv from disk, and mpv renders them against each frame's pts;
requests already carry videoHash/videoSize/filename. Two explanations fit
and need opposite fixes: the subtitle belongs to another release (cut or
23.976/24 fps difference, so the offset depends on the episode position and
only becomes visible far from the start), or the stream's timestamps after
a seek differ from those of linear playback. A seek back to the first
minutes distinguishes them: back in sync means a release/timing mismatch,
still shifted means a seek-time defect. No production change until then.
The owner cannot run that check yet; it stays pending.

## Now-playing detail tabs

The expanded player now groups its details like Desktop's now-playing panel
(music-now-playing.tsx): a segmented "music.now.details" control with
"music.now.next", "Lyrics" and "music.now.signal", plus the open-queue
action. The queue panel keeps the existing upcoming rows, all-tracks list
and row actions; the lyrics panel is the existing synced-lyrics view.

The signal panel ports music-signal-details.tsx and lib/music/quality.ts:
the declared source stage (codec or local extension, depth only for
non-lossy sources, decoded rate, bitrate, unverified when undeclared) and
the output stage (current route, negotiated output rate read from the
decoder, equalizer, ReplayGain and crossfeed state). Tiers, ranges and the
kHz label follow the original exactly; no value is inferred.

Desktop's fourth tab, "music.artist.about" (compact artist overview,
recording credits, where to buy, soundtrack link), is not offered yet: the
sheet has no catalog client for the credit links and the overview,
where-to-buy and soundtrack pieces are not ported. Lyric-tab disabling
when lyrics are switched off and the in-panel search are also pending.
All labels already exist in the sixteen catalogues; none were added.

New native case MusicSignalDetailsTests (original tier vectors and
phone/tablet/Arabic captures) joins the focused module; it is unexecuted.

## Now-playing "About" tab and the original artist profile (uncompiled)

The expanded player now has Desktop's four detail tabs in its order: up
next, about, lyrics, signal. About is offered while a playback session
exists, because it needs a profile-scoped metadata client and the player is
mounted by the app shell, outside the music screen that owns the shared one
(MusicPlaybackSession.makeArtistMetadataClient).

The artist data is not re-implemented. build-music-artist-assets.mjs now
pins three more original Desktop modules by SHA-256 (artist-profile.ts,
artist-genre-cache.ts, source-link.ts; twelve inputs in total) and exposes
the operations profile, cancelProfile and parseProfile of the same worker
that already runs the roster, statistics and recording code. The only host
shim added is ./local-store without persistence, next to the existing
safe-fetch, debug and secret-store shims. The unmodified generator was first
run and reproduced the committed asset byte for byte, so the regenerated
program (SHA-256 02fb263e3723f4ac5e937dd58b9a07bf70cd11e1d0a1e2adc3e9a8d721f5d9bc)
differs only by the new modules. The Swift pin in MusicArtistAsset.read() is
updated to that digest and to twelve inputs.

The transport allows two more public hosts for it: www.wikidata.org and the
two or three letter \*.wikipedia.org summaries. Everything else, including
look-alike hosts, is still refused.

The independent expectation is build-music-artist-profile-fixture.mjs: it
runs the pinned program in Node against owned MusicBrainz, Wikidata and
Wikipedia responses and stores the outputs in
music-artist-profile-reference.json. In that evaluation the original code
drops the ended relation, the loopback address, Google Play and duplicate
URLs, sorts genres by popularity, keeps one qobuz store link, identifies
Deezer, Spotify and YouTube Music sources and rejects a profile fetched for a
different identity. These Node results are not Apple evidence.

New view code: MusicArtistOverviewView (portrait, name, biography with read
more, origin, active years, aliases, genres, Wikipedia source, connections,
links around the web, MusicBrainz) and MusicWhereToBuyView (stores and
merchandise from the profile plus the Bandcamp search), wired into the About
tab together with the existing recording credits. The profile falls back to
the original resolveArtist when the recording has no verified primary artist.

Not ported yet: the soundtrack link (Cinemeta match), the artist gallery
modal, the tour and event extras, the linked biography, genre navigation
from a chip, and member portraits. MusicArtistProfileTests adds four
unexecuted native cases (parser against the Node evaluation, the real worker
against owned responses and hosts, the host and URL policy, and
phone/tablet/Arabic captures). Nothing here is compiled; it joins the next
batched validation, with MusicSignalDetailsTests and the pending meter case.

## Run 41844742608 (da648bfb)

Artifact 13331927916, SHA-256
7bdeb16afab39f23be3b49aa6bb6c10b9a2165c17c294405214464c307151288 (verified).
The artwork sources compiled on Apple for the first time. Passed: artwork
colours in the responsive player, both audio-form captures, beat-effect
controls and the queued-source chooser; its Arabic capture now lists the
owned alternative. Failed, with causes:

- Measured bands: enable-before-load threw with no mpv diagnostic. The
  actor's synchronous setMetering/meterSnapshot lost overload resolution in
  the async test to the protocol extension's unavailable defaults, so the
  engine was never reached (also the 41831413613 failure). Both are now
  async like their requirements.
- Owned consumers: release-phone timed out, mpv=none. Hiding the capture
  window did not close the views; the test now removes both consumers from
  the visible hierarchy, the production close path, before tearing down.
- Artwork vectors: all 19 passed; actual decoding returned the bottom
  colour of the owned two-colour image. The pixel reader flipped a bitmap
  context that already stores its top row first; the flip is removed. The
  phone/Arabic player captures show the blue (bottom) palette from this bug.

"Unknown artist" in captures is Desktop's own native placeholder data.

## Run 41849651852 (2ccdd217)

Artifact 13335847994, SHA-256
ac644f857dc0470485fba5a4083b1ef71a399dc844db57feaa94b874c858401b (verified).
Five of six passed and are retained: measured native bands, both artwork
cases (19 vectors and the top-first tie), and both signal-detail cases.
Reviewed capture: the phone signal tab shows "Alta resolución sin pérdida",
FLAC, 24 bits, 96 kHz, 2400 kbps and the selected output; the Arabic and
tablet captures were exported but not yet opened. The player controls in
the artwork capture still use a blue accent for a red/blue cover; whether
that slot matches Desktop's selection is not verified.

Still failing: the owned-consumers case. The phone capture is attached, then
the closed views leave harbor_meter in the chain (mpv=none, so no rejected
toggle). The cause is not established. The failure message now reports the
live consumer count, whether a signal exists, the exact af string, phase,
loaded and position, to separate a leaked lease, a rejected release and a
track that ended. Only this case is rerun.

Run 41854576393 (75ca13f0) produced no result: GitHub reported "The job was
not acquired by Runner of type hosted even after multiple attempts" and
cancelled it after 15 minutes. It is an infrastructure failure, not a test
result, and the same single case is dispatched again.

Run 41857532741 and run 41860272503 hit the same hosted-runner
acquisition failure (macos-15-intel, 15 minutes each, no test executed)
while GitHub reported Actions operational. The focused workflow now takes
its Apple host from the existing apple_runner input (default unchanged,
macos-15-intel); the native cache key already includes the architecture, so
an arm64 host starts cold. The next dispatch uses macos-15.

Run 41865981171 on macos-15 also never acquired a runner. Its annotation
says that, due to capacity constraints, jobs targeting macOS arm64 runners
may experience longer queue times. Four consecutive dispatches (two Intel
after the earlier success, one more Intel, one arm64) produced no test
result. The pending case is unchanged and still has to run on Apple
hardware; it is retried when macOS capacity returns, not repeated blindly.

Subtitles, owner report 4 November (later): the shift appears after seeking
forward or backward, with audio and video in sync. A wrong-release subtitle
would be in sync again near the start, so this leans toward a seek-time
defect. The static red/green fixture cannot show it; reproducing it needs
moving content with burned-in timecode and cues keyed to it, served over
HTTP Range. Not built yet.

The owner then confirmed the shift is constant: it does not grow with the
episode position or the seek distance. That excludes frame-rate or ratio
drift (which would grow) and a mismatched edit that only appears far from
the start. What remains is a fixed offset between the picture's timeline and
the subtitle's after a seek, for example a stream start time that is
rebased differently once mpv seeks, or timestamps that restart in a new
segment. Candidate inputs for the reproduction: a Matroska stream with a
non-zero first timestamp, B-frame reordering and sparse keyframes, served
through the existing Range fixture, with cues keyed to a timecode burned
into the picture; the measured quantity is displayed timecode versus the
cue shown, per seek. No production change is made before that measurement.

Streaming sources panel, 4 November (uncompiled, no CI): Desktop's Filters,
Sorting and Picker tabs are ported with their effect on the stream list
(wait time, stream priority, source mode, Stremio layout, picker details);
details and open items are in REMAINING_PORT_PLAN_2026-11-04.md item 2. New
focused cases: StreamSourcePolicyTests (9 cases, one through the real Rust
ranking). They join the batched run when macOS runners return.

Progressive stream results, 4 November (uncompiled, no CI): the picker now
fills as addons answer and automatic play settles with Desktop's timings
instead of waiting for every addon, which removes the 30 s hold the new
default wait introduced. Details in REMAINING_PORT_PLAN_2026-11-04.md item 2;
three more StreamSourcePolicyTests cases (settle floors, episode checks and
confident start, debrid merge), 12 in that class.

Owner decision, 4 November: match Desktop. The picker applies the safety
filter with Desktop's recovery (0 made it through + Search wider, Only 1/2
sources + Show everything anyway, no debrid configured + Set up a debrid) and
the layout defaults to Stremio. Condensed-picker UI tests pin the layout with
a launch argument; the synthetic caption flow also turns the filter off.
Uncompiled; two more StreamSourcePolicyTests cases (14 in that class).

5 November, macOS runner available again (autonomous session). The first
focused dispatch (run 41955266363, macos-15-intel) acquired a runner in
seconds. Findings so far: the Rust workspace compiles and `harbor-core`'s tests
pass (97 before the Desktop 0.9.132 sync of trust, parser and types, 109 after
it, including Desktop's own tests); the Swift app compiled with the Debrid,
streaming sources, progressive results and filtered picker; the only errors were
a duplicate type name (`StreamPickerFilter`) and a test property named `hash`
that clashes with `NSObject.hash`, both fixed. Dispatching a new run cancels the
one in progress, so each run must finish before the next. The pending Music and
subtitle cases from this log are part of the same selection and are reported with
the run that finishes them.

Focused run 41958341805 (commit ad3fd8d2, macos-15-intel): the app and the test
bundle compiled, `harbor-core` passed 109 tests, and 50 of the 53 selected cases
passed, among them every Debrid, stream policy, sleep timer, A-B loop, auto-skip,
playback speed, magnet-link and Music artist/artwork/signal case of the selection.
Three failed: the stream-language test compared a `JSONValue` with `nil` (a missing
key is `.null`); the owned-meter test let its twelve-second tones end before the
captures began (position 12.0, loaded false), so it now loops the track; and the
artist overview capture never saw its profile requests, so the view's task now
starts on a container instead of an empty `Group` and the capture waits longer for
the web worker. Run 42011211733 (commit 92a633a3) reruns those three together
with the seven new still-watching, hotkey and Watch on cases.

Focused run 42011211733 (commit 92a633a3): 9 of 10 passed: the artist overview
capture (its profile task now starts on a container), the stream-language test,
and the still-watching, hotkey and Watch on cases, which also shows that the
Easynews card, the hotkeys and the player check-in compiled. The owned-meter case
still failed: the looped track gets past the capture but is restarting (no signal,
phase resolving) when the release is checked, so the release wait now asks for no
consumers and no filter instead of an explicit false, and the loop waits for the
track to be loaded before it seeks. Run 42015909434 (commit 8866e84a) covers the
AniList and MyAnimeList tracker cases (27) with the first of those changes.

Focused run 42015909434 (commit 8866e84a): the app and the tests compiled, and all
27 AniList and MyAnimeList cases passed on the first execution (sign-in codes and
addresses, the rate-limit retry, GraphQL and HTTP errors, token refresh and
rejection, the request allow-lists, tracker targets from Kitsu stream ids, the
90 s and 70 % phases, forward-only sync plans, the form and GraphQL writes, the
unconfirmed-write retry, and the account stores). The owned-meter case still
failed: the seek to the start was ignored while the looped track restarted, so
each capture now starts the track again instead (commit 3158e6f8, run
42021364643, together with the six StreamPlaybackHistoryTests cases for
"Remember last stream").

Focused run 42021364643 (commit 3158e6f8): all 7 cases passed, including the
owned-meter case that had failed in every earlier run. Starting the track again
for each capture (instead of looping it) leaves every capture a freshly loaded,
playing track, and the release wait accepts the no-signal state. The six
StreamPlaybackHistoryTests cases for "Remember last stream" passed on their first
execution. With this, no Music case from this log is open on the Apple side;
the physical subtitle drift remains unreproduced.
Run 42025901122 (commit 0c9f5c01) executes the three retained picker cases of the
HarborTests module (automatic playback order, manual picker sources under the
automatic filters, the direct source picker layout) against the new build, which
also compiles the automatic retry chain, "Remember last stream" in the detail
flow and the episode sort menu.

Focused run 42025901122 (commit 0c9f5c01): the app compiled with the automatic retry
chain, "Remember last stream" in the detail flow and the episode sort menu, and the
three retained HarborTests picker cases passed (automatic playback order,
manual picker sources under the automatic filters, the direct source picker
layout). Run 42107765914 (commit 37239570) executes the three HiddenEpisodesTests
cases for "Hide and skip episodes", which are the only new code not yet compiled.
Still not run on Apple: the LiveNavigation and PlayerCaption UI flows whose launch
arguments changed, and the automatic retry chain itself (it needs a source that
fails to resolve).

Focused run 42107765914 (commit 37239570): the app compiled and the three
HiddenEpisodesTests cases passed (the store per show/season/number, Up Next
stepping over hidden episodes while the playing one keeps its neighbours, and a
multi-entry anime using each entry's own hidden episodes). Run 10 (commit 47661760) compiles the player screen lock and repeats the player cases that share
PlayerView (check-in, hotkeys, auto-skip).

Focused run 42112564237 (commit 47661760): the app compiled with the player screen
lock and the five player cases that share PlayerView passed (check-in, hotkeys,
auto-skip). The lock itself has no unit case: it is a view-state feature to be
checked on a device (lock button in the top bar, touches ignored, Unlock controls
shown for 2.2 s after a touch).

Focused run 42118442254 (commit 66337ffa): all 11 cases passed and the app compiled
with the audio filter chain (5 cases: normalizer, each profile, stacking and the
limiter, nothing sent while off, saved options without the new keys), the playback
stats card (4 cases: mpv string parsing, bitrate units, row order and translation)
and the new `i` hotkey (2 existing shortcut cases). Run 42132367263 (commit
00f91191) executes the five TraktCommentsTests cases.

Focused run 42132367263 (commit 00f91191): the app compiled with the Trakt comments
section and its five TraktCommentsTests cases passed (comment parsing with its
fallbacks, the age buckets, movie/show/anime/unidentified targets with their paths
and Trakt links, the request with its API headers and paging and no account, and
failures answering an empty list). Run 42135176976 (commit decaf0b7) executes the
subtitle sync indicator cases (format, fallbacks, defaults, Shift fine steps).

Focused run 42135176976 (commit decaf0b7): the app compiled with the subtitle sync
indicator and all 6 cases passed (4 SubtitleOffsetIndicatorTests: whole-millisecond
format with a plus sign for positive delays, position and size fallbacks like
Desktop, on at the bottom by default with saved options still decoding, Shift
halving the delay step; 2 PlayerShortcutTests: no shared key chord, seek steps).
The indicator overlay itself is a view-state feature to be checked on a device.
The physical subtitle drift after a seek is still not reproduced in CI.

## OMDb and MDBList ratings on the detail page (7 November)

Desktop's `lib/providers/omdb.ts`, `mdblist.ts`, `views/detail/hero-ratings.tsx`,
`library-panel/provider-keys.tsx` and the Details column of `ratings-matrix.tsx` are
ported. `OmdbService` (actor) keeps scores for 90 days, remembers misses for a day,
counts the 1,000-request daily allowance from UTC midnight, stops when the key is
refused or the allowance is spent, and saving a key resets the budget as Desktop's
`resetOmdbBudget` does. `MdblistService` tries the api endpoint then the legacy one,
keeps a result for a day and a failure for a minute, and does not reuse an answer
across keys. Keys live in the Keychain per profile (`ProviderKeyStore`); the detail
page shows Rotten Tomatoes critics and audience, Letterboxd, Metacritic (MDBList's
value, else OMDb's Metascore), Trakt, SIMKL and MDBList chips with Desktop's links,
and each provider can be turned off in Settings > Metadata > Set up rating providers.

Not ported, recorded as partial: the Cards column (score chips on posters), OMDb awards
and season ratings, the budget panel, the SIMKL community rating (the chip uses
MDBList's SIMKL value), the MAL chip for anime, RPDB and Fanart.

Reviewed before the first compile: the Keychain store is keyed by the settings owner
on both screens (the detail page first used the personal owner and would have looked
in another profile's keys); the OMDb key is never cached on disk (the metadata
session has no URL cache); a corrected OMDb key now clears an earlier refusal.
`ProviderRatingsTests` has 12 cases. Run 14 compiles it.

After the review that followed the push: the detail page asks OMDb without a type, as
Desktop's `detail.tsx` does (MDBList still gets movie or show); both screens read the
keys under `MetadataPreferences.shared.settingsOwner`; every Details default on Desktop
is true, which the empty hidden set matches. These edits are not in run 14 and need the
next run.

Focused run 42312093016 (commit a36c55b4): the app compiled with the ratings work and all 12
ProviderRatingsTests cases passed (OMDb reply parsing and fallbacks, certified-fresh
threshold, error classes, UTC-midnight budget and prefetch share, cache for 90 days and
across restarts, refused key until reset, misses and the daily limit, prefetch reserve,
MDBList parsing and aliases, legacy endpoint, day and minute caches, the ratings row
with order, links and rounding, the matrix list and Metacritic colours). The chips row
itself is a view-state feature to be checked on a device.

## Calendar sources (7 November)

The calendar had only "My library". It now has Desktop's source switcher for the five
sources that need no Simkl account or filter builder: My library, All upcoming (TMDB
discover pages 1 and 2 for movies and TV plus upcoming movies of the month, one item per
title, anime left to its own source), My Trakt (`/calendars/my/shows` and `/movies` from
today for 31 days, or up to 7 x 31 six months ahead; nothing for past months or beyond six
months), Trakt anticipated (`/shows/anticipated` and `/movies/anticipated`, premieres
listed before movies) and Anime (AniList airing schedule, three pages at a time up to ten,
adult titles and movies left out). Posters, ratings and genres for Trakt titles come from
Cinemeta; "Animation" or "Anime" in the genres marks a title as anime. Desktop's id rules
are kept (`id:season:episode`, `:premiere`, `mal:`/`anilist:`); a Trakt title without an
IMDb id opens through its TMDB id instead of Desktop's `trakt:` id, which Harbor cannot
open. Events open the title through `calendarToMeta`'s rules (`CalendarItem.media`).

Also ported: the type filter row (All, Movies, TV) and "Watchlist only" for All upcoming,
Desktop's empty-month cards with their per-source texts, the "needs a TMDB key" card with
an Open settings button, and the source kept in the profile (`calendar.source`). The
type filter stays on My library too (an iOS addition: Desktop has none there).

Not ported, recorded as partial: Simkl and Simkl premieres, the Custom source and its
filters, the Sub/Dub switch (the dub schedule feed), the games source (excluded), the day
modal, release chips and airing countdown, opening an episode from an event (Desktop's
`calendarEpisodeHint`), and hiding anime through `hideContent.anime`.

Simkl premieres (Desktop's `simkl-anticipated`) followed: the three public catalogs of
`data.simkl.in/calendar/v2/{year}/{month}/` (tv, anime, movie_release) joined with each
title's shared metadata, shown only while a Simkl account is connected (the same rule as
Desktop's switcher), with the type filters including Anime. A title Simkl knows only by its
MAL id opens through `mal:` (Desktop's `simkl:` id cannot be opened). My Simkl needs
Desktop's library-calendar resolver (TMDB, TVMaze and AniZip) and is not ported.

`CalendarSourcesTests` has 15 cases. Run 15 compiles it together with the review edits of
the ratings work.

## SIMKL community rating on the detail page (7 November)

Desktop's SIMKL chip shows SIMKL's own community score, read from the Harbor server's
`/api/simkl/ratings?ids=imdb:tt...` proxy, and falls back to the copy MDBList carries. Harbor's
community server answers the same endpoint (checked with one read of a public title, which
returned `{"ratings":{"imdb:tt0111161":{"rating":9.1,"votes":10380}}}`). `SimklCommunityRatings`
asks up to 120 lower-cased specs per request, remembers scores and "none" after an HTTP error,
and asks again after a network failure, as Desktop does. The chip needs no provider key and
follows the SIMKL toggle in the ratings matrix. Settings row 42 moves to ported. The cards'
SIMKL score and the anime specs (`mal:`, `kitsu:`) are not wired yet.

`ProviderRatingsTests` now has 15 cases; run 15 should include the three new ones.

## Anime Sub/Dub in the calendar (7 November)

The Anime source gets Desktop's Sub/Dub switch. Sub is the AniList schedule as before; Dub reads
the AniSchedule dub feed (`raw.githubusercontent.com/RockinChaos/AniSchedule/.../dub-schedule.json`),
kept for 30 minutes and falling back to the last good copy when a read fails (`AnimeDubFeed`),
and maps it with Desktop's `mapDubFeedToCalendar` rules (episode date in the month, adult titles
and movies left out, titles from the media then the feed, one item per episode). The empty month
has its own text ("No dubbed episodes this month"). Spanish texts for the switch were added to the
native translations because Desktop's Spanish catalog lacks them.

`CalendarSourcesTests` has 16 cases.

## Large uncompiled block (7 November, usage limit reached)

Ported without compiling (Actions disabled for the repository, owner chose to keep porting):
episode IMDb ratings on the episode picture (community server `/api/imdb/episodes/{tt}` plus OMDb
season ratings, setting `showEpisodeRating`); player short seek steps (3 s by default, Desktop's
eight choices), "Ask before leaving" (Esc confirm with "Don't ask me again") and maximum volume
boost (mpv `volume-max`); the Custom calendar source (people, genres, providers, origin countries,
media types, Trakt sources, filter sheet, person search). The earlier short-seek default of 5 s was
wrong and is now 3 s as on Desktop. New cases: EpisodeRatingsTests (5), PlayerControlSettingsTests (4)
and 5 Custom cases in CalendarSourcesTests (21 in all). Not started: hide watched/unreleased titles in
home catalogs (`hideWatchedInCatalogs`, `hideUnreleased`), watchlist saved-only, Letterboxd,
seasonSourceLock, autoNextStreamOnStall, My Simkl. Run 15 must cover every case of CalendarSourcesTests,
ProviderRatingsTests, EpisodeRatingsTests and PlayerControlSettingsTests, and the existing PlayerShortcutTests.

## Usefulness review (7 November)

The owner asked that nothing be ported unless it is useful on iPhone or iPad. Before porting more, every
Missing item was reviewed: 19 behaviors and 60 settings with no real use on a phone or tablet are now Excluded
with a recorded reason (see the audit script and report). Kept as useful, to be ported later: casting
(Chromecast, DLNA, Roku), Watch Together, a remote streaming server (the way to get torrents on iOS),
Letterboxd, AniList and MAL lists, local file import, seek previews, content notifications, Theme Studio
(without the code editor), card rating chips, AI search with the person's own keys.

## Haiku trial: hide watched and unreleased titles (7 November)

Written by a Haiku subagent from a precise brief, in its own worktree and branch
`ios/haiku-trial-home-filters` (commit `7d061d2a`), then fast-forwarded into this branch. It added
`HomeCatalogFilter` (Desktop's `isUnreleased`, `metaTitleKey`, `watchTitleKey` and the watched test), the
two settings (`hideWatchedInCatalogs`, `hideUnreleased`), the filter in `DiscoveryRails`, and 11 cases in
`HomeCatalogFilterTests`. By reading, the Swift matches the brief and Desktop's rules. Two things were not
the model's doing: the translation script failed in the fresh worktree (it lacks the Node dependencies),
so the four labels were generated here; and the toggles were moved from "Episode cards" to "Home layout",
where Desktop has them. Not compiled yet; the CI result for these 11 cases and the build is the measure of
the trial.

## Haiku trial, second round (7 November)

Two more Haiku subagents, each in its own worktree and branch, then merged here (three small conflicts in
the settings files resolved by hand). `ios/haiku-trial-library-watchlist` (`6ab79d4e`): the setting
`libraryBookmarkedOnly` (default on, same behavior as before) and `LibraryWatchlistFilter`; off also lists
unstarted entries Stremio auto-added, and joins them to the Trakt projection without duplicates.
`ios/haiku-trial-continue-watching` (`28f12eb0`): `cwAdvanceNext` through `ContinueWatchingAdvance` and an
`advanceNext` parameter of `ContinueWatchingPresentation`. It stopped on its own for `cwHideCaughtUp`: iOS
keeps finished series in Continue Watching and a filter would need per-title episode lists in a broad
change; that setting stays Missing. Known gap it reported: with `cwAdvanceNext` off, tapping the card still
plays the next episode because `DetailView.playTitle` calls `EpisodeSequence.startingEpisode` directly.
Both reports named the compile-sensitive spots; nothing is compiled. New cases: LibraryWatchlistFilterTests
(3), ContinueWatchingSettingsTests (4), plus HomeCatalogFilterTests (11) from the first round.

## CI runs 15 to 21 and the third Haiku round (7 November)

Runs 15 to 19 stopped at the compiler: one escaping-closure error in the filter sheet, then "unable to type-check
this expression in reasonable time" on the player's long modifier chain, which was already at the limit. Fixed by
moving the filter sheet's content out of the closure, the leave confirm into its own modifier, and splitting the
chain into `withTrackers` and `withStateObservers`. Run 20 compiled the app: 64 of 65 cases passed, all 18 cases
written by Haiku included; the one failure was the calendar source order (Anime before Simkl premieres), fixed
to Desktop's order and rechecked by run 21.

Third round, merged here: `ios/haiku-trial-display-settings` (`2f5baf57`): `hidePosterTitles` on poster cards
(TV cards keep their title); it stopped on `streamBackdropBlur` because the iOS picker draws no backdrop, so that
setting is now Excluded. `ios/haiku-trial-home-languages` (`8ca3944d`): `homeLanguages` filtering Home catalog
and discovery rows by original language (exact match, titles without a language stay) and `animeOnlyInAnimeRoom`
(default on as on Desktop: Home Continue Watching leaves anime out; the Anime tab keeps its own row). The language
filter runs once in `HomeView` because `DiscoveryRails` is shared with other pages. Not compiled yet.

## Fourth Haiku round (8 November)

Run 22 (20 cases: the Haiku display and home-language pieces plus the calendar source order) passed in full.
Four more pieces were written by Haiku in separate worktrees and merged here after review: watching statistics
(`WatchStatistics`, `WatchStatisticsView`, entry in the library header, `wrappedButton`), AniList lists and the
recommended rail (read-only screen opened from the AniList settings), Theme Studio import/export with a per-profile
theme library and a custom background image (`ThemeLibrary`, `ThemeBackgroundStore`, `ThemeBackdrop` at the app root),
and catalog pins/hides with the Customize list plus Home `homeShowAllAddonRows`. Excluded with reasons: `top10RibbonSide`
(no ribbon on iOS cards), `homeNewEpisodes` (no per-series new-episode pipeline yet), `preferCustomMetaAddon` (iOS already
asks addons before Cinemeta), `resumeDetailScroll` (needs DetailView), top genres/people in statistics (Desktop fetches them
over the network). Status: CI run 23 green. The background image screens are transparent over `ThemeBackdrop`; that layering has
not been looked at on a device.

## Fifth and sixth Haiku rounds (8 November)

Fifth round, merged after review (CI run 24 green): score chips on poster cards (RT, Popcornmeter, MAL, Metacritic, Letterboxd,
MDBList, Trakt, SIMKL, with the limit and the top/bottom placement), Letterboxd through Stremboxd (settings, session in the
Keychain, Home rails), episode layouts (list, strip, grid, card scale, TMDB story arcs on plain series) and the Continue
Watching settings (caught-up hiding, end-of-series timer, episode stills, the New Episodes row). Excluded with reasons:
`hdEpisodeImages` (iOS never builds TMDB still URLs), snapshot retention and quality (iOS stores the position only),
`animeCardRating` (no IMDb title source for anime), the Letterboxd profile card (no profile surface).

Sixth round (CI run 25 pending): remote streaming server (address, strict policy, health, URL and transcode builders; torrent streams
now resolve through it in `HarborService.resolve`, after the debrid services or first when the profile has none), people
search with a person page (cast now opens it), AI search with OpenRouter or Groq keys (an "AI search" entry in search),
and the optional subtitle providers (SUBDL and Subsource are searched but their archives and key-protected files are
filtered out until the player can load them). These hooks are wired and compiled, but only the parsing, policy and
request building are covered by tests: nothing was exercised against a real server, Wyzie or an AI provider. The
decode-error transcode retry is still not wired.

## Regression runs 25 to 28 (8 November)

Run 24 (66 cases, round 5) and run 25 (85 cases, round 6) passed in full. Run 26 re-ran 35 older and new classes
(375 cases) over the shared code that rounds 4 to 6 touched: 372 passed and 3 failed, all in `SubtitleSeekTests`
(real mpv seeks on a simulator GL surface): `testDownloadedCommunityWebVTTCuesFollowSeeksAfterResumingMidVideo` and
`testEmbeddedAndExternalCuesFollowForwardBackwardAndPausedSeeks` never reached the paused start (position 0.0, "Native
seek did not settle"), and `testHTTPRangeSeeksRetainEmbeddedAndExternalCuesAndRenderedSubtitles` missed its playing-seek
window (position 29.7 instead of 21 to 23). Run 27 (side branch `ios/wip-simkl-batch`, 37 cases) ran the three SIMKL batching tests, CardRatingsTests,
ProviderRatingsTests and then SubtitleSeekTests: everything passed except two of the three seek cases. That shows the
failure is not specific to the 375-case run, but it was not a solo run of the seek tests: three other classes ran before
them. Run 28 (`ios/wip-seek-bisect`, branch cut at `02278d3e`, the commit before the player control settings; run 42343468637) runs the three seek cases alone on that older commit; its result was not read before the shutdown.
To read it fairly, run SubtitleSeekTests alone on `d01dfff8` as well, so the commit is the only difference: both fail
means the cause is older or environmental; the old commit passes and the head fails means a regression from tonight's
player changes (`volume-max` and the short seek steps in `PlaybackOptions.mpvOptions`, the player helper splits); the
head passes alone means the earlier tests in the same run interfere with the real-time seek tests. Nothing in these
cases exercises the new subtitle provider hook, which only appends candidates after the addon search.

SIMKL poster chips now share one request across cards (`SimklCommunityRatings.coalescedRating`, 60 ms window, batches of
120), as Desktop's card lookups do; three tests passed in run 27.

## animeOnlyInAnimeRoom decision

The owner delegated the default of `animeOnlyInAnimeRoom` to the assistant. It stays ON, as on Desktop: Home's
Continue Watching leaves anime out, the Anime tab keeps its own Continue Watching row, and Settings, Interface has a
"Keep anime in the Anime room only" switch to show anime on Home as well. Reason: the target is a 1:1 port of Desktop
0.9.132, whose default is on, and nothing is lost because the anime row is one tab away.

## Seventh Haiku round (8 November)

Written by Haiku in separate worktrees, merged after review, hooks wired by hand (CI run 31 green, 80 cases): Wikidata awards on the detail
page (`TitleAwardsSection` after the media gallery), the local video library (files or folders from the Files app kept as
bookmarks, grouped like Desktop, an entry next to the library's Local tab), local notifications for upcoming episodes and
releases (refreshed after the library syncs when the app is active; no background modes), and the stall-switching and
season-source-lock policies with their settings. The season lock is wired in `DetailModel` (saved after a pick, applied
to the automatic start); the stall switch only has its policy and setting, because Desktop's rule is a first-load check
that needs the player's loaded state fed back to the detail model. Excluded with reasons: award tabs on poster cards,
instant playback preparation, NFO artwork, background scanning.

## Eighth Haiku round and the seek-test bisect (8 November)

Eighth round, written by Haiku and merged after review (CI run 32 green (43 cases), cast run green (36 cases)): Live TV in search plus Desktop's region top-network rows
on the channel list, Critics Pick on Discover, addon sharing and recommendations on the addon detail, and casting to a
Roku or a DLNA renderer (protocol code, controller, sheet and a cast button in the player controls, hidden when the stream
needs headers or a local file; AirPlay keeps its own picker). The cast branch was validated on `ios/wip-cast` (36 cases)
before it joined the development branch. Not ported: Chromecast, SSDP discovery, cast transcoding.

`SubtitleSeekTests` bisect (real mpv seeks): the old commit `02278d3e` passes 3 of 3 twice, hours apart (runs 28 and 33),
so the runner is not the cause. `44ef42fb` passes 3 of 3. `002e1b32` and every later commit fail two of three (the failure
is always the `playing seek 21` step, position 29.667, no subtitle text). Removing `volume-max` does not change it. The
change therefore sits in the four commits between `44ef42fb` and `002e1b32` (the poster-title setting, the home-language
filter and anime-only Continue Watching, and their merges); runs on `2f5baf57` and `8ca3944d` narrow it further.
