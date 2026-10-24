# Remaining reader interface failures

Run 40051396481, source 7587f5ba84992033e12dc7cc586f168e7defdbdc,
completed twenty actual executions: fourteen passed and six failed. The original
logs, result trees, screenshots and recordings are preserved. Four UI journeys
passed: the manual HTML source and readers on iPad, embedded cover/chapter heading
on iPhone, actual landscape voice selection on iPhone, and sealed search in both
reading modes on iPad. These routes and the fifty-one prior native reader cases
remain retained.

The focus journeys reached restoration in landscape, then lost the menu while
opening settings. Reader actions now use a native confirmation dialog with explicit
presentation state. That state suspends the existing 2.2-second focus timer until
the dialog closes, as the other reader panels already do. All ten prior actions
remain available, including the focus choice and reading settings.

The iPad voice journey restored its selection, then kept the keyboard open after
rotation. Both iPad orientations retain the regular size class, so a size-class
change alone did not dismiss it. The panel also observes device orientation changes.
The failed phone catalog journey now reveals its moving lazy-grid result again
after its original capture before activating it.

The two discovery journeys showed public search results rather than the prepared
owned catalog. Their cause remains under investigation. Fresh preparation now
requires the persisted public cache to reopen in a separate worker without an
outbound request. Its original diagnostic records the owned cache digest, public
keys and prepared request URLs. The fresh-simulator runner also records cache-key
snapshots before and after those routes; it does not export account credentials.

Only the six failed UI journeys and six fresh preparations are selected: twelve
executions with thirty-four required original captures, zero native model replay.
Apple outcomes and the complete motion/interface review remain pending. This
increment produces no IPA and does not complete the full Desktop port.
