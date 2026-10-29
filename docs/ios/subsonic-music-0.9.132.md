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
are owned fixtures; they have not executed on Apple yet, and do not claim a
live private server or audio playback test.

This implements the private-server service. Connection settings, routing it
through the Music catalog/source chooser, and the shared remote audio player
remain to be connected. It does not replace the existing local audio player
or certify the whole Music section. No IPA is built by this increment.
