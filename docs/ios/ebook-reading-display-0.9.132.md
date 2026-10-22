# Reader display and native font import — in integration

The native reader adds Desktop's page width (520–1080, default 768), brightness
(55–120%, default 100%) and persistent focus mode. Page width is offered in
regular-width iPad layouts; compact layouts use the available width. The RGB
brightness multiplier is a small native Metal shader. It is disabled at the
default 100% so ordinary reading does not add an extra color-effect pass. The
setting affects the reader, without changing the device's system brightness.

TTF/OTF import follows Desktop's 32 MiB per-font limit and short display name.
Files are coordinated through the system document picker, validated with Core
Graphics and stored in a protected directory per normal profile. Duplicate
imports reuse the content identity. Only the selected font is loaded. The
reader creates a Core Text font directly from that file and bridges it to
[SwiftUI Font](<https://developer.apple.com/documentation/swiftui/font/init(_:)>);
it never registers an imported name globally across profiles. Deleting a
selected font returns to the built-in literary face. Corrupt or missing files
keep text readable with the built-in fallback.

Font selection, brightness, page width, focus and chapter presentation belong
to the existing profile settings document. Font bytes remain local. WOFF/WOFF2
conversion, Desktop's paginated book renderer, annotations, translation and
complete narration controls remain in scope; this increment does not mark the
reader as complete.

Two new native cases cover actual bundled-font import, Core Text creation,
restoration, duplicate import, deletion, profile isolation, malformed/oversized
files, invalid identities and cancellation. Apple compilation, shader rendering
and the new reader/font interfaces still require execution and review. No
previous approved tests or final IPA are produced by this implementation step.
