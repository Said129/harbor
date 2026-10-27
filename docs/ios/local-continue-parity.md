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

Initial Apple validation executed 14 tests: 13 passed, with all six source-control
captures reviewed. The remaining exact-record test found Foundation truncating
integer milliseconds from `.123` to `.122`. The formatter now constructs the
fraction from the original integer; that failed comparison is selected again.

The private-mode increment selects personal records/resume only when another
profile shares the source. Actual playback and explicit Start Over mirror to the
canonical personal/shared resume actors; cloud imports stay shared. Weak actor
registration prevents a closing player and another profile from maintaining
competing cached copies of one file. Settings resolve the requested profile's
own document, including the shared fallback, before selecting a resume store.

Legacy hidden choices seed existing profiles once. Explicit private choices,
including an empty document, survive; profiles created later inherit nothing.
Failed private reads/migrations never fall back to shared cards. Library and
Simkl controls lock while privacy is requested; Downloads remains editable.

The private increment still requires Apple execution and visual review: 9 new
native methods, the failed date comparison, the affected production checkpoint
composition, 2 fresh guest preparations, and 2 actual privacy/source journeys
with 8 captures. Its executed Desktop oracle has 18 scope, 5 migration and 4
resume scenarios. Selection preflight does not prove native behavior.

Global dismissal cloud propagation and resume clearing still need their complete
Desktop behavior. Trakt progress remains a separate gap. Neither validation
selection produces an IPA or establishes complete Desktop parity.
