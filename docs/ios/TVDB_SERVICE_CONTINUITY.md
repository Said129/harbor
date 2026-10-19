# TVDB service continuity, 19 October 2026

The functional and visual reference remains Desktop 0.9.132 Beta. This repair preserves its public TVDB proxy protocol; it does not adopt another fork's entire application, require a new account or API key, or change episode ordering.

## Verified upstream information

- [The original Harbor notice](https://harbor.elfhosted.com/) cites legal and personal reasons for ending support. It does not explain those reasons further. The old `harbor.site` TVDB route redirects to this HTML notice. TheTVDB itself has not closed.
- [The community continuation](https://github.com/Harborofficial/Harbor), examined at commit `cd2a0aff335fb9936146b6434098a7e10b14a421`, changes `HARBOR_TVDB_BASE` to `https://harborcommunity.site` and retains `/api/tvdb/v4`, `/api/tvdb/images` and `/api/tvdb/artwork`. Public series and images routes returned JSON during this investigation.
- [Another independently maintained fork](https://github.com/crazyrabbit0/harbor/blob/8293d680e054361ae6bae4f3a8098d52eac956c4/docs/SUNSET.md) instead uses the official TVDB API with a user-supplied key. This is an alternative implementation, not evidence that TVDB was replaced by another database.
- [TheTVDB's own API information](https://thetvdb.com/api-information) and [official v4 API](https://thetvdb.github.io/v4-api/) confirm that series, seasons, episodes and artwork remain available.

The owner explicitly prefers keeping Harbor's existing system and repairing the connection. The iOS implementation therefore uses the compatible public community proxy. It sends no account password, token, API key or cookie. Existing Harbor account credentials are not redirected to another service by this change. Account/realm synchronization is a separate unfinished dependency; public metadata success does not certify it.

## Native implementation

`TVDBService` retains the v4 response envelope and default episode route, coalesces requests and caches successful responses for ten minutes with a 200-entry bound. It rejects malformed or wrong-series responses, repeated pagination and unapproved paths. The HTTP session rejects redirects, has no cookies or cache, requires JSON and retains the existing eight-megabyte response bound. Transient failures have one bounded retry.

The provider episode list is published before the optional supplement. A proxy failure retains that list. Valid TVDB stills replace missing or generated Metahub images; existing other images are kept. Raw video IDs, canonical season/episode, watched keys and selected display coordinates stay intact. Ambiguous matches are left alone. A cour's local episode number is not assumed to be the franchise's absolute number; a complete unique mapping or explicit canonical coordinates are required. The detail page links to TheTVDB for attribution.

This supplements the native metadata route that was still missing from the larger port. It does not complete the full Desktop TVDB order/provider panel (DVD, alternate, regional and other controls), or the overall port.

## Validation boundary

Six new native contract/identity/failure tests and one new live proxy/image test are selected by `tvdb-proxy`. Previously approved suites, the two already running UI cohorts and intermediate IPA packaging are excluded. A CI dispatch or local source check is not a passed Apple SDK result. Actual outcomes must be recorded from the Xcode result tree before claiming runtime validation.
