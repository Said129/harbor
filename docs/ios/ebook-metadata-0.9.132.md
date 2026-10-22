# Books metadata and discovery — Desktop 0.9.132

This increment uses reference commit `0834340cec5531650bfe78cd628628702e636987`.
It does not complete the whole port and does not generate an IPA.

## Implementation

- The original ebook API, anonymous AniList client, relation helpers, and detail
  source-matching functions are extracted from six hash-pinned reference files.
  The corrected generated program is 105,472 UTF-8 bytes with SHA-256
  `ca03f3b2e7284dd8662af748694685cc33300c2327308adf06eda3430d8b2829`.
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

Validation of internal navigation from adaptations to the other media rooms, complete
Desktop composition/motion comparison, physical-device performance, the other
remaining compatible sections, and the consolidated final IPA remain part of
the full objective.

## Native initialization correction and adaptation follow-up

Run `39757601970` compiled the simulator and passed the new native local HTTP
contract, the new permission-precedence contract, and the affected public-host
guard. Its seven model cases produced two passes and five failures. The title
tag/coalescing case and owner-isolated cache case are retained. The five
metadata worker cases exposed an invalid assumption that raw source evaluation
provides a `config` global. The original factory only passes `harbor`.

The first-party engine now initializes through an explicit `configure` content
call after worker readiness, before publishing the client. The fourteen
affected local checks passed again without providing a synthetic global
configuration. Original worker/host execution code is unchanged. The early
archive preserves the actual seven native outcomes and three Rust passes,
including their original structured tree and logs. Its SHA-256 is
`5c49717eb5da48e4ee3e1a162393d8c9ba0cc441cbf18db42a0fc8fadb76dc19`.

Local and legacy EPUBs now retain a readable route even though imported files
have no remote EPUB URL. A new integration case imports the owned EPUB,
applies public metadata, restores the shelf and opens the original chapters.

Adaptation navigation is implemented with a separate original-source program
(`EBookAdaptationAssets.json`, 16,114 bytes, SHA-256
`cef50f38205ab590978a854ebf5f1d6bb7315ea2302b26ffda26be2e9bc1f75c`).
It pins seven reference inputs and preserves Desktop's exact AniList identity,
anonymous three-provider anime search, normalized title selection, eight manga
aliases and three real manga choices. Manga lookup includes installed reading
plugins and configured Suwayomi sources, with bounded concurrency and stable
request order. Known anime identifiers open the native detail immediately;
other anime titles resolve through the original search. Live-action public
links retain their Desktop behavior. Ten new local checks passed; three new
native adaptation cases and actual new-interface review are still required.

The follow-up selects five failed metadata cases and four new adaptation/local
EPUB cases, plus the pending fresh preparations and ten independent UI routes:
twenty-one planned XCTest executions and fifty-eight expected captures. The
two approved native and three approved Rust cases are not repeated. This
supersedes the earlier nineteen-execution plan for remaining work; that run's
actual partial results remain independent evidence.
