"""Select only the newly implemented plugin playback block; no predecessor outcomes are assumed."""
import json
import os
from pathlib import Path
import re
import runpy

requested = os.environ.get('HARBOR_NATIVE_SELECTION', '').strip()
if requested == 'native-only:simkl-playback' or 'HarborTests.SimklPlaybackContractTests/' in requested:
    runpy.run_path('scripts/ios/prepare-simkl-playback-selection.py')
    raise SystemExit(0)
if requested == 'native-only:simkl-library' or 'HarborTests.SimklLibraryContractTests/' in requested:
    runpy.run_path('scripts/ios/prepare-simkl-library-selection.py')
    raise SystemExit(0)
if requested == 'ui-only:artwork-interface-repair':
    runpy.run_path('scripts/ios/prepare-artwork-interface-repair-selection.py')
    raise SystemExit(0)
if requested == 'affected:poster-simkl-completion' or 'HarborTests.SimklClientTests/' in requested:
    runpy.run_path('scripts/ios/prepare-poster-simkl-completion-selection.py')
    raise SystemExit(0)
if requested == 'affected:poster-behavior' or 'HarborTests.PosterBehaviorTests/' in requested:
    runpy.run_path('scripts/ios/prepare-poster-behavior-selection.py')
    raise SystemExit(0)
if requested == 'affected:localized-posters' or 'HarborTests.LocalizedPosterTests/' in requested:
    runpy.run_path('scripts/ios/prepare-localized-poster-selection.py')
    raise SystemExit(0)
if requested == 'affected:card-artwork':
    runpy.run_path('scripts/ios/prepare-card-artwork-selection.py')
    raise SystemExit(0)
if requested == 'affected:poster-appearance':
    runpy.run_path('scripts/ios/prepare-poster-appearance-selection.py')
    raise SystemExit(0)
if requested == 'affected:custom-source-interface':
    runpy.run_path('scripts/ios/prepare-source-interface-selection.py')
    raise SystemExit(0)
if requested in ('affected:custom-sources', 'affected:custom-sources-repair'):
    runpy.run_path('scripts/ios/prepare-custom-source-selection.py')
    raise SystemExit(0)
if requested == 'affected:profile-identity-repair':
    runpy.run_path('scripts/ios/prepare-profile-identity-repair-selection.py')
    raise SystemExit(0)
if requested == 'affected:profile-identity' or 'HarborTests.ProfileIdentityMigrationTests/' in requested:
    runpy.run_path('scripts/ios/prepare-profile-identity-selection.py')
    raise SystemExit(0)
if requested == 'affected:cached-layout' or 'HarborTests.CachedHouseholdLayoutTests/' in requested:
    runpy.run_path('scripts/ios/prepare-cached-layout-selection.py')
    raise SystemExit(0)
if requested == 'affected:household-layout' or 'HarborTests.HouseholdLayoutHydrationTests/' in requested:
    runpy.run_path('scripts/ios/prepare-household-layout-selection.py')
    raise SystemExit(0)
if requested == 'affected:server-completion' or ('HarborTests.HarborArtworkServerTests/' in requested and 'HarborTests.HarborIdentityServerTests/' in requested):
    runpy.run_path('scripts/ios/prepare-server-completion-selection.py')
    raise SystemExit(0)
if requested == 'native-only:artwork-server' or 'HarborTests.HarborArtworkServerTests/' in requested:
    runpy.run_path('scripts/ios/prepare-artwork-server-selection.py')
    raise SystemExit(0)
if requested == 'affected:identity-server' or 'HarborTests.HarborIdentityServerTests/' in requested:
    runpy.run_path('scripts/ios/prepare-identity-server-selection.py')
    raise SystemExit(0)
if requested == 'affected:household-activation' or 'HarborTests.HouseholdIdentitySyncTests/' in requested:
    runpy.run_path('scripts/ios/prepare-household-activation-selection.py')
    raise SystemExit(0)
if requested == 'native-only:player-order-caption' or 'HarborTests.PlayerEpisodePresentationTests/' in requested:
    runpy.run_path('scripts/ios/prepare-player-caption-selection.py')
    raise SystemExit(0)
if requested == 'affected:watched-by' or 'HarborTests.WatchedBySyncTests/' in requested:
    runpy.run_path('scripts/ios/prepare-watched-by-selection.py')
    raise SystemExit(0)
if requested == 'affected:layout-batch-startup' or 'HarborTests.LayoutSyncBatchTests/' in requested:
    runpy.run_path('scripts/ios/prepare-layout-batch-startup-selection.py')
    raise SystemExit(0)
if requested == 'affected:anime-continue-layout' or 'HarborTests.AnimeContinuationLayoutTests/' in requested:
    runpy.run_path('scripts/ios/prepare-anime-continuation-selection.py')
    raise SystemExit(0)
if requested == 'native-only:page-layout-sync' or 'HarborTests.DesktopPageLayoutTests/' in requested:
    runpy.run_path('scripts/ios/prepare-page-layout-sync-selection.py')
    raise SystemExit(0)
if requested == 'ui-only:prepared-app':
    runpy.run_path('scripts/ios/prepare-existing-app-ui-selection.py')
    raise SystemExit(0)
if 'HarborTests.PageCustomizationScopeTests/' in requested:
    runpy.run_path('scripts/ios/prepare-page-customization-scope-selection.py')
    raise SystemExit(0)
if 'HarborTests.DesktopAnimeRowTests/' in requested:
    runpy.run_path('scripts/ios/prepare-desktop-anime-row-selection.py')
    raise SystemExit(0)
if requested == 'ui-only:reading-visible-repair':
    runpy.run_path('scripts/ios/prepare-reading-visible-repair-selection.py')
    raise SystemExit(0)
if 'HarborTests.MusicArtistNativeTests/' in requested:
    runpy.run_path('scripts/ios/prepare-music-artist-selection.py')
    raise SystemExit(0)
if requested in ('affected:music-public-network', 'HarborTests.MusicBillboardPublicTests/testActualPublicHot100KeepsItsPublishedDateRankAndOriginalCatalogIdentity'):
    runpy.run_path('scripts/ios/prepare-music-public-network-selection.py')
    raise SystemExit(0)
if requested == 'affected:music-billboard' or (requested.startswith('HarborTests.MusicBillboardNativeTests/') and 'HarborTests.MusicBillboardPublicTests/' in requested and 'HarborTests.MusicBillboardModelTests/' not in requested):
    runpy.run_path('scripts/ios/prepare-music-billboard-repair-selection.py')
    raise SystemExit(0)
if requested in ('affected:music-explore', 'HarborTests.MusicExploreNativeTests/testOnlyAnonymousProviderGETRequestsRunAndRetiredScopeCannotPublishALateChart'):
    runpy.run_path('scripts/ios/prepare-music-explore-repair-selection.py')
    raise SystemExit(0)
if 'HarborTests.MusicBillboardNativeTests/' in requested:
    runpy.run_path('scripts/ios/prepare-music-billboard-selection.py')
    raise SystemExit(0)
if requested == 'ui-only:reading-visible':
    runpy.run_path('scripts/ios/prepare-reading-visible-selection.py')
    raise SystemExit(0)
if 'HarborTests.MusicExploreNativeTests/' in requested:
    runpy.run_path('scripts/ios/prepare-music-explore-selection.py')
    raise SystemExit(0)
if requested == 'ui-only:reading-final-followup':
    runpy.run_path('scripts/ios/prepare-reading-final-followup-selection.py')
    raise SystemExit(0)
if 'HarborTests.MusicCatalogModelTests/' in requested:
    runpy.run_path('scripts/ios/prepare-music-open-catalog-selection.py')
    raise SystemExit(0)
if 'HarborTests.MusicCollectionsTests/' in requested:
    runpy.run_path('scripts/ios/prepare-music-collections-selection.py')
    raise SystemExit(0)
if requested == 'ui-only:reading-final-repair':
    runpy.run_path('scripts/ios/prepare-reading-final-repair-selection.py')
    raise SystemExit(0)
if requested == 'ui-only:reader-heading':
    runpy.run_path('scripts/ios/prepare-reader-heading-selection.py')
    raise SystemExit(0)
if requested == 'HarborTests.EBookReaderChromeTests/':
    runpy.run_path('scripts/ios/prepare-reader-focus-selection.py')
    raise SystemExit(0)
if requested in ('HarborTests.EBookSourceRefreshTests/', 'native-only:HarborTests.EBookSourceRefreshTests/'):
    runpy.run_path('scripts/ios/prepare-reading-source-refresh-selection.py')
    raise SystemExit(0)
if requested == 'HarborTests.EBookEdgeTokenTests/':
    runpy.run_path('scripts/ios/prepare-reader-narration-repair-selection.py')
    raise SystemExit(0)
if requested == 'HarborTests.EBookNarrationTests/':
    runpy.run_path('scripts/ios/prepare-reader-narration-selection.py')
    raise SystemExit(0)
if requested == 'HarborTests.EBookAnnotationTests/':
    runpy.run_path('scripts/ios/prepare-reader-annotations-selection.py')
    raise SystemExit(0)
if requested == 'HarborTests.EBookTranslationTests/':
    runpy.run_path('scripts/ios/prepare-reader-translation-selection.py')
    raise SystemExit(0)
if requested == 'HarborTests.EBookBookmarkTests/':
    runpy.run_path('scripts/ios/prepare-reader-bookmarks-selection.py')
    raise SystemExit(0)
if requested == 'ui-only:reader-interface-completion':
    runpy.run_path('scripts/ios/prepare-reader-interface-completion-selection.py')
    raise SystemExit(0)
if requested == 'HarborUITests.EBookReaderContentsNavigationTests/':
    runpy.run_path('scripts/ios/prepare-reader-contents-selection.py')
    raise SystemExit(0)
if requested == 'native-only:HarborTests.ReadingPositionMountTests/':
    runpy.run_path('scripts/ios/prepare-reader-position-probe-selection.py')
    raise SystemExit(0)
if 'ReadingPositionMountTests/' in requested:
    runpy.run_path('scripts/ios/prepare-reader-position-selection.py')
    raise SystemExit(0)
if 'EBookMetadataPublicTests/' in requested:
    runpy.run_path('scripts/ios/prepare-reading-surface-selection.py')
    raise SystemExit(0)
if 'EBookSearchTests/' in requested or 'ReadingBrightnessTests/' in requested:
    runpy.run_path('scripts/ios/prepare-reader-completion-selection.py')
    raise SystemExit(0)
if 'EBookPaginationTests/' in requested:
    runpy.run_path('scripts/ios/prepare-book-pagination-selection.py')
    raise SystemExit(0)
if 'ReadingRoutingTests/' in requested:
    runpy.run_path('scripts/ios/prepare-reading-navigation-selection.py')
    raise SystemExit(0)
if 'ReadingWebFontTests/' in requested:
    runpy.run_path('scripts/ios/prepare-web-font-selection.py')
    raise SystemExit(0)
if 'ReadingFontTests/' in requested:
    runpy.run_path('scripts/ios/prepare-reading-display-selection.py')
    raise SystemExit(0)
if 'EBookDetailTests/' in requested or 'EBookLibraryTests/' in requested:
    runpy.run_path('scripts/ios/prepare-ebook-detail-selection.py')
    raise SystemExit(0)
if 'EBookAdaptationTests/' in requested or 'EBookLocalMetadataTests/' in requested:
    runpy.run_path('scripts/ios/prepare-reading-adaptation-selection.py')
    raise SystemExit(0)
if 'EBookMetadataTests/' in requested:
    runpy.run_path('scripts/ios/prepare-reading-metadata-selection.py')
    raise SystemExit(0)
html = ['HarborTests.HarborReadingHTMLTests/' + method for method in [
    'testActualWebKitDOMMatchesAllNineOriginalManualHTMLProviderCases',
    'testManualSourceSaveReadEditDisableAndRemovalKeepDesktopRoutesAndCleanConfiguration',
    'testInvalidManualConfigurationNeverChangesTheInstalledDocument',
    'testCancellingTrustedHTMLCallDoesNotPublishItsLatePageOrBlockOtherCallsAndScopeRetirement']]
if requested and set(item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in requested.split(',')) == set(html):
    selected = [item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in requested.split(',')]
    assert len(selected) == len(set(selected)) == 4
    seed = 'HarborTests.HarborReadingHTMLInterfaceSeedTests/testPrepareOwnedManualSourcesForTheOrdinaryPhoneAndTabletReaders'
    ui = ['HarborUITests.HarborReadingHTMLNavigationTests/testManualSourceEditorValidationAndActualMangaAndBookReadersOn' + device for device in ['IPhone', 'IPad']]
    for case in html + [seed] + ui:
        target, tail = case.split('.', 1); suite, method = tail.split('/')
        assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
    plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reading-html', selected_case_count=4,
        pending_native_cases=html, new_native_cases=4, native_preparation_case=seed, ui_cases=ui,
        expected_total_executions=8, expected_original_images=12,
        required_original_captures=['reading-html-' + state + '-' + device for device in ['iphone', 'ipad'] for state in [
            'editor', 'saved', 'invalid', 'manga-reader', 'book-catalog', 'book-reader']],
        approved_predecessor_cases_repeated=False, prior_preparation_repeated_only_for_fresh_devices=True,
        unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
    directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
    (directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
    (directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in html) + '\n', 'utf-8')
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
    print('4 new manual HTML models, 2 fresh preparations, 2 new phone/tablet routes and 12 captures. No existing worker/reading suite replay. No IPA.')
    raise SystemExit(0)

bulk = ['HarborTests.HarborReadingBulkTests/' + method for method in [
    'testBulkContinuesAfterOneFailureReportsRealProgressUpdatesAndRemovesOnlyInstalledEntries',
    'testAllFailedBulkShowsFailureAndCanRetryWithoutDuplicatingSources',
    'testCancellingBulkRejectsTheHeldDownloadAndLeavesThePreviousCatalog']]
if requested and set(item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in requested.split(',')) == set(bulk):
    selected = [item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in requested.split(',')]
    assert len(selected) == len(set(selected)) == 3
    seed = 'HarborTests.HarborReadingPluginInterfaceSeedTests/testPrepareOwnedBulkRepositoryWithoutInstallingItsEntries'
    ui = ['HarborUITests.HarborReadingBulkNavigationTests/testReadingBulkProgressPartialFailureAndConfirmedUninstallOn' + device for device in ['IPhone', 'IPad']]
    for case in bulk + [seed] + ui:
        target, tail = case.split('.', 1); suite, method = tail.split('/')
        assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
    plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reading-bulk', selected_case_count=3,
        pending_native_cases=bulk, new_native_cases=3, native_preparation_case=seed, ui_cases=ui,
        expected_total_executions=7, expected_original_images=8,
        required_original_captures=['reading-bulk-' + state + '-' + device for device in ['iphone', 'ipad'] for state in [
            'before', 'progress', 'partial', 'uninstalled']],
        approved_predecessor_cases_repeated=False, prior_preparation_repeated_only_for_fresh_devices=True,
        unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
    directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
    (directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
    (directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in bulk) + '\n', 'utf-8')
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
    print('3 new reading bulk models, 2 fresh preparations, 2 new phone/tablet routes and 8 captures. No approved suite replay. No IPA.')
    raise SystemExit(0)

catalog = ['HarborTests.EBookCatalogTests/' + method for method in [
    'testActualJavaScriptCoreMatchesAllTwentyOnePinnedDesktopCatalogCases',
    'testGroupedNativeBooksKeepEveryPlayableRouteAndPersistOldShelves',
    'testRealReadingWorkerCoalescesSupportedTagsAndSeparatesOriginalFromContentLanguage',
    'testMangaTagUsesOriginalSearchContractWithEmptyQueryAndSourceOffset']]
if requested and set(item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in requested.split(',')) == set(catalog):
    selected = [item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in requested.split(',')]
    assert len(selected) == len(set(selected)) == 4
    seed = 'HarborTests.HarborReadingPluginInterfaceSeedTests/testPrepareOwnedCombinedBookCatalogInTheOrdinaryLocalInstallation'
    ui = ['HarborUITests.EBookCatalogNavigationTests/testCombinedBooksFiltersSourceSelectionAndDetailReaderOn' + device for device in ['IPhone', 'IPad']]
    for case in catalog + [seed] + ui:
        target, tail = case.split('.', 1); suite, method = tail.split('/')
        assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
    plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='ebook-catalog', selected_case_count=4,
        pending_native_cases=catalog, new_native_cases=4, native_preparation_case=seed, ui_cases=ui,
        expected_total_executions=8, expected_original_images=10,
        required_original_captures=['ebook-catalog-' + state + '-' + device for device in ['iphone', 'ipad'] for state in [
            'grouped', 'detail', 'alternate-reader', 'filters', 'manga-tag']],
        approved_predecessor_cases_repeated=False, prior_preparation_repeated_only_for_fresh_devices=True,
        unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
    directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
    (directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
    (directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in catalog) + '\n', 'utf-8')
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
    print('4 new catalog/tag models, 2 fresh preparations, 2 new phone/tablet routes and 10 captures. No passed reading, source or activity replay. No IPA.')
    raise SystemExit(0)

reading = ['HarborTests.HarborReadingPluginTests/' + method for method in [
    'testActualWorkerMatchesAllTwentyTwoPinnedReadingReferenceCases',
    'testNativeReadingSourcesInstallBrowseReadAndRetainDistinctKindsWithSanitizedPageHeaders',
    'testMangayomiJSIndexUsesOriginalPreludeForPageSearchDetailsAndConcurrentSourceReuse',
    'testRetiredProfileCancelsAnInFlightReadingInstallAndKeepsThePreviousCatalog']]
activity_retries = ['HarborTests.HarborPluginActivityTests/' + method for method in [
    'testClosingActivityCancelsRealRequestWithoutLateResultOrFailure',
    'testRealCheckUsesDesktopSampleFreshConfigurationAndLastTitleWithVisibleActivity']]
requested_set = set(item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in requested.split(',')) if requested else set()
reading_repair = requested_set == set(reading + activity_retries)
if requested and requested_set == set(reading + activity_retries + catalog + bulk):
    cases = reading + activity_retries + catalog + bulk
    assert len(cases) == 13 and len(requested.split(',')) == 13
    seed = 'HarborTests.HarborReadingPluginInterfaceSeedTests/testPrepareAllPendingReadingInterfacesInOneFreshInstallation'
    ui = ['HarborUITests.HarborCombinedReadingNavigationTests/testAllPendingReadingCatalogAndBulkInterfacesOn' + device for device in ['IPhone', 'IPad']]
    for case in cases + [seed] + ui:
        target, tail = case.split('.', 1); suite, method = tail.split('/')
        assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
    captures = []
    for device in ['iphone', 'ipad']:
        captures += ['reading-plugin-' + state + '-' + device for state in ['manga-installed', 'manga-repository', 'books-installed', 'manga-search', 'manga-reader', 'book-search', 'book-reader', 'book-next']]
        captures += ['ebook-catalog-' + state + '-' + device for state in ['grouped', 'detail', 'alternate-reader', 'filters', 'manga-tag']]
        captures += ['reading-bulk-' + state + '-' + device for state in ['before', 'progress', 'partial', 'uninstalled']]
    plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reading-consolidated', selected_case_count=13,
        pending_native_cases=cases, native_preparation_case=seed, ui_cases=ui, expected_total_executions=17,
        expected_original_images=34, required_original_captures=captures,
        reading_predecessor_run=39666426032, reading_predecessor_actual_executions=0,
        cancelled_catalog_run=39670150636, failed_activity_cases=activity_retries,
        approved_predecessor_cases_repeated=False, prior_preparation_repeated_only_for_fresh_devices=True,
        unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
    directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
    (directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
    (directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
    print('Consolidated: 13 unexecuted/new/actually failed models, 2 fresh preparations, 2 complete reading routes and 34 captures. Retain all previously passed unrelated behavior. No IPA.')
    raise SystemExit(0)

if requested and (requested_set == set(reading) or reading_repair):
    cases = reading + activity_retries if reading_repair else reading
    selected = [item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in requested.split(',')]
    assert len(selected) == len(set(selected)) == len(cases)
    seed = 'HarborTests.HarborReadingPluginInterfaceSeedTests/testPrepareOwnedReadingSourcesInTheOrdinaryLocalInstallation'
    ui = ['HarborUITests.HarborReadingPluginNavigationTests/testOwnedReadingSourcesManagementSearchAndReadersOn' + device for device in ['IPhone', 'IPad']]
    for case in cases + [seed] + ui:
        target, tail = case.split('.', 1); suite, method = tail.split('/')
        assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
    plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reading-repair' if reading_repair else 'reading-plugins', selected_case_count=len(cases),
        pending_native_cases=cases, native_preparation_case=seed, ui_cases=ui, expected_total_executions=len(cases) + 4, expected_original_images=16,
        required_original_captures=['reading-plugin-' + state + '-' + device for device in ['iphone', 'ipad'] for state in [
            'manga-installed', 'manga-repository', 'books-installed', 'manga-search', 'manga-reader', 'book-search', 'book-reader', 'book-next']],
        approved_predecessor_cases_repeated=False, prior_preparation_repeated_only_for_fresh_devices=True,
        unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
    if reading_repair:
        plan.update(reading_predecessor_run=39637899685, reading_predecessor_actual_executions=0,
            activity_predecessor_run=39629636444, activity_predecessor_actual_executions=8,
            activity_predecessor_passed_executions_retained=6, failed_activity_cases=activity_retries,
            ordered_predecessor_run=39634418674, ordered_predecessor_actual_passes_retained=5)
    directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
    (directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
    (directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
    print(str(len(cases)) + ' new/unexecuted/failed models, 2 fresh reading preparations and 2 new reading UI routes. 16 captures; no passed source, activity UI or ordered-model replay. No IPA.')
    raise SystemExit(0)

ordered = ['HarborTests.HarborPluginRuntimeTests/testOptionalOrderedJSONRepliesPreserveNestedOrderWithoutChangingConcurrentNormalCallsOrCancellation',
    'HarborTests.HarborPluginStreamSourceTests/testOriginalWorkerHeaderOrderSurvivesThePoolAndAdapterHeaderLimit']
ordered += ['HarborTests.HarborPluginStreamAdapterTests/' + method for method in [
    'testActualWebKitRunsAllTwentyOriginalStreamAdapterReferenceCases',
    'testCancellingOneCallerDoesNotRetireAnotherCallOrTheSharedPureContext',
    'testConcurrentCallsKeepEachTrackingPolicyAndSubsequentDefaultIndependent']]
if requested and set(item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in requested.split(',')) == set(ordered):
    selected = [item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in requested.split(',')]
    assert len(selected) == len(set(selected)) == 5
    for case in ordered:
        suite, method = case.split('.', 1)[1].split('/')
        assert re.search(r'\bfunc ' + method + r'\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='plugin-object-order', selected_case_count=5,
        pending_native_cases=ordered, expected_total_executions=5, expected_original_images=0, ui_cases=[], required_original_captures=[],
        predecessor_run=39623835388, predecessor_source='611784ae29de26991c5aba30c72e288a9b43ad6e', predecessor_actual_executions=13,
        predecessor_passed_executions_retained=12, failed_native_cases=1, new_native_cases=2, affected_native_cases=2,
        unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
    directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
    (directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
    (directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in ordered) + '\n', 'utf-8')
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
    print('1 failed adapter, 2 affected encoding/cancellation models and 2 new ordered delivery contracts. No passed source/UI/startup replay. No IPA.')
    raise SystemExit(0)

activity = ['HarborTests.HarborPluginActivityTests/' + method for method in [
    'testRealCheckUsesDesktopSampleFreshConfigurationAndLastTitleWithVisibleActivity',
    'testExplicitActivityCheckRecoversAnAlreadyPausedInstallationAndPersistsIt',
    'testPausedMasterBlocksChecksAndFailedCheckShowsOnlySafeRuntimeCode',
    'testClosingActivityCancelsRealRequestWithoutLateResultOrFailure']]
if requested and set(item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in requested.split(',')) == set(activity):
    selected = [item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in requested.split(',')]
    assert len(selected) == len(set(selected)) == 4
    seed = 'HarborTests.HarborPluginInterfaceSeedTests/testPrepareOwnedPluginInTheOrdinaryLocalInstallation'
    ui = ['HarborUITests.HarborPluginNavigationTests/testPluginActivityCheckOn' + device for device in ['IPhone', 'IPad']]
    for case in activity + [seed] + ui:
        target, tail = case.split('.', 1); suite, method = tail.split('/')
        assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
    plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='plugin-activity', selected_case_count=4,
        pending_native_cases=activity, new_native_cases=4, native_preparation_case=seed, ui_cases=ui,
        expected_total_executions=8, expected_original_images=4,
        required_original_captures=['plugin-activity-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['before', 'after']],
        approved_predecessor_cases_repeated=False, prior_preparation_repeated_only_for_fresh_devices=True,
        unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
        full_desktop_parity_complete=False, ipa_requested=False)
    directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
    (directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
    (directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in activity) + '\n', 'utf-8')
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
    print('4 new activity models, 2 fresh preparations and 2 new activity routes. No prior playback or manager suite replay. No IPA.')
    raise SystemExit(0)

if requested:
    startup = ['HarborTests.HarborNativeNetworkTests/testMaximumRPCResponseCrossesActualWebKitWorkerBridge',
        'HarborTests.HarborPluginRuntimeTests/testWorkerInitializationKeepsItsTenSecondBudgetAfterTheNativeHostIsReady',
        'HarborTests.HarborPluginRuntimeTests/testTimeoutTerminatesABusyWorkerWithoutBlockingAnotherInstance']
    failed = ['HarborTests.HarborPluginStreamAdapterTests/' + method for method in [
        'testActualWebKitRunsAllTwentyOriginalStreamAdapterReferenceCases',
        'testCancellingOneCallerDoesNotRetireAnotherCallOrTheSharedPureContext',
        'testConcurrentCallsKeepEachTrackingPolicyAndSubsequentDefaultIndependent']]
    failed += ['HarborTests.HarborPluginStreamSourceTests/' + method for method in [
        'testActualDetailSelectionMergesPluginWorkersThroughOriginalAdapterRankingAndDirectSubtitleResolution',
        'testMasterPauseCancelsActiveProviderWithoutRemovingItOrBreakingSubsequentPlayback',
        'testRepositoryGroupingKeepsWorkingMembersAndSkipsProviderWithoutTMDBWithoutCountingFailure']]
    selected = [item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in requested.split(',')]
    repair = set(selected) == set(startup + failed)
    cases = startup + failed if repair else startup
    assert len(selected) == len(set(selected)) == len(cases) and set(selected) == set(cases)
    for case in cases:
        suite, method = case.split('.', 1)[1].split('/')
        assert re.search(r'\bfunc ' + method + r'\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
    ui = ['HarborUITests.HarborPluginNavigationTests/testNewPluginPlaybackOptionsPersistOn' + device for device in ['IPhone', 'IPad']] if repair else []
    seed = 'HarborTests.HarborPluginInterfaceSeedTests/testPrepareOwnedPluginInTheOrdinaryLocalInstallation'
    plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='plugin-repair' if repair else 'plugin-startup', selected_case_count=len(cases),
        pending_native_cases=cases, failed_case=cases[0], new_case=cases[1], affected_case=cases[2],
        expected_total_executions=len(cases) + (4 if repair else 0), expected_original_images=4 if repair else 0, ui_cases=ui,
        native_preparation_case=seed if repair else None,
        required_original_captures=['plugin-options-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['paused', 'restored']] if repair else [],
        predecessor_run=39587372660, predecessor_source='cfe4160368baf1c33299aec06ddf8ec365f6e38b',
        predecessor_original_job_log_sha256='505086b292a161ef73f19075453d1d5b1d0563ac7b82e7d18606134e544ea3c0',
        predecessor_completed_executions=28, predecessor_passed_executions=27, predecessor_failed_executions=1,
        unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
        full_desktop_parity_complete=False, ipa_requested=False)
    if repair:
        plan.update(playback_predecessor_run=39596075675, playback_predecessor_source='481c346e60bebd16fa49b54fe6605105157f1a57',
            playback_original_model_tree_sha256='cdb88eaa502a3892f171ea823efffe134d73d8f60092c437d2c0267e0f1d21dc',
            playback_failed_native_cases=failed, playback_passed_native_cases_retained=4, prior_preparation_repeated_only_for_fresh_devices=True)
    (directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
    (directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=' + ('true' if repair else 'false') + '\n')
    print(json.dumps(dict(selected_models=len(cases), failed_models=7 if repair else 1, new_models=1, affected_models=1,
        retry_ui=len(ui), approved_request_models_repeated=False, ipa_requested=False)))
    raise SystemExit(0)

cases = []
for suite, count in [('HarborPluginStreamAdapterTests', 3), ('HarborPluginStreamRequestTests', 3), ('HarborPluginStreamSourceTests', 5)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
assert len(cases) == len(set(cases)) == 11
seed = 'HarborTests.HarborPluginInterfaceSeedTests/testPrepareOwnedPluginInTheOrdinaryLocalInstallation'
ui = ['HarborUITests.HarborPluginNavigationTests/testNewPluginPlaybackOptionsPersistOn' + device for device in ['IPhone', 'IPad']]
for case in cases + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='plugin-playback', selected_case_count=len(cases),
    pending_native_cases=cases, new_native_cases=11, native_preparation_case=seed, ui_cases=ui,
    expected_total_executions=15, expected_original_images=4,
    required_original_captures=['plugin-options-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['paused', 'restored']],
    predecessor_run=39587372660, predecessor_source='cfe4160368baf1c33299aec06ddf8ec365f6e38b',
    predecessor_results_assumed=False, predecessor_tests_repeated=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, public_network_case_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('11 playback models, 2 fresh device preparations and 2 option routes. Previous-run outcomes remain independent. No IPA.')
