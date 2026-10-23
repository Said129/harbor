# Native Edge narration

The final original beta is preserved separately at commit
`8274f05485554e531cf5654574de84108f16bdb7`. Its reader, narration, reader-state
and `ebook_tts.rs` sources match the existing `0834340` reference after line-ending
normalization. The new voice/sample asset records the exact original commit and
normalized reader SHA-256. All twenty fallback voices and original language and
locale preview samples are extracted without rewriting their content.

The native iPhone/iPad reader now has Edge voice selection and search, language
filtering, pre-listening, generation progress/cancel, pause/resume/stop, playback
position/remaining time, seeking and playback speed. It starts at the current
passage, follows spoken paragraphs in continuous and printed-book modes, and
stops on chapter/mode/source changes or reader dismissal. The original growing
700/1500/3000/4000-character windows prefetch one subsequent window. Paragraph
updates are published only when the spoken paragraph changes, rather than on
every audio tick. Native controls remain available when generation fails.

`URLSessionWebSocketTask` implements the same Edge protocol as the original's
pinned `kothok-edge-tts 0.2.10`: GEC authentication, SSML, 24 kHz mono MP3, word
boundaries and ticks, Unicode-safe 3600-byte chunks, 500000-scalar maximum, voice
and locale validation, neutral synthesis rate, clock-skew retry and idle timeout.
Cancellation closes the actual socket and rejects late playback. The original
MIT notice is bundled and readable in the voice panel. No new Rust dependency
or JavaScript network bridge is required.

Generated audio and boundaries have a thirty-day cache protected and separated
by profile. Full SHA-256 identities include voice, locale, rate and text. Failed
cache writes do not prevent playback, clearing one profile preserves other
profiles, and an in-flight generation cannot recreate a cleared cache. The app
also offers available device voices. Narration options belong to the existing
profile settings mirror; the old narration-rate key is preserved for compatibility.

An independent public voice-list observation on 2026-10-23 returned HTTP 200,
322 voices including 45 Spanish voices. This is evidence of the catalogue only,
not of Apple WebSocket synthesis or complete narration playback.

Six new native cases cover the exact wire vector/metadata and original samples,
Unicode chunk/SSML/window rules, real protected cache/timelines/owner separation,
actual AVAudioPlayer playback/pause/seek/rate/resume/stop, actual narrator task
cancellation and a live native Edge catalogue/MP3 synthesis integration. The
playback fixture is eight seconds of newly generated silence; it contains no
book, voice recording, account or key. Two new UI cases capture search/selection,
restoration and rotated panels on ordinary fresh iPhone/iPad guests.

The affected combined selection is eleven native cases (six new narration and
five still-unexecuted notes), eight necessary fresh preparations and eight UI
methods: twenty-seven executions and forty-eight required original captures.
Four UI methods retry actual failed search/translation interactions; the other
four are new notes/narration routes. Previously approved, unchanged cases stay
retained. No IPA is requested by this validation.

Run 39947821170 stopped during compilation with zero actual test executions.
Its original diagnostic reports an expression type-check timeout in the large
reader body, following the earlier corrected shadowed-property diagnostic.
Reader surface, footer, menu, lifecycle, persistence and settings now have
separate SwiftUI expressions; their existing actions remain intact. Apple
compilation and all new native/UI results remain pending. Full reader chrome,
localization, motion, text-identity migration and the complete app parity audit
are still open; this increment does not establish a finished port.
