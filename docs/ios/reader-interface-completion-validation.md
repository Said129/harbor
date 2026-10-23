# Remaining reader interfaces and the UI-only build repair

Original run 39883561558 approved five more reader UI methods: phone detail and
lists, phone display/font restoration, both web-font interfaces, and tablet Book
pages/rotation/zoom/restoration. Preserve those five and the two earlier reader
UI passes. The mounted native contract also passed in run 39889589952 after its
backward movement used the actual app jump interface. Preserve that method too.
The three remaining failed reader methods are phone/tablet search and the tablet
display-restoration route.

Tablet display stopped waiting for a lazy brightness slider before scrolling
its form after relaunch. Realize the control first, keeping the saved 55-percent
and selected-font assertions. Chapter search explicitly keeps its search field
visible in the navigation drawer on tablet. Its UI action is tapped at its
observed frame and records the full hierarchy if the field fails to appear.
The printed-passage assertion and actual backward swipe remain mandatory.

Reader contents run 39886268564 executed zero tests. The original shell log
reports `selection[@]: unbound variable` at the final command expansion when
the selected native array is empty under `nounset`. Consequently its preparation
test bundle was never built; subsequent launches reported a missing
`Harbor.app/PlugIns/HarborTests.xctest`. These are setup failures, not UI passes.

The actual workflow now expands an empty selection to zero arguments safely.
UI-only validation builds both preparation and interface schemes without running
native model tests, and checks the native test bundle's Info.plist and executable
before starting fresh devices. The original successful public-metadata run's
build log confirms that bundle path.

The new selection has zero native models, five fresh preparations, and five UI
methods: two previously unexecuted contents routes and the three failed reader
routes. It requires 28 original captures. It explicitly excludes the seven
approved reader UI methods and retains 28 native contracts, one public metadata
integration and five Rust font contracts. Windows shell argument recording is
preflight only; Apple execution and visual inspection remain separate. No IPA
is created and full Desktop 0.9.132 parity remains incomplete.
