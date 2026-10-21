# Native reading catalog parity

Reference: Desktop 0.9.132, commit `0834340cec5531650bfe78cd628628702e636987`.

The native Books catalog combines Gutenberg and enabled reading plugins, publishes
completed source pages as they arrive, preserves individual cursors, and keeps
usable results when another source fails. At most four providers load at once.
Queries shorter than two UTF-16 code units retain browsing, matching Desktop.

Pinned original pure functions implement work identity, duplicate grouping,
category/genre/status/original-language filters, ordering and display titles.
Every readable provider route remains available in the native book detail view.
Apply/Reset retain Desktop's draft/applied filter distinction. Content language
is independent of original language; tags are forwarded only to providers that
declare support for them. Manga tag selection uses the original empty-query
search contract and the selected provider's offset.

The pure catalog program runs in a serial JavaScriptCore actor, outside the UI
actor. It exports no account, network, filesystem or native-object bridge and
never evaluates installed code. Source plugins retain the existing separate
WebKit runtime. Catalog program: 9,089 UTF-8 bytes, SHA-256
`53346856ad401229d174d033c070b0bddfa6aea1536a96541b11c346f63d41b1`.

New reference checks executed locally: 21 catalog cases and two source-tag cases.
Native JavaScriptCore, real worker/tag integration and phone/tablet navigation
still require the selected Apple CI execution. Node checks are not native or
visual approval. Existing unrelated successful suites are retained.

This block does not complete the entire Desktop port. HTML source editors,
external metadata enrichment/discovery, remaining settings and the complete
interface/animation audit remain part of the active goal. No IPA is produced by
this block; delivery remains one consolidated validated IPA.
