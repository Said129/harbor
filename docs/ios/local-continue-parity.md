# Local Continue Watching

Reference: Desktop 0.9.132, commit `0834340cec5531650bfe78cd628628702e636987`.

The actual player checkpoint commits its existing resume entry before recording
local viewing history. Streaming uses `library`; downloads use `local`. The
personal owner is captured when playback starts, separately from the Stremio
account and shared progress source. Changing profiles invalidates publication
and any remaining store writes through the active binding lease.

Each source has separate personal and shared files. Actual playback writes both;
cloud anime absorption writes only the shared file. The store retains 60 titles,
removes movies at 92%, keeps series, and preserves Desktop's equal-time object
enumeration. Disk writes are serialized across asynchronous lease checks and
commit cached state only after the protected atomic write. Corrupt files remain
unavailable and are preserved.

Immutable prepared records avoid reconstructing dates and sorting all histories
on each view read. Source selection and invalid profile leases also participate
in the merged projection's cache identity. Library and download switches persist
in the existing profile settings document and do not change Simkl selection.

`local-continue-reference.json` contains results from executing the pinned
original `local-cw.ts`, `cw-profile.ts`, `continue-watching.ts` conversion, and
`anime-cw-absorb.ts` with the original Stremio coordinate parser. It covers 13
history cases and 15 cloud absorption cases with no provider requests. Input
hashes are included in the fixture.

Validation selection: 8 new native methods, 2 actually affected existing methods,
2 fresh guest preparations, and 2 actual iPhone/iPad settings journeys with 6
required original captures. Selection preflight is not native execution. Apple
results and visual review remain required before approving this change.

This does not complete private Continue Watching: profile-specific read routing,
the privacy setting, legacy dismissal migration, and dual resume ownership still
require their complete Desktop behavior. Trakt progress remains a separate gap.
No IPA is produced by this validation selection.
