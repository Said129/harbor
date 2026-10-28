# Home lists from Desktop 0.9.132

Reference: `0834340cec5531650bfe78cd628628702e636987`, the owner's preserved Desktop 0.9.132 tree. This increment implements Home rows made from My lists. The actual partial Apple results and remaining findings below are authoritative; they are not an approval of full parity or a stable IPA.

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

The local fixture server supplies owned film artwork; a newly generated two-page PDF supplies the actual imported Manga cover and reader. The image decode case requires a successful real image callback, not existence of a placeholder. Source comparison, selector preflight and formatting are separate from Apple runtime evidence. No personal accounts or provider credentials are part of the fixtures.

Preserve the accepted My lists contracts/interface actions from run `40691573028`. The new gate does not replay that journey or unrelated reader/player/tracker suites. Live configured Manga providers, full motion/keyboard coverage, physical iPhone/iPad performance and the remaining full-project parity requirements still require their own evidence. No IPA is produced by this gate.

## Actual results and selected repair, 28 October 2026

Run `40739389865`, exact source `28386ee04c67a435b627e28bae1a6ea6899d341c`, compiled and executed eleven cases: ten passed, one failed. Both complete ordinary Home journeys passed, including add/remove/re-add, name/visibility/numerals/order, relaunch, Manga hero and actual PDF reading. Six of the seven native cases passed; both preparations also passed. There were no new compiler warnings.

The single failure is the final reset assertion in the original mutation comparison: the removed list's hidden flag survived because reset only rewrote mapped rows. The repair explicitly empties all supported Home row-option fields, including references removed earlier, while retaining unrelated future document fields. Keep the other passing cases. Retry this failure and only the affected raw-reference reset/future-field case.

The authenticated archive is 78,086,105 bytes, SHA-256 `a854bb0f76034392848b02db22d0ce4f0b830f6f586c58f3cfe28d4cf326dbb1`, equal to GitHub's digest. All nine original images were individually inspected. Actual private PDF cover, poster, hero and reader rendering fit both device families. The external visual review retains additional existing English-UI findings: Spanish seasonal invitation, hero information action, and automatic movie-hero bookmark action. These language findings remain open; successful navigation does not close them.

The follow-up `list-parity-repair` plan combines the failed reset and failed origin comparison with their two affected native paths, one necessary fresh iPad preparation and only the failed iPad localization journey: six executions/two originals. It retains both approved Home journeys and the approved iPhone localization journey. No new IPA.

Run `40773669603`, exact source `415ed880ca6228d0ad5c8588936088471f50dce3`, passed all six selected executions with zero skips/failures and no new compiler warnings. The complete original mutation comparison and affected reset/future-field/owner case now pass. The archive is 18,056,913 bytes, SHA-256 `ada0ae82e3421308673761d5f189006a3d390bff08fa35eb5c83cd176d0a65a8`, equal to GitHub's digest. Both new original iPad images were individually inspected and their scoped layouts/English labels pass. The prior approved Home/reader journeys remain retained. The separate Home label and seasonal-entry findings are addressed by the next increment, documented in `home-entry-language-0.9.132.md`; its Apple results remain pending.
