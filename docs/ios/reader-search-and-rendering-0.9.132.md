# Chapter search and native reader rendering

The preserved 0.9.132 reader searches the current chapter without Latin/Arabic
diacritics or case sensitivity. Matches ahead of the current paragraph stay
sealed until explicitly revealed. Changing the query seals them again; closing
the panel retains that reader session's query and reveal choice.

Extract the exact original `marks`, `stripMarks`, search and future-result
expressions into a pinned pure JavaScriptCore program with no native/network
bridge. Ten original oracle cases include Arabic marks, decomposed Latin text,
literal punctuation, astral characters, future sealing/reveal and 240 matches.
Native results retain original block routes and the original 220 UTF-16-unit
preview. A selected result jumps locally in continuous or Book mode without
downloading the chapter again. Existing chapter, shelf and account data remain
unchanged. The ordinary reading menu opens the new search panel on phone/tablet.

## Actual rendering failure and repair

Runs 39856231737 and 39857311929 approved two actual CoreText web-font contracts
and three Book contracts respectively. Both ran all their selected interfaces:
six font/detail/display and two Book interfaces failed at a zero reader scroll
frame. Their original final recording frames show the native loading indicator
replaced by the unsupported-rendering marker, followed by an empty reader.
The entire native reader was wrapped in a Metal color effect, including
UIKit-backed selectable text, scroll content and the page-curl controller.
[Apple documents this restriction](<https://developer.apple.com/documentation/swiftui/view/coloreffect(_:isenabled:)>).

Remove that container filter. Scale native text/paper colors directly, adjust
the Book renderer's own RGBA canvas before PNG creation, and retain the original
shader only on actual SwiftUI illustration images. Keep the brightness control,
its bounds, profile persistence and selection/zoom. Include brightness in the
Book cache identity so a changed value cannot display stale pixels. A new
Native contract checks premultiplied alpha, bounded values and actual rendered
PNG background pixels at 55, 100 and 120 percent without changing page layout.
The reader's real scroll view has its own identifier; interface checks wait for
visible layout, retain the geometry assertions and record the actual failure
frame/hierarchy if it does not lay out.

This repair and search still require new Apple execution and screenshot/video
inspection. Prior Native results do not certify these new interfaces. Record
only three NEW models, four necessary fresh phone/tablet preparations, two NEW
search interfaces and eight FAILED reader-interface retries: 17 XCTest methods
and 61 original captures. Font and Book groups use separate fresh guests; a
Book-mode preference cannot alter the independent continuous-reader cases.
Retain the 24 approved Native models and five Rust font contracts. No IPA, global
completion percentage, stable release or full Desktop equivalence is claimed.
