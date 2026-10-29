# Shared music playback integration

The production catalog now starts playback through the same player used for imported files. A remote recording carries its real metadata and optional genuine local record; it never receives an invented local filename. Catalog track rows, collection Play/Shuffle actions, context actions, the mini player and the full player use the shared recording queue. Existing local-file callers remain supported.

`MusicAudioEngine` serializes creation, loading, events, controls and destruction of libmpv on a dedicated actor. Blocking core setup and destruction run outside the main actor. Monotonic request identifiers reject older opens, stops and controls; a fresh core per load also prevents late old-file events or HTTP headers from becoming state for a new recording. The engine copies events into sendable values before returning them to the interface. Position, duration, loaded state and pause come from actual mpv events.

`MusicPlayback` checks the session lease before and after source resolution and engine admission. A stopped or superseded resolution cannot publish its old audio. Active playback also checks profile activation and private credential revision. `AppModel` retains one music workspace per active profile, so leaving and reopening the Music page keeps the same credential owner and does not restart a playing song. A locked app cannot acquire a playable workspace.

The already validated complete Desktop queue class supplies shuffle preview, Next, Previous/history, manual priority and repeat behavior. Its program and existing 610-state fixture are unchanged and are not executed again in this selection. Upcoming entries are cached on queue/current/mode changes rather than encoding the entire queue on every playback clock tick. A separate transport view observes the clock. Video interruption, operating-system transport controls, seeking and volume remain available. Eligible listening uses actual small position advances before scrobbling; a failed private request shows a generic translated message.

Only 27 affected labels are selected in the existing 16 languages: 22 Desktop-derived labels and five messages specific to mobile integration. The other accepted labels and translations are preserved. The fixture has 432 comparisons.

## Focused validation

The new selection has eight native executions:

- Real libmpv playback of an owned WAV over loopback HTTP using the actual Subsonic resolver, followed by an actually imported local file; pause for video, resume, seek and Next.
- Real HTTP request headers, including commas, backslashes and quotes; stale engine requests cannot replace, pause or stop a newer core.
- Held old resolutions, Stop and profile retirement with explicitly controlled engine events.
- Queue preview/history, manual versus automatic repeat, priority, collection-origin adoption and eligible scrobbling.
- A locked application cannot obtain a playable workspace.
- The 432 affected label comparisons.
- Actual production player metadata, transport and queue mounts at compact and regular sizes, using decoded owned artwork. Four original captures are required.
- The affected private-server mount, connecting in the same production view. Four further originals are required to inspect the previously missing connected-state titles.

At implementation time these eight cases are unexecuted. The preflight checks selections, existing proof, label resources and the real workflow shell; it does not prove Apple compilation, audio playback or visual correctness. The selection retains 30 other nearby unique native passes. Real audio uses only loopback fixtures and owned imported files; controlled-event cases and independent mounts do not prove ordinary user navigation or physical-device behavior.

## Remaining scope

This integration does not complete Desktop Music parity. Matching and provider fallback, the source chooser, additional source clients, full mixed-playlist and personal-history interfaces, lyrics, DSP/quality, session checkpoints, prewarming, casting and remaining original layouts and animations still require implementation or evidence. Ordinary app journeys and physical iPhone/iPad performance remain unverified. The full application objective remains open; this gate creates no IPA.
