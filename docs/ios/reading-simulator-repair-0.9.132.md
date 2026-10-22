# Reading validation startup repair

Run39852325983 approved all five new Rust font contracts and clean clippy with
all targets. Preserve those original results while the 23 compiled Rust and font
fixture inputs retain their hashes. The production cargo check from39850934986
is also retained. Neither suite is replayed to retry an unrelated interface.

The same run executed zero XCTest methods. Its original result tree contains a
system startup failure: Xcode16.4 / iOS18.5 simulator could not load its own
Swift WebKit overlay. Apple's Frameworks Engineer documents the simulator-only
runtime path repair in [the accepted answer](https://developer.apple.com/forums/thread/785964).
Expose that selected runtime's existing library in the simulator build product
search path only when the ordinary runtime library is absent. Nothing is copied
into the app and the minimum deployment remains iOS17.

The independent UI target also failed to typecheck one pixel assertion. Replace
the long inferred filter with an explicit loop and identical RGB comparison.
The failure occurred at compile time; it is not an executed UI case outcome.

Retry only the two unexecuted CoreText font contracts, two necessary fresh guest
preparations and six unexecuted phone/tablet interface routes (36 captures).
The previously approved17 Native models remain retained. All UI behavior still
requires execution and inspection. No IPA is produced by this validation.
