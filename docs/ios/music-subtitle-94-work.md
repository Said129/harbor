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
restrictions and authenticated browsing remain unverified. New mobile Spotify
setup/consent paragraphs still need full localization. Existing original Music
labels have been transferred for all sixteen Desktop languages.

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
