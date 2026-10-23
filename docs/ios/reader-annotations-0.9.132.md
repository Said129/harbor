# Notes, highlights and references

Reference: `0834340cec5531650bfe78cd628628702e636987`, the original
`harbor-reader.tsx` selection, reference matching, mark precedence, editor and
notes panel, plus `reader-state.ts` annotation persistence rules.

The iPhone/iPad reader now exposes the complete text-note fields: selected
passage, the eight original inks, 58% initial density and 20–90% adjustment,
optional title, body, UTF-16 character count, comma-separated tags and references.
Saving/editing moves the same ID first, preserves its creation time and caps the
list at the original 1000 entries. Individual deletion and passage navigation
use the original chapter source ID, not its display position.

Selection is adapted to touch through a native scrollable, read-only text sheet
with normal iOS selection handles and copy actions. It can select across multiple
paragraphs. The native edit menu and footer offer highlight, note and reference.
The reader footer starts at the current paragraph. The default continuous reader
and its existing native copy behavior remain unchanged for unmarked paragraphs.
Highlighted text uses native attributed labels with the same Core Text font,
spacing, direction and brightness. Tapping a painted range opens its note, and
VoiceOver receives the corresponding note title/type. The list opens all notes.
References paint matching whole phrases across chapters as Desktop does.

The pinned original Unicode/diacritic reference matcher and direct/reference
range ordering execute without network/script bridges. Whole-chapter preparation
uses a single bounded background call with compact annotation data; note bodies
and tags are not repeatedly serialized while drawing. The native document maps
paragraph UTF-16 offsets separately from noncontiguous source block IDs. Images
are excluded from text selection and retained in the normal reader.

Each profile/book has an atomic, file-protected annotation document. Failed writes
keep the old list and editing draft. A changed profile/book retires the previous
presentation generation, clears visible note state and rejects late paint updates.
No text or notes are sent to a provider. The richer text-identity migration between
changed editions/languages still belongs to the full reader audit; no remote sync
or PDF annotation parity is claimed by this increment.

Local generation covers eleven original reference, Unicode, overlap, clipping
and batch cases. Five new native contracts cover the actual JavaScriptCore,
cross-paragraph UTF-16 selection, protected profile/book storage/order/cap,
failed-write retry and actual mounted highlight pixels/imported font attributes.
Two new ordinary phone/tablet UI cases cover native selection, note editing,
ink/density/tags, painted text, a cross-chapter reference, relaunch, passage jump
and individual deletion. Twelve original captures are required.

The same affected selection includes only the two actual failed search UI methods
from run 39933605950. Original images showed that iOS hides navigation-bar items
while the search field is active. The close-panel control now stays in a safe-area
footer above the keyboard. The earlier corrected expected edited query remains.
This preserves the requirement to close the actual search panel; no assertion is
removed to accept an inaccessible button. The two failed translation UI methods
are also selected. Their original choices images showed the switch still off
before saving, while all five native translation/storage contracts passed. The
interaction now targets the observed switch thumb and requires its value to turn
on before saving; persistence is not changed to force on an unselected option.

Run 39945488394 stopped during Apple compilation before any test executed. Its
preserved compiler archive reports a shadowed `error` property in the annotation
store's load failure handler. The handler now explicitly assigns `self.error`;
the retry and previous-value behavior are unchanged. No native/UI passes are
claimed from this run. Apple execution and new note/search interface results
remain pending. The affected selection is five new native cases,
six necessary fresh preparations and six UI methods: seventeen actual cases,
thirty-eight captures, no IPA. Thirty-five recent native contracts, one public
metadata integration, five Rust font tests and twelve reader UI methods stay
retained. Only four failed methods are retried; no passed predecessor is replayed.

The broader reader chrome, animations, narration and full Desktop parity audit
remain open. This increment is not a declaration that the port is complete.
