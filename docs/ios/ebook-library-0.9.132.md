# Independent book lists — Desktop 0.9.132

Desktop's `src/lib/ebook/library.ts` stores bookmarks, favorites and read-later
independently. iOS now exposes all three on book details and card context menus,
with shelf filters for those lists, continuing reading and completed books.
Existing shelf search and sorting remain available.

Removing list membership leaves the imported file, reading position, completion
state and reading bookmarks intact. Explicit deletion of a saved book remains
a separate action. A book saved for later does not claim that reading has
already begun. Imported files also join the bookmarked list.

The bounded list document belongs to the normal profile's personal owner and
is protected by Keychain. Initial migration copies the existing shelf once;
removing membership cannot be undone by a second migration. A failed read,
owner mismatch or failed write preserves the prior document and blocks an
unsafe overwrite. An unreadable legacy shelf cannot initialize an empty
migration. The chapter list/grid preference joins the existing profile settings
document. These local list changes do not claim cloud/Desktop synchronization.

Three new native cases check independent memberships and migration, failed
storage and profile isolation, and actual imported EPUB/progress preservation.
Apple execution and the new list/volume UI routes are pending. No previous
approved suite is selected again, and no IPA is generated for this increment.
