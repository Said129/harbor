# Books metadata and discovery — Desktop 0.9.132

This increment uses reference commit `0834340cec5531650bfe78cd628628702e636987`.
It does not complete the whole port and does not generate an IPA.

## Implementation

- The original ebook API, anonymous AniList client, relation helpers, and detail
  source-matching functions are extracted from six hash-pinned reference files.
  The generated program is 105,162 UTF-8 bytes with SHA-256
  `6084b096042afdcf493c309b77b5885f25481478861c6981baa5afd23615f531`.
- The first-party program runs in its own isolated worker. Installed sources
  receive neither its Google Books key nor its metadata cache. Public metadata
  requests retain HTTPS host checks and public-network-only native policy.
- Books source catalogs appear before optional metadata completes. Cached and
  subsequent verified results enrich titles, authors, covers, identifiers,
  editions and other facts while preserving native EPUB/PDF and plugin routes.
- Discover offers original popular books, novel ratings/trending, new releases,
  categories, search and supported pagination. Known readable sources attach to
  matching metadata entries. Metadata-only entries cannot open the reader until
  a real source has been resolved.
- Details show public and source descriptions, alternate readable sources,
  metadata facts, collections, recommendations and adaptation information with
  available public links. Source resolution uses Desktop's six distinct title
  aliases, original matching rules and at most 32 detail candidates; mobile
  concurrency is bounded. Gutenberg aliases run serially alongside providers.
- Optional Google Books credentials live in the profile's Keychain. Public
  metadata cache files are owner-scoped and bounded. The original cache keys,
  budgets, freshness, stale fallback and negative caching are retained; API key
  query values are excluded from stored metadata. Users can clear metadata
  without deleting books or progress.

## Reading corrections

Owned native UI evidence exposed an unconditional private-host rejection in
the Rust HTTP transport. An explicit native reading policy now permits local
sources, including manually configured local HTML catalogs. Public metadata and
stream policies keep their original restrictions; blocked hosts, URL schemes
and public-only checks take precedence. Installed JavaScript cannot choose the
native permission flag.

Cover placeholders no longer contain a retry button inside a navigation link.
Readers retain explicit image retries. Search fields and the manual source
editor have full touch targets and focus handling. The catalog tag test now
expects Desktop's actual title cleanup rather than colon-containing fixture
text.

## Evidence and pending validation

Fourteen local generator checks passed: five exact mapping/merge fixtures plus
nine request, language, enrichment, partial-result, cache-privacy, freshness,
alias and readable-route checks. They are not Apple SDK execution.

Run `39672288309` retained twelve actual native passes out of thirteen model
cases. The remaining tag expectation and both unsuccessful UI routes are
addressed here. Its original archive is retained, including seven captures.

Run `39676396973` passed all four new manual HTML native cases and its iPhone
preparation. The iPhone UI failed on text-field focus; iPad did not complete
before the runner timeout. The final attachment export also failed on a partial
bundle. Original GitHub logs and their four native outcomes are retained; the
missing original structured tree is not presented as a saved artifact. These
four passed native cases are not selected again.

The new selection contains six metadata cases, the one failed catalog case,
two fresh guest preparations, and ten independent affected/new UI cases across
iPhone and iPad: nineteen planned XCTest executions and fifty-eight expected
captures. Two new Rust local-access contracts and one affected public guard
also run. Selected tests and captures are plans until their actual results are
collected.

Local preflight checked the real workflow selection shell, asset integrity and
the runner's independent-failure path using recording command stubs. It proved
one UI build and four subsequent commands without rebuilding, including the
second device after an injected first-device failure. It did not run Swift,
WebKit, Rust tests or a simulator. The Windows host lacks Cargo and Apple SDKs;
those compiler and runtime checks remain required on the Apple build host.

CI now saves model results before UI starts and preserves available logs and
canonical trees when a partial attachment bundle cannot be exported.

Internal navigation from adaptations to the other media rooms, complete
Desktop composition/motion comparison, physical-device performance, the other
remaining compatible sections, and the consolidated final IPA remain part of
the full objective.
