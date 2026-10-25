"""Validate cached shared projections and only failed or affected predecessor behavior."""
import json
import os
from pathlib import Path
import re

marker = 'affected:cached-layout'
cases = []
for suite, count in [('CachedHouseholdLayoutTests', 9), ('LayoutProjectionStorageTests', 2),
                     ('HouseholdLayoutHydrationTests', 8), ('LayoutEditProvenanceTests', 3)]:
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8').split('final class ' + suite + ': XCTestCase {', 1)[1]
    methods = re.findall(r'\bfunc (test\w+)\(', source)
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
affected = {
    'NavigationSyncTests': ['testConflictAdoptsServerAndRestoresOnlyMobileChoicesOnExplicitRequest',
        'testAnEditDuringTheRequestKeepsItsVersionAndUsesTheAcceptedRevisionNext',
        'testFailedQueueWriteRetainsTheNativeEditAndRecoversBeforePullCanReplaceIt'],
    'StreamingSyncTests': ['testConflictAdoptsServerAndExplicitRestoreKeepsTheNewestUnknownDesktopFields',
        'testFailedQueueReplacementRecoversTheNewestLocallySavedCheckboxes',
        'testConflictBackupAndInterruptedApplicationSurviveStorageFailureAndRestart'],
    'PageLayoutSyncTests': ['testAnEditSavedBeforeAQueueFailureIsRecoveredAfterTheProcessReopens',
        'testAConcurrentRemoteLayoutWinsWholeAndTheParkedLocalVersionCanBeRestoredExplicitly',
        'testAdoptionJournalRecoversAnInterruptedCommitWithoutEchoingServerData'],
    'PageCustomizationScopeTests': ['testLegacyLayoutMigratesOnceWithoutOverwritingTheOriginalOrCopyingToAnotherProfile',
        'testExistingDestinationChoicesWinOverLegacyAndRetryingACopyUsesOnlyItsClaimedOwner',
        'testMalformedLegacyLayoutIsPreservedAndNeverReplacedWithDefaultsOrClaimed'],
    'HarborIdentityServerTests': ['testAnOldSessionNeverContactsTheClosedServerOrTransfersItsPendingAppearanceToTheCommunity',
        'testRefreshRetryRestorationAndLogoutKeepTheServerChosenAtLogin'],
    'HarborArtworkServerTests': ['testTheArtworkOriginSurvivesHouseholdRestorationAndDoesNotEnterThePortableRoster'],
}
for suite, methods in affected.items():
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8')
    for method in methods:
        assert len(re.findall(r'\bfunc ' + method + r'\(', source)) == 1
        cases.append('HarborTests.' + suite + '/' + method)
assert len(cases) == len(set(cases)) == 37
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    ui = ['HarborExistingAppUITests.HarborIdentityServerNavigationTests/testTheAccountServerIsVisibleAndChangingItClearsThePasswordOn' + family]
    if family == 'IPad': ui.append('HarborExistingAppUITests.PageContinuationNavigationTests/testOtherWatcherBadgeCoexistsWithAnimeCustomizationOnIPad')
    batches.append(dict(id='CachedLayout' + family, family=family,
        seed='HarborTests.WatchedByInterfaceSeedTests/testPrepareAnotherOwnedWatcherAndAnExplicitDefaultOnAFreshGuest', cases=ui))
    captures += ['identity-server-' + state + '-' + family.lower() for state in ['community', 'custom', 'restored']]
captures += ['anime-continue-' + state + '-ipad' for state in ['initial', 'editing', 'moved', 'renamed', 'hidden', 'restored']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='cached-layout', selection_marker=marker,
    selected_case_count=37, pending_native_cases=cases, ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']],
    preserve_prepared_app_data=True, fresh_preparation_executions=2, expected_total_executions=42,
    expected_original_images=12, required_original_captures=captures, new_cached_projection_cases=11,
    affected_native_cases=23, failed_native_cases=3, failed_ui_cases=3,
    predecessor_run=40191329989, retained_iphone_continuation_ui=True,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    actual_personal_account_login_verified=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Cached layout:11NEW+23AFFECTED+3FAILEDnative+2fresh+3FAILED UI=42executions/12captures. Retain approved iPhone continuation; no IPA.')
