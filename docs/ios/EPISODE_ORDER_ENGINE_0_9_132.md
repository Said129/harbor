# Episode-order engine — work in progress

Reference: Desktop 0.9.132, commit `0834340cec5531650bfe78cd628628702e636987`, specifically `src/lib/providers/tvdb.ts` and `tvdb-order.ts`.

The native engine now represents Aired, DVD, clean Absolute, raw TVDB Absolute, Alternate and Regional order. It discovers advertised orders, checks whether they contain episodes, reads their pages through the existing public metadata transport, and builds season buckets with counts and date ranges. Requested text falls back per field to English and then the provider's original text. The existing bounded response cache and request coalescing are reused.

Clean Absolute joins regular episodes in canonical broadcast order and excludes specials. Raw TVDB Absolute preserves the provider's sequence, including specials. Ordered slots retain canonical and alternative coordinates separately. Duplicate IDs are placed once; duplicate canonical pairs use unique alternative pairs for presentation while keeping their original canonical reference. Playable `Episode` IDs, watched-bit ordering, streams and resume records are untouched by this component.

Nine new XCTest cases cover the six modes, discovery and shared requests, requested/English/original text, season names and dates, language mappings, duplicate IDs/coordinates and bounded pagination. The `episode-order` CI scope selects those nine cases only, authenticates the actual Xcode result tree, preserves partial failure evidence and disables IPA packaging. Synthetic provider replies test the new engine; they do not establish public-service availability or visual parity.

At introduction, Apple compilation and those nine actual outcomes are pending. Local Python compilation and selection generation pass. `pnpm run check` formats the YAML but exits before lint analysis because these Swift/Python paths have no supported lint targets. Earlier unrelated successful tests are retained.

This is a provider-engine component, not a completed episode panel. Still required: connect its buckets to real playable episode and franchise identities, port the full season/order/extras interface and settings, apply the chosen order consistently to player navigation, and review the actual iPhone/iPad interface and motion. The full Desktop port remains active and no new IPA is created here. The previous conversational 75% is not an audited completion metric.
