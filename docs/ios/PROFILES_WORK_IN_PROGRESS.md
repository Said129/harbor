# Desktop household profiles: work in progress

Reference: Desktop 0.9.132, source `0834340cec5531650bfe78cd628628702e636987`.
This belongs to the existing full iPhone/iPad port. It does not reserve or create another IPA.

The local foundation has been written, with 22 affected native tests prepared: 15 roster/lock/routing cases and seven session migration/isolation cases. **Apple compilation and execution are still pending. The application does not yet activate this roster or expose a profile selector.**

`NativeProfileRoster.swift` separates the portable Desktop roster from device identity, Stremio sharing, migration ownership and credentials. Unknown Desktop fields survive adoption and editing. Portable output omits device IDs, passwords, parent PINs and Stremio sharing IDs. Profile names alone never establish that existing user data is disposable.

`HouseholdProfileStore.swift` commits the roster, selection, routing and device locks together in Keychain. Missing remote rows are retained; explicit deletion creates tombstones. Incoming account revisions cannot move backwards. Linked settings share one scope; independent settings use the personal scope. Continue Watching remains shared unless the private option is enabled and two profiles actually share the same Stremio source, matching `cw-profile.ts`.

Selection checks credentials centrally. Reloading or locking the session invalidates prior unlocks. A failed persistence write cannot publish an unlocked selection. Child profiles preserve local parent credentials when the Desktop roster changes. These checks are model work; the child content and playback restrictions still need application integration.

`DeviceProfileCredential.swift` uses device-specific random salt and PBKDF2-HMAC-SHA256 through Apple's [CommonCrypto API](https://github.com/apple-oss-distributions/CommonCrypto/blob/main/include/CommonKeyDerivation.h). Derivation runs away from the main actor. The prepared test vector was calculated independently with Python; its native verification is pending. Credentials remain device-local, as required by Desktop's `WireProfile` contract.

`HouseholdSessionVault.swift` prepares actual Stremio session isolation. A shared Stremio source reads the same account; an independent source starts with its own account configuration. The old iOS session and its migration claim are committed together, preserving the complete saved addon payload. Legacy keys are retained for rollback but cannot silently sign a profile back in or migrate into a different household. A generation and per-source version reject late login/refresh writes after source changes. The vault is not yet bound to `AppModel`; this is not a claim that live account switching has been verified.

Signing in or out of a shared profile follows Desktop's `auth.tsx`: detach that profile from its shared source. `prepareOwnAccount` durably stages its own account before the caller changes `shareStremioWith` and binds the new source. Refreshing the deliberately shared addon/source configuration remains a shared update. The primary source is never replaced or signed out by a secondary profile's explicit sign-in/sign-out.

Before claiming profile parity, complete and verify:

- Transactional migration of existing iOS sessions and data, with Stremio sharing or separate accounts following the selected profile.
- Actual routing of reading, favorites, trackers, discovery, settings, library and optional private playback progress; changing a profile must change the data being used.
- Full roster synchronization and durable queued changes through the existing authenticated Harbor transport.
- The selector, profile editor, PIN entry, parental exit, linked settings, tab/content controls and daily playback limits on iPhone and iPad.
- Original picker and child artwork, configurable backgrounds, Desktop transitions and Reduce Motion behavior.
- Focused Apple tests and manual inspection of actual phone/tablet screenshots. Previously approved unrelated checks remain reusable only when their producers are unchanged.

The remaining routing inventory and exact source hashes are saved outside the app in `work/harbor-revision/parity132/profiles/foundation-and-routing-review.json`. This is an implementation inventory, not a completion percentage or runtime proof.
