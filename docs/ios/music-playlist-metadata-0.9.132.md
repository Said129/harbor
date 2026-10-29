# Full recording metadata for native playlists

Desktop stores full recording metadata and playlist membership in a single
database transaction. The previous native playlist store kept only IDs, and
its interface resolved those IDs exclusively against imported audio files.
Catalog recordings therefore could not form usable saved playlist entries.

The native store now commits membership, collection-specific addition dates
and shared recording metadata in one owner-scoped document. Batch additions
keep first-insertion order, update shared metadata, preserve existing addition
dates and return the actual playlist identity for save-copy retries. A failed
write publishes neither partial membership nor partial metadata.

The v2 document reads existing local-only Keychain lists when no v2 document
exists. It writes the new format only after a successful mutation and leaves
the original document untouched. A failed read cannot overwrite unread data.
Existing callers adding an imported file use the same transaction. Local file
contents and the audio player are unchanged.

Recording persistence follows the pinned Desktop database defaults and merge
rules: missing connector/source identity, nullable explicit/version/media kind
updates, duration labels and private transient playback URLs. Remote stream
URLs must be resolved again for playback. Original source SQL is executed in
SQLite for eight ordered reference states, including blank and nullable values.
This executes the original SQL fragments, not the complete Rust function.

All four new native cases passed in Apple run 40860748738 at source
2122caa82d2a30fa72e4ad5081bce5038d7f9942, with zero new compiler warnings.
They cover mixed recordings and shared updates, batch write failure and retry,
real legacy Keychain migration, and the eight SQL reference states. Its
54,448-byte evidence archive matches GitHub's SHA-256 digest
8a24528f94372c0e5c0bfb0cfd0011cafaa4267e0ce7abf786dd7f0b2598ddbe.
No interface captures were required by this data-only scope. The already
approved local audio playback case is retained without replay.

The shared metadata is a foundation for the remaining source picker, remote
playback, mixed-track playlist interface and complete seasonal playlist view.
Those interfaces are not completed by this change. No IPA is produced here.
