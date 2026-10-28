# Home labels and the seasonal entry

This increment addresses actual findings in the original images from run `40739389865`: the English hero still displayed Spanish information/bookmark actions and the seasonal invitation had a Spanish description. It also ports a functional difference discovered in the pinned source: dismissing Spooktober leaves an accessible chip in Desktop, while the native Home had removed the entry.

The reference remains Desktop 0.9.132, commit `0834340cec5531650bfe78cd628628702e636987`. Apple run `40776316479` compiled source `483cc25a38a9e7d3db1dfed3578971c79d412535` and passed all five selected executions without new warnings. All eight original captures have been individually inspected. This approves the selected hero labels and seasonal entry behavior; it does not certify full Home, the festival room, motion on physical devices or the complete port.

## Source and implementation

`src/components/cinema-hero.tsx` uses `Play` and `More info`; `src/components/hero.tsx` uses `In Watchlist`/`Add to Watchlist`; `src/views/movies.tsx` supplies `Featured tonight`. CinemaHero now resolves these actual canonical labels through the selected interface locale. Manga keeps its separate Read action and regular information route.

`src/views/spooktober/spooktober-entry.tsx` renders an expanded invitation or a small pumpkin/title chip, with the same opening action. Home now retains the invitation during the actual source season after dismissal. The existing owner-scoped dismissal record selects the chip; reopening the app preserves that selection. The chip retains a 44-point native touch target, keyboard focus and pointer styling. The expanded card uses the original description, entry and dismiss catalog keys in all sixteen supported languages.

The source CSS supplies a 760 ms pumpkin sway: angles 0, -7, 5, -2, 0 degrees and vertical offsets 0, -2, -1, 0, 0 pixels at 0%, 25%, 57%, 80%, 100%, with a bottom-biased anchor. Native keyframes follow those positions and timing on pointer entry/keyboard focus. Native interpolation uses SwiftUI cubic keyframes; it is not a claim that every intermediate frame equals browser CSS interpolation. Reduced Motion suppresses the sway and hover transitions. A regular-width invitation shows the entry caption; compact layout keeps its arrow. Focus outlines and the chip's 160 ms pointer transition follow the original behavior with native rendering.

The source's Halloween Nightmare font was inspected; its embedded license limits use. No new font was copied or represented as cleared for redistribution. The existing native OFL typography remains, so exact seasonal title typography is an explicit fidelity item still open. The full festival room, its sections, provider content and internal wording remain a separate reference review; repairing its entry does not close that room.

## Evidence and selective gate

The external `build_home_labels_reference.mjs` executes the original locale modules and actual original invitation TSX component with a small JSX descriptor runtime. The expanded and collapsed branches retain real callbacks and source labels; this is execution of the component, not a browser screenshot. The fixture records six original file hashes, two branches and 144 expected label resolutions (9 labels × 16 languages), with no provider network requests.

The new gate selects one native source-catalog comparison, two fresh owned preparations and two focused ordinary iPhone/iPad journeys: **5 executions / 8 original captures**. The journeys verify movie bookmark states, Manga information labels, the expanded invitation, dismissal, the persisted chip after relaunch and its actual reopening of the seasonal room. Owned local film artwork and an actual imported PDF supply the hero data. No personal accounts are used.

The earlier complete Home list/reader journeys, private-cover decode case and other approved behavior are retained. Screenshots of the reopened room will prove access, rather than complete internal festival-language or room parity. Only actual Apple results, original capture review and warning diagnostics can approve the newly selected behavior; local formatting and selector recording are preflight evidence.

The terminal archive contains 49,001,666 bytes with SHA-256 `244baade030d1aff3a6b7f45f8c4f31b25319b96af690bd93b6f9f5ce3df4288`, matching its GitHub digest. The native catalog comparison, both fresh preparations and both ordinary device journeys all passed. The film captures show the expanded English invitation; the captures named expanded show the Manga hero's Read and More info actions, with the invitation below the viewport. Both chip captures fit their viewports. Reopened-room captures confirm access and also show the remaining Spanish internal search, subtitle and headings with English selected. That existing room finding remains open. No unrelated tests were replayed and no IPA was created.
