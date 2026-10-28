# Home lists from Desktop 0.9.132

Reference: `0834340cec5531650bfe78cd628628702e636987`, the owner's preserved Desktop 0.9.132 tree. This increment implements Home rows made from My lists. Apple compilation, native results and original interface captures are pending; the implementation alone is not an approval of full parity or a stable IPA.

## Reference behavior

The original `listHomeRows` and `availableListRows` memos in `src/views/home.tsx` select nonempty, existing lists in saved `homeRows.listRows` order. Empty/deleted lists do not render; available choices exclude already selected lists. Names are literal user data, including duplicate names. Source rows precede list rows, which precede ordinary catalogs. `src/lib/home-customization.ts` supplies add/remove, visibility, order, names, numeral choices and hero selection.

The external `build_home_lists_reference.mjs` executes the complete original customization module and the two extracted original memo callbacks. The checked-in fixture contains six selections, thirteen consecutive mutations and two visible/editing layout projections; it records both original file hashes. No provider requests run during fixture generation. This proves the reference data's origin, not execution of the native implementation.

## Native behavior

Home exposes **Add from lists** while editing and uses the existing poster, rank, row controls, hero and poster animation components. A selected list can be renamed for Home, moved, hidden, numbered when it has at least ten titles, used as the hero source, or removed from Home. Removing the row preserves the list. Reset clears supported Home customization, list references and custom source rows.

`listRows` remains in the existing raw Desktop projection rather than adding a required field to the older native Codable layout. Saving only a list reference invokes the normal Harbor layout sync queue. The wire map recognizes absent list references as well, retaining their names, hidden/rank/hero choices until the list becomes available. Atomic saved projections, stale activation checks and independent-profile fallback follow the existing layout machinery. Unknown future wire fields remain preserved during supported edits/reset.

Cached list media retains addon origin and raw provider episode IDs. This deliberately preserves information omitted by Desktop's small Home memo projection. The normal metadata and playback routes use the stored origin rather than replacing a provider episode coordinate with its display number.

## Reading and mobile adaptations

An explicit View all action opens the ordinary list detail in the navigation stack. Manga items open the normal Manga detail instead of video details; a Manga hero uses **Read**, resumes the reader and offers the information route. Local PDF first-page artwork is eligible for the hero even when the imported item has no public poster URL.

Home and My lists read their owner's Manga shelf/connection snapshot off the main thread once per active list context. Visible Manga artwork reuses the normal Manga image loader, including private local PDF/archive pages and authenticated configured sources. Saved books must match the item's identity and title and belong to the current owner's snapshot; configured server/plugin checks remain required. Remote saved IDs absent from the snapshot are resolved against their configured source and checked for the same title before use. Concurrent visible requests for the same item share a task. No broad source search runs just to draw each card. Local-only previews do not initialize the reading plugin manager.

The context is discarded/cancelled on disappearance, backgrounding, profile activation or list changes. It never copies private Manga books or source passwords into shared custom-list records. Original poster style, dimensions, effects, focus and dock rendering remain in the shared poster component.

## Selective validation

The new `affected:home-lists` plan selects six new native cases (original selection/mutations, persistence/scope/malformed edits, raw-only Harbor sync, owned source selection and actual PDF image decoding), one affected existing wire-preservation case, two fresh guest preparations and two ordinary Home journeys, one per device family: **11 executions and 9 original images**. The journeys add/remove/re-add rows, rename/hide/show, enable numerals, move, relaunch and open an owned PDF through its Manga hero.

The local fixture server supplies owned film artwork; a newly generated two-page PDF supplies the actual imported Manga cover and reader. The image decode case requires a successful real image callback, not existence of a placeholder. Native/actual UI tests have not yet executed for this increment. Source comparison, selector preflight and formatting are separate from Apple runtime evidence. No personal accounts or provider credentials are part of the fixtures.

Preserve the accepted My lists contracts/interface actions from run `40691573028`. The new gate does not replay that journey or unrelated reader/player/tracker suites. Live configured Manga providers, full motion/keyboard coverage, physical iPhone/iPad performance and the remaining full-project parity requirements still require their own evidence. No IPA is produced by this gate.
