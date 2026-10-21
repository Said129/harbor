# Plugin activity and recovery

The installed plugin row now opens the reference's recent activity: a manual real-title check, result count and time, request count, declared sites, observed sites, and the existing bounded runtime logs. An automatically paused plugin offers Try again; a successful explicit check clears its persisted failure state. Installed settings and secrets are read afresh by the runtime.

The sample is the pinned Desktop 0.9.132 `src/lib/plugins/kinds/stream.ts` request for Fight Club (`tt0137523`, TMDB movie 550, 1999), with the reference's last-title override. Checks use the reference's default 30-second operation budget, bounded to 8–120 seconds. Master pause, disabled or removed installations, profile retirement, and the adult-content preference prevent an ineligible check. Closing the view cancels its consumer and rejects a late result.

The interface uses the original 16 language catalogs and adapts its width to iPhone and iPad. Plugin-declared text stays plugin-owned. Logs are local, limited by the existing pool, and its configured password values are redacted before truncation. Observed hosts are informational, as in the reference row; this view does not pretend to enforce a host allowlist.

## Focused validation

Four new native tests cover the actual worker's sample and current configuration, recovery from a seeded paused installation, master pause and safe failure text, and cancellation of a held request. Two new UI routes check the Spanish result and runtime log on fresh iPhone and iPad guests, with four original captures and two recordings. The two guest preparations are setup, not a replay of the already-approved management route. Prior playback, metadata, pool, and form tests stay unselected.

Source and locale generation are complete. Apple SDK compilation, these eight executions, original image/motion review, and the focused simulator packaging change still require the next validation run. No IPA or full-port approval is implied.
