# Desktop household profiles: work in progress

Reference: Desktop 0.9.132, source `0834340cec5531650bfe78cd628628702e636987`.
This belongs to the existing full iPhone/iPad port. It does not reserve or create another IPA.

The local foundation and initial application routing have been written, with 35 affected native tests prepared: 15 roster/lock/routing cases, seven session migration cases, seven context cases, three library binding cases and three playback ownership cases. **Apple compilation and execution of this profile block are still pending. Startup now binds the migrated primary profile, but the multi-profile selector is not yet exposed.**

`NativeProfileRoster.swift` separates the portable Desktop roster from device identity, Stremio sharing, migration ownership and credentials. Unknown Desktop fields survive adoption and editing. Portable output omits device IDs, passwords, parent PINs and Stremio sharing IDs. Profile names alone never establish that existing user data is disposable.

`HouseholdProfileStore.swift` commits the roster, selection, routing and device locks together in Keychain. Missing remote rows are retained; explicit deletion creates tombstones. Incoming account revisions cannot move backwards. Linked settings share one scope; independent settings use the personal scope. Continue Watching remains shared unless the private option is enabled and two profiles actually share the same Stremio source, matching `cw-profile.ts`.

Selection checks credentials centrally. Reloading or locking the session invalidates prior unlocks. A failed persistence write cannot publish an unlocked selection. Child profiles preserve local parent credentials when the Desktop roster changes. These checks are model work; the child content and playback restrictions still need application integration.

`DeviceProfileCredential.swift` uses device-specific random salt and PBKDF2-HMAC-SHA256 through Apple's [CommonCrypto API](https://github.com/apple-oss-distributions/CommonCrypto/blob/main/include/CommonKeyDerivation.h). Derivation runs away from the main actor. The prepared test vector was calculated independently with Python; its native verification is pending. Credentials remain device-local, as required by Desktop's `WireProfile` contract.

`HouseholdSessionVault.swift` prepares actual Stremio session isolation. A shared Stremio source reads the same account; an independent source starts with its own account configuration. The old iOS session and its migration claim are committed together, preserving the complete saved addon payload. Legacy keys are retained for rollback but cannot silently sign a profile back in or migrate into a different household. A generation and per-source version reject late login/refresh writes after source changes. `AppProfileContext` now connects the vault to `AppModel`; this is source integration, not a claim that live account switching has been verified.

The root keeps content hidden until account, library and resume storage are bound. The migrated profile retains the previous reading, favourites and tracker namespace; new profiles receive independent personal scopes. Reading shelves, music, downloads, discovery and seasonal preferences now use that scope. Shared Stremio library records keep their source account. Linked navigation, streaming services and TV settings use the household settings owner. The remaining settings singletons, private Continue Watching and full Harbor identity/roster transport still require integration before exposing the selector.

Open EPUB/PDF requests are queued at the stable application root, including cold starts. A request opened for a specific profile waits for that profile rather than being imported into whichever person is selected later. The actual UI flow remains to be verified.

`ProfilePlaybackRegistry` closes registered video/PiP controllers during a context change and rejects late surface creation. A rejected controller cannot initialize its renderer or audio session later. The context changes its operation token even when two people share Stremio; addon refresh completions cannot clear a newer task or publish an old error. These paths have prepared focused cases but have not run on Apple yet.

Signing in or out of a shared profile follows Desktop's `auth.tsx`: detach that profile from its shared source. `prepareOwnAccount` durably stages its own account before the caller changes `shareStremioWith` and binds the new source. Refreshing the deliberately shared addon/source configuration remains a shared update. The primary source is never replaced or signed out by a secondary profile's explicit sign-in/sign-out.

Before claiming profile parity, complete and verify:

- Transactional migration of existing iOS sessions and data, with Stremio sharing or separate accounts following the selected profile.
- Actual routing of reading, favorites, trackers, discovery, settings, library and optional private playback progress; changing a profile must change the data being used.
- Full roster synchronization and durable queued changes through the existing authenticated Harbor transport.
- The selector, profile editor, PIN entry, parental exit, linked settings, tab/content controls and daily playback limits on iPhone and iPad.
- Original picker and child artwork, configurable backgrounds, Desktop transitions and Reduce Motion behavior.
- Focused Apple tests and manual inspection of actual phone/tablet screenshots. Previously approved unrelated checks remain reusable only when their producers are unchanged.

The original foundation-only review is historical. The updated context routing inventory and exact source hashes are saved outside the app in `work/harbor-revision/parity132/profiles/context-routing-review.json`. These are implementation inventories, not a completion percentage or runtime proof.
