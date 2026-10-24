# Remaining reader navigation checks

Run 40084158469 authenticated 12 executions: six fresh preparations and six
reader journeys. Nine passed. Preserve Metadata on iPhone, Focus on iPad and
Narration on iPad, together with the previously approved 51 native reader cases.

Only three failed journeys are selected by `ui-only:reading-visible`:

- Catalog on iPhone waits for the initial progressive provider responses before
  following a lazy card. The loading indicator has a stable accessibility ID.
  The journey still requires the two grouped sources, actual alternate reader,
  source/status filters and manga tag result.
- Metadata on iPad waits for the actual reader viewport to finish appearing
  before scrolling its paragraph. The original recording already shows that the
  owned book opens; this change does not claim a metadata cache repair.
- Focus on iPhone scrolls the native action list in landscape to reach Settings.
  The original accessibility hierarchy exposes the dialog and its action list;
  the Settings action is virtualized below the visible area.

The selection performs three fresh preparations and three UI journeys, requiring
17 original captures. It does not replay approved native suites or approved UI
journeys, and it does not build an IPA. Local selection and shell checks only
verify the dispatch plan. Apple execution and visual review remain required.
