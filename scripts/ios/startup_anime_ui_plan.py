"""Ordered ordinary-device journeys, with setup executions distinguished from checks."""

def execution_plan():
    rows = []
    def add(group, bundle, suite, method, fixture=False):
        rows.append(dict(group=group, bundle=bundle, target='HarborTests' if fixture else 'HarborUITests',
            suite=suite, method=method, fixture=fixture))
    for family, title in [('iphone', 'IPhone'), ('ipad', 'IPad')]:
        group = 'profiles-' + family
        if family == 'ipad':
            add(group, 'PendingIPadLanguage', 'LanguageReferenceNavigationTests', 'testReferenceLanguagesSwitchInTheOrdinaryIPadSettings')
        add(group, 'Pending' + title + 'Profiles', 'HouseholdProfilesNavigationTests', 'testNormalProfileCreationIdentityAndRestartPINWorkOn' + title)
    for family, title in [('iphone', 'IPhone'), ('ipad', 'IPad')]:
        group = 'startup-' + family
        add(group, 'Startup' + title + 'Configuration', 'ProfileStartupNavigationTests', 'testStartupDefaultAndExplicitProfileChoiceOn' + title)
        add(group, 'Startup' + title + 'Clock', 'ProfileLaunchTests', 'testPrepareAnExpiredOrdinaryDeviceSelectionClockForStartupReturnUI', True)
        add(group, 'Startup' + title + 'Return', 'ProfileStartupNavigationTests', 'testExpiredReturnPromptAndRecentSelectionOn' + title)
        add(group, 'Anime' + title + 'Setup', 'AnimeEpisodeTests', 'testPrepareOrdinaryAnimeUISettings', True)
        add(group, 'Anime' + title + 'Grouping', 'AnimeEpisodesNavigationTests',
            'testSuperShowsContinuousEpisodesAndArtworkAfterFourteen' if family == 'iphone' else 'testSuperRestoresProviderSeasonsAndContinuousEpisodesOnIPad')
    assert len(rows) == 13 and sum(not row['fixture'] for row in rows) == 9
    assert len({row['bundle'] for row in rows}) == len(rows)
    return rows
