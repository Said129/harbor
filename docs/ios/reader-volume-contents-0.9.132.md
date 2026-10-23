# Reader volume contents and navigation

Desktop `harbor-reader.tsx` opens its contents at the current chapter's volume,
lists chapters with an active highlight and a counter within that volume, and
lets the reader choose another volume. It preserves the chosen sidebar volume
when closing the panel, follows the new owning volume after a chapter change,
and scrolls to the active chapter when the panel opens.

The iPhone/iPad reader now provides that panel instead of a flat chapter list.
It uses the already approved original grouping program and the loaded chapter
objects. Opening the panel performs no source/network request and no additional
grouping pass. Chapter buttons retain the provider's original identifiers. The
volume selection lives in the reader session; active-chapter selection is inert,
as in Desktop. Text and volume labels use the existing Desktop language catalog.

The same original flattened volume order now controls Previous/Next and the
overall chapter counter. The old native controls used the provider's raw array
order, which can differ from the displayed volume/chapter order. The stored
chapter index still refers to the canonical source array, so existing progress
and chapter requests do not change identity.
Within each volume, Desktop preserves the provider's order. The owned fixture
therefore navigates 1, 3, 2, rather than numerically sorting the entire reader.

Two new UI methods exercise the ordinary saved-book route on fresh iPhone and
iPad guests. They require the current chapter/volume, a different volume without
the old chapter, retained sidebar choice after closing, an actual new chapter's
paragraph, and Next moving to the next chapter in volume order. Eight original
captures are required. Existing native grouping tests are retained unchanged.

The validation pipeline now supports an explicit UI-only selection: build the
native targets without running native model tests, then execute only two fresh
preparations and those two new UI methods. The selection and collector reject an
unexpected empty model plan. A build result is not counted as an executed test.
This avoids rerunning approved native contracts solely to start interface checks.
The separate actual public metadata search also passed in run 39881961134; its
original tree/log are retained and it is not selected again here.

Local checks validate the actual workflow shell's empty test selection and
`build-for-testing` action; Apple compilation, UI execution and visual review
remain separate. This increment does not complete the full Desktop port or
generate an IPA.
