# Reader position restoration and remaining interface checks

Run 39877611403 executed all 17 selected cases: three new functional native
tests, four necessary fresh preparations and two reader UI routes passed; eight
UI routes failed. The original 31 captures show readable native text, actual
book pages, turns, zoom and position restoration on iPhone, and complete book
detail/list navigation on iPad. Preserve those approved outcomes.

The remaining iPad Book route returned to paragraph zero after switching back
to continuous reading. The continuous scroll view now owns its position binding
and initializes it from the settled paragraph when mounted. It restores through
the real scroll proxy after mounting; explicit search jumps keep their separate
identity. The printed and continuous views publish settled paragraphs instead
of sharing a scroll binding across removal and insertion. Chapter changes
recreate the continuous view with the new chapter's position.

The new native contract mounts this actual SwiftUI component in a UIKit window.
It requires a nonzero real scroll offset at saved paragraph 14, a later offset
after jumping to 30, and publication of paragraph zero after scrolling back.
Source, font, paper, illustrations, margins, direction and search remain intact.

Three font interface routes stopped at an accessibility scroll action while
pressing a Back button. The tablet query selected the underlying book navigation
bar instead of the font sheet. Select the Custom font navigation bar explicitly
and tap its observed visible button. Realize the iPad form's brightness slider
before asserting its presence. Give each remaining UI route a fresh guest so a
previous Book preference cannot change a subsequent continuous-reader premise.

The phone search recording visibly reaches printed page 12 after the paragraph
30 jump, but its text/visibility query fails. Keep the assertion and preserve a
full hierarchy if it fails again, rather than claiming approval from the video.
The first phone catalog call also reports a real provider error; its cause is
not established. Do not turn that failure into a simulated success or broaden
network policy without evidence.

The new `reader-position` selection contains one mounted native contract, eight
fresh preparations and only the eight failed UI methods, with 47 required
original captures. It excludes the approved iPad detail and iPhone pagination
journeys and retains 27 recent functional native and five Rust font passes.
Local shell/selection checks are preflight only. Apple execution, complete
Desktop 0.9.132 parity and the final consolidated IPA remain pending.
