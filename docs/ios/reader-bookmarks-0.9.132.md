# Reader bookmarks from Desktop 0.9.132

Reference: `0834340cec5531650bfe78cd628628702e636987`,
`src/views/ebook/harbor-reader.tsx` and `src/lib/ebook/reader-state.ts`.

Saving the current text passage opens the bookmark panel. The newest bookmark
comes first, saving the same passage replaces the older entry, and the list is
capped at 300. Cards show volume, chapter and one-based passage labels, with the
original 140 UTF-16-unit preview and an individual delete control. The layout
wraps the badges when the phone or text size needs more width.

New bookmarks carry the original chapter source ID. A changed display order
therefore resolves the same chapter; a removed source ID cannot silently jump
to a different chapter at the old numeric position. Existing positional iOS
bookmarks decode without the new fields and are upgraded on the next successful
open, reversing the former append order once. Legacy records did not retain
source IDs, so chapter identity before that first upgrade cannot be recovered
if a provider already reordered them.

A bookmark within the loaded chapter issues the existing reader jump without
refetching the chapter. Another chapter uses its source route. The encrypted
profile shelf retains the list across relaunch, and delayed position writes
merge into the latest list. No new account or background request is added.

Validation selection: two new native contracts, two fresh guest preparations
and two new phone/tablet UI methods, with twelve original captures. The prior
28 native contracts, public metadata integration and five Rust font tests are
retained. The independent reader-interface run is 39933605950 at source 5349c4.
Apple execution of this bookmark increment remains pending until its own
original results are collected. No IPA is produced by this selection.

While reading the search UI case, its expected query after an explicit edit was
corrected from the pre-edit value to `readable`. This is an assertion correction;
the currently executing older source is left intact so other results survive.
