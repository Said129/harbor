"""Validate full-roster layouts, affected recovery paths and previously unexecuted server behavior."""
import json
import os
from pathlib import Path
import re

marker = 'affected:household-layout'
cases = []
for suite, count in [('HarborIdentityServerTests', 8), ('HouseholdIdentitySyncTests', 4), ('HarborArtworkServerTests', 8),
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
}
for suite, methods in affected.items():
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8')
    for method in methods:
        assert len(re.findall(r'\bfunc ' + method + r'\(', source)) == 1
        cases.append('HarborTests.' + suite + '/' + method)
assert len(cases) == len(set(cases)) == 43
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='HouseholdLayout' + family, family=family,
        seed='HarborTests.WatchedByInterfaceSeedTests/testPrepareAnotherOwnedWatcherAndAnExplicitDefaultOnAFreshGuest',
        cases=['HarborExistingAppUITests.HarborIdentityServerNavigationTests/testTheAccountServerIsVisibleAndChangingItClearsThePasswordOn' + family,
            'HarborExistingAppUITests.PageContinuationNavigationTests/testOtherWatcherBadgeCoexistsWithAnimeCustomizationOn' + family]))
    captures += ['identity-server-' + state + '-' + family.lower() for state in ['community', 'custom', 'restored']]
    captures += ['anime-continue-' + state + '-' + family.lower() for state in ['initial', 'editing', 'moved', 'renamed', 'hidden', 'restored']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='household-layout', selection_marker=marker,
    selected_case_count=43, pending_native_cases=cases, ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']],
    preserve_prepared_app_data=True, fresh_preparation_executions=2, expected_total_executions=49,
    expected_original_images=18, required_original_captures=captures, new_layout_native_cases=11,
    previously_unexecuted_server_native_cases=20, affected_recovery_and_migration_cases=12,
    previous_zero_execution_run=40186940505, previous_native_compiler_error='Optional guestAddons in an owned assertion',
    retained_household_activation_run=40161132799, retained_direct_activation_cases_selected=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_roster_layout_hydration_implemented=True, automatic_local_edit_fanout=False,
    actual_personal_account_login_verified=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Household layout:11NEW+20UNEXECUTED+12AFFECTEDnative+2fresh+4unapproved UI=49executions/18captures. No unrelated replay or IPA.')
