# Native Navidrome and Subsonic service

The provider follows the pinned Desktop Subsonic client, response models,
conversion functions and catalog operations. It tries Navidrome's token
exchange first, then the original salted Subsonic authentication when that
exchange is unavailable. A successful ping precedes the atomic owner-scoped
Keychain write. The password is used only for pairing and is never persisted.
Failed authentication or storage retains the previous pairing.

Requests preserve API version 1.16.1, Harbor client identity, the 20-second
timeout, form query encoding, untranscoded audio and sized cover URLs. Each
request checks the active profile and credential revision before and after
transport. Retired profile and disconnected-source responses cannot publish
results or save credentials. Cached pairing is hidden when its activation is
retired. Response decoding runs outside the main actor and checks the lease
again before returning the decoded catalog.

The six original Home feeds, typed search, track-only search, disc/track album
order, artist fanout over four albums with a 30-track limit, and playlist order
are implemented. Concurrent feed or album failures preserve the successful
results. Source identity and recording metadata match the Desktop converter;
resolution returns an authenticated full-audio URL and sends the original
now-playing scrobble. Submission converts the original listening start time
from seconds to milliseconds with the same saturated multiplication.

Six new native cases cover request/token/response contracts, exchanged pairing,
salted fallback and failed writes, catalog partial results/order/concurrency,
late profile and credential responses, and actual owner Keychain persistence
with recovery from network and authentication errors. Their transport replies
are owned fixtures. Apple run 40871194110, source
`28f7ee165e7d4765731e9c791f381bd44e2492a0`, executed all six: six passed,
zero failed or skipped. Its original 53,940-byte evidence archive has SHA-256
`68f3d934b5d62b8850fc2a6e4f4c9a0276870dd1fb18e0815cb85e0415dd1c4d`,
matching GitHub's digest. This does not claim a live private server or audio
playback test. The run introduced one Sendable-closure warning in the fan-out
helper; its correction and the one affected concurrency case require the next
Apple gate. Run 40874840049/source `9b81c8caca3758a06efd9db92a2b4e955cb263b7`
subsequently compiled the correction with zero new compiler warnings and passed
that affected fan-out case. The remaining issue in that follow-up concerns its
new connection mount lifecycle and one timing-dependent catalog assertion,
not the retained six service cases. Those service cases are not selected again.

The follow-up described in `music-server-catalog-0.9.132.md` connects server
settings and catalog routing. Full source selection and shared remote audio
playback remain open. This does not replace the existing local audio player
or certify the whole Music section. No IPA is built by these validation slices.
