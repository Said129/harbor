import XCTest
@testable import Harbor

/// Desktop's content advisory (`components/player/content-advisory-toast.tsx`, `content-advisory-prompt.tsx`,
/// `views/player/hooks/use-content-advisory.ts`, `lib/providers/harbor-imdb.ts`). Scripted data only; no network.
final class ContentAdvisoryRulesTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func testGuideReadsCategoriesAndMpaRatingAndSkipsIncompleteEntries() throws {
        let guide = ContentAdvisory.guide(try json(#"{"categories":[{"category":"Violence","severity":"Severe"},{"category":"Profanity"},{"severity":"Mild"},{"category":"Frightening","severity":"Mild"}],"mpaRating":"R"}"#))
        XCTAssertEqual(guide.categories, [ContentAdvisoryCategory(category: "Violence", severity: "Severe"),
                                          ContentAdvisoryCategory(category: "Frightening", severity: "Mild")])
        XCTAssertEqual(guide.mpaRating, "R")
    }

    func testEmptyMpaRatingIsNoRatingAndAGuideWithoutRowsShowsNothing() throws {
        let guide = ContentAdvisory.guide(try json(#"{"categories":[],"mpaRating":""}"#))
        XCTAssertNil(guide.mpaRating)
        XCTAssertFalse(ContentAdvisory.showsContent(guide))
    }

    func testRatedDropsNoneAndUnknownAndSortsMostSevereFirstKeepingServerOrderOnTies() {
        let rated = ContentAdvisory.rated([
            .init(category: "Profanity", severity: "Mild"),
            .init(category: "Nudity", severity: "None"),
            .init(category: "Gore", severity: "Unknown"),
            .init(category: "Violence", severity: "Moderate"),
            .init(category: "Drugs", severity: "Mild"),
            .init(category: "Sex", severity: "Severe"),
        ])
        XCTAssertEqual(rated.map(\.category), ["Sex", "Violence", "Profanity", "Drugs"])
    }

    func testContentNeedsARatedCategoryOrAnMpaRating() {
        XCTAssertTrue(ContentAdvisory.showsContent(.init(categories: [.init(category: "Violence", severity: "Mild")])))
        XCTAssertTrue(ContentAdvisory.showsContent(.init(mpaRating: "PG-13")))
        XCTAssertFalse(ContentAdvisory.showsContent(.init(categories: [.init(category: "Violence", severity: "None")])))
    }

    func testImdbIDTakesTheTitleFromEpisodeAndStreamIDs() {
        XCTAssertEqual(ContentAdvisory.imdbID(in: "tt0903747:1:2"), "tt0903747")
        XCTAssertEqual(ContentAdvisory.imdbID(in: "tt1234567"), "tt1234567")
        XCTAssertNil(ContentAdvisory.imdbID(in: "iptv:channel-9"))
        XCTAssertNil(ContentAdvisory.imdbID(in: nil))
    }

    func testPresentationUsesDesktopLabelsAndKeepsAnUnknownCategoryAsItIs() {
        XCTAssertEqual(ContentAdvisory.presentation(of: "Sex & Nudity").label, "Sex & Nudity")
        XCTAssertEqual(ContentAdvisory.presentation(of: "Graphic Violence").label, "Violence & Gore")
        XCTAssertEqual(ContentAdvisory.presentation(of: "Strong Language").label, "Profanity")
        XCTAssertEqual(ContentAdvisory.presentation(of: "Drugs, Alcohol, Smoking").label, "Alcohol, Drugs & Smoking")
        XCTAssertEqual(ContentAdvisory.presentation(of: "Intense scenes").label, "Frightening & Intense Scenes")
        XCTAssertEqual(ContentAdvisory.presentation(of: "Other").label, "Other")
        XCTAssertEqual(ContentAdvisory.presentation(of: "Other").symbol, "info.circle")
    }

    func testToneFollowsTheThemeAndAnUnknownSeverityTakesMild() {
        XCTAssertEqual(ContentAdvisory.tone(severity: "Severe", theme: .colored), .danger)
        XCTAssertEqual(ContentAdvisory.tone(severity: "Moderate", theme: .colored), .accent)
        XCTAssertEqual(ContentAdvisory.tone(severity: "Mild", theme: .colored), .white(0.6))
        XCTAssertEqual(ContentAdvisory.tone(severity: "Odd", theme: .colored), .white(0.6))
        XCTAssertEqual(ContentAdvisory.tone(severity: "Severe", theme: .monochrome), .white(0.85))
        XCTAssertEqual(ContentAdvisory.tone(severity: "Moderate", theme: .monochrome), .white(0.7))
        XCTAssertEqual(ContentAdvisory.tone(severity: "None", theme: .monochrome), .white(0.5))
    }

    func testThemeDefaultsToMonochromeForAnyOtherStoredValue() {
        XCTAssertEqual(ContentAdvisoryTheme(stored: nil), .monochrome)
        XCTAssertEqual(ContentAdvisoryTheme(stored: "rainbow"), .monochrome)
        XCTAssertEqual(ContentAdvisoryTheme(stored: "colored"), .colored)
    }

    func testPlaybackCountsAsStartedPastThreeTenthsOfASecond() {
        XCTAssertFalse(ContentAdvisory.hasPlaybackStarted(position: 0.3))
        XCTAssertTrue(ContentAdvisory.hasPlaybackStarted(position: 0.31))
    }

    func testPromptDecisionShowsOnceAndNeverWithTheCardAlreadyOn() {
        XCTAssertEqual(ContentAdvisory.promptDecision(seen: true, toastOn: false, ready: true), .none)
        XCTAssertEqual(ContentAdvisory.promptDecision(seen: false, toastOn: true, ready: true), .markSeen)
        XCTAssertEqual(ContentAdvisory.promptDecision(seen: false, toastOn: false, ready: false), .none)
        XCTAssertEqual(ContentAdvisory.promptDecision(seen: false, toastOn: false, ready: true), .show)
    }
}

final class ContentAdvisoryTimelineTests: XCTestCase {
    func testToastWaitsForItsInputsThenHoldsOnceForEachSource() {
        var toast = ContentAdvisoryToastState()
        toast.update(enabled: true, ready: false)
        XCTAssertEqual(toast.phase, .idle)
        toast.update(enabled: true, ready: true)
        XCTAssertEqual(toast.phase, .holding)
        XCTAssertEqual(toast.pendingDelay, ContentAdvisory.holdSeconds)
        toast.holdElapsed()
        XCTAssertEqual(toast.phase, .collapsing)
        toast.exitElapsed()
        XCTAssertEqual(toast.phase, .done)
        toast.update(enabled: true, ready: true)
        XCTAssertEqual(toast.phase, .done, "a source shows its card once")
    }

    func testTheOffSettingNeverTriggers() {
        var toast = ContentAdvisoryToastState()
        toast.update(enabled: false, ready: true)
        XCTAssertEqual(toast.phase, .idle)
        XCTAssertFalse(toast.isVisible)
    }

    func testAPointerOverTheCardPausesTheHoldAndLeavingGivesTheShortTail() {
        var toast = ContentAdvisoryToastState()
        toast.update(enabled: true, ready: true)
        toast.pointerEntered()
        XCTAssertNil(toast.pendingDelay)
        toast.holdElapsed()
        XCTAssertEqual(toast.phase, .holding, "a hovered card stays")
        toast.pointerLeft()
        XCTAssertEqual(toast.pendingDelay, ContentAdvisory.hoverTailSeconds)
        toast.holdElapsed()
        XCTAssertEqual(toast.phase, .collapsing)
    }

    func testDismissFadesAtOnceAndThenIsGone() {
        var toast = ContentAdvisoryToastState()
        toast.update(enabled: true, ready: true)
        toast.dismiss()
        XCTAssertEqual(toast.phase, .collapsing)
        XCTAssertTrue(toast.isVisible, "the card is still on screen while it fades")
        toast.exitElapsed()
        XCTAssertEqual(toast.phase, .done)
        XCTAssertFalse(toast.isVisible)
    }

    func testTurningTheCardOffClearsTheTimelineSoItCanShowAgain() {
        var toast = ContentAdvisoryToastState()
        toast.update(enabled: true, ready: true)
        toast.holdElapsed()
        toast.exitElapsed()
        toast.update(enabled: false, ready: true)
        XCTAssertEqual(toast.phase, .idle)
        toast.update(enabled: true, ready: true)
        XCTAssertEqual(toast.phase, .holding)
    }

    func testThePromptHoldsForTwelveSecondsUnlessThePointerIsOverIt() {
        var prompt = ContentAdvisoryPromptState()
        prompt.show()
        XCTAssertEqual(prompt.pendingDelay, ContentAdvisory.promptHoldSeconds)
        prompt.pointerChanged(inside: true)
        XCTAssertNil(prompt.pendingDelay)
        prompt.holdElapsed()
        XCTAssertEqual(prompt.phase, .visible)
        prompt.pointerChanged(inside: false)
        prompt.holdElapsed()
        XCTAssertEqual(prompt.phase, .exiting)
        prompt.exitElapsed()
        XCTAssertFalse(prompt.isShown)
    }

    func testTurnOnAndNotNowCloseThePromptAtOnce() {
        var prompt = ContentAdvisoryPromptState()
        prompt.show()
        prompt.close()
        XCTAssertEqual(prompt.phase, .exiting)
        prompt.exitElapsed()
        XCTAssertFalse(prompt.isShown)
    }
}

final class ContentAdvisoryStoreTests: XCTestCase {
    /// Records the requests and answers each from a script, so the tests can count the calls without a network.
    private final class ScriptedGuides: @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [URL] = []
        private let reply: @Sendable (URL) throws -> JSONValue

        init(reply: @escaping @Sendable (URL) throws -> JSONValue) { self.reply = reply }

        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return requests.count
        }

        func answer(_ url: URL) throws -> JSONValue {
            lock.lock(); requests.append(url); lock.unlock()
            return try reply(url)
        }
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func testOnlyTitleIDsReachTheCommunityServer() async {
        XCTAssertEqual(HarborAdvisoryRatings.url("tt0903747")?.absoluteString, "https://harborcommunity.site/api/imdb/parental/tt0903747")
        XCTAssertNil(HarborAdvisoryRatings.url("tt0903747:1:2"))
        let script = ScriptedGuides(reply: { _ in throw HarborError(code: "unused") })
        let ratings = HarborAdvisoryRatings(fetch: { try script.answer($0) })
        let guide = await ratings.guide("iptv:9")
        XCTAssertEqual(guide, ContentAdvisoryGuide())
        XCTAssertEqual(script.count, 0)
    }

    func testAGuideIsFetchedOnceAndAFailureIsKeptForTheSession() async throws {
        let guide = try json(#"{"categories":[{"category":"Violence","severity":"Moderate"}],"mpaRating":"R"}"#)
        let script = ScriptedGuides(reply: { url in
            if url.absoluteString.hasSuffix("/tt0903747") { return guide }
            throw HarborError(code: "network")
        })
        let ratings = HarborAdvisoryRatings(fetch: { try script.answer($0) })
        let first = await ratings.guide("tt0903747")
        XCTAssertEqual(first.mpaRating, "R")
        XCTAssertEqual(first.categories.first?.category, "Violence")
        _ = await ratings.guide("tt0903747")
        XCTAssertEqual(script.count, 1, "a second read is served from the cache")

        let failed = await ratings.guide("tt7777777")
        XCTAssertEqual(failed, ContentAdvisoryGuide())
        _ = await ratings.guide("tt7777777")
        XCTAssertEqual(script.count, 2, "a failed title is kept for the session, as Desktop keeps it")
    }

    @MainActor func testIgnoredTitlesStayOnThisDeviceUntilRestored() {
        let suite = "ContentAdvisoryIgnoreTests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let ignores = ContentAdvisoryIgnores(defaults: store)
        XCTAssertFalse(ignores.isIgnored("tt0903747"))
        ignores.ignore("tt0903747")
        ignores.ignore("tt0903747")
        XCTAssertEqual(ignores.count, 1)
        XCTAssertTrue(ContentAdvisoryIgnores(defaults: store).isIgnored("tt0903747"), "a new instance reads the saved list")
        XCTAssertFalse(ignores.isIgnored(nil))
        ignores.clear()
        XCTAssertEqual(ContentAdvisoryIgnores(defaults: store).count, 0)
    }

    func testTheSwitchesFollowTheProfileButTheIgnoreListAndNudgeDoNot() {
        XCTAssertTrue(ProfileSettingsStore.keys.isSuperset(of: ["contentAdvisoryToast", "contentAdvisoryTheme", "contentAdvisoryShowIgnore"]))
        XCTAssertFalse(ProfileSettingsStore.keys.contains(ContentAdvisoryIgnores.key), "ignored titles are device-level, as in Desktop")
        XCTAssertFalse(ProfileSettingsStore.keys.contains(ContentAdvisoryPreferences.nudgeKey), "the invitation is seen once per device")
    }

    @MainActor func testPreferencesDefaultOffMonochromeAndReloadFromDefaults() {
        let keys = ["contentAdvisoryToast", "contentAdvisoryTheme", "contentAdvisoryShowIgnore", ContentAdvisoryPreferences.nudgeKey]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        defer { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
        let preferences = ContentAdvisoryPreferences()
        XCTAssertFalse(preferences.showToast)
        XCTAssertEqual(preferences.theme, .monochrome)
        XCTAssertTrue(preferences.showIgnoreButton)
        XCTAssertFalse(preferences.nudgeSeen)

        UserDefaults.standard.set("colored", forKey: "contentAdvisoryTheme")
        UserDefaults.standard.set(true, forKey: "contentAdvisoryToast")
        preferences.reloadPreferences()
        XCTAssertEqual(preferences.theme, .colored)
        XCTAssertTrue(preferences.showToast)
        XCTAssertFalse(preferences.nudgeSeen, "a profile reload does not count as dismissing the invitation")

        preferences.showToast = false
        XCTAssertTrue(preferences.nudgeSeen, "a change made in settings dismisses the invitation, as in Desktop")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "contentAdvisoryToast"))
    }
}
