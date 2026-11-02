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
