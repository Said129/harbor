# Trakt personalized Home rows

Reference: Desktop 0.9.132, commit `0834340cec5531650bfe78cd628628702e636987`.

## Behavior

Home now includes Your Trakt Watchlist, Up Next on Trakt, Trakt Recommends:
Movies, and Trakt Recommends: Series when the active profile has connected
Trakt. These rows precede public discovery rows and remain independent of the
Stremio login.

The implementation retains Desktop's ordered raw items, first 24 item slices,
four illustrated items minimum, separate movie/show recommendations with
`limit=40&ignore_collected=true`, and the 14 day calendar based on the UTC date.
Upcoming shows are deduplicated by IMDb, then TMDB. A failure of one Trakt feed
does not suppress the others. No unavailable catalog warning is introduced.

TMDB hydration preserves the original Trakt identity/title and uses the original
w500 poster and w780 backdrop rungs. Missing posters or TMDB failures fall back
to the full Cinemeta record by IMDb, including its identity and title. Items
without an illustrated result are excluded. Mobile hydration is bounded to four
requests per row, with original ordering retained; pages already loaded by this
build are reused.

The ordinary Home row renderer supplies View all, normal title navigation,
renaming, hiding, reordering, numerals, and selection as the hero. The existing
layout projection carries the canonical Trakt row keys without account tokens
or configured URLs. The four row names use all 16 Desktop language catalogs.

Account lineage and active profile leases guard every response, row, and pager.
Disconnecting/replacing Trakt or leaving the profile prevents a late response
from publishing and invalidates a grid opened from the old profile. Private
feed items are retained in memory for the active build, not a new disk cache.

## Evidence

The external source runner executes the actual eight original modules:
home-rails, watchlist, recommendations, calendar, hydrate, to-meta, TMDB mappers,
and TMDB image rungs. It supplies owned transport replies without contacting
provider services, executes ten success/failure/artwork/page scenarios, and
records three pages for each emitted row. Catalog extraction supplies 64 label
comparisons. Original file hashes accompany the fixture.

Five new native cases are selected: comparison against those source executions,
late account/profile reply isolation, bounded out of order hydration, existing
Home layout integration, and production SwiftUI row/grid/customization mounting
with decoded owned covers in compact and regular sizes. Eight original images
are required. No approved Trakt library, OAuth, scrobble, or full Home journey
is selected again.

Apple compilation/execution and image inspection are pending for this source.
Rendering an injected owned Trakt feed is not evidence of live personal OAuth
or an end to end journey from ordinary app launch. The existing Trakt token
broker configuration still requires the separate independence audit. Public
Trakt lists, standalone calendar, comments, ratings, and full Desktop parity
are not completed by this change. No IPA is produced by its validation.
