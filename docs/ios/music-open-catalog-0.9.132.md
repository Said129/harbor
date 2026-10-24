# Original public Music catalog — native port in progress

Desktop 0.9.132's public catalog is separate from playback connectors. This
increment preserves its original Deezer, iTunes, ListenBrainz, MusicBrainz and
cover-art modules, data models and unit tests. It retains provider ordering,
partial-result behavior, rate limits, endpoint validation and artist cursors.
The source manifest records eleven inputs checked against the preserved Desktop
provenance and the generated native output hashes. The upstream MIT license is
included. Original unchanged modules keep their original line endings.

The Tauri connector trait becomes native inherent methods with an empty context;
the original atomic health cell and unsupported-operation messages remain. HTTP
identifies the pinned Desktop version and bounds metadata responses to eight MiB.
This budget applies to metadata, not audio files. Existing plugin HTTP behavior
and the network ABI version remain unchanged.

A new typed asynchronous catalog entry point shares the existing cancellation
and callback ownership contract. It accepts catalog operations rather than
arbitrary URLs, limits the request and response sizes, and has a thirty-second
overall deadline. Connection metadata remains anonymous with search and browse
capabilities. No playback capability is invented for the metadata catalog.

The separate Apple Rust validation compiles the bridge and runs only the newly
ported catalog contracts. Existing approved font and plugin network tests are
retained. Swift integration, actual public provider calls, native discovery/detail
interfaces and visual review are still required. Authenticated music connectors,
source selection, For you/Explore and full Music parity remain in scope and are
not established by these new unit tests. No IPA is produced by this workflow.
