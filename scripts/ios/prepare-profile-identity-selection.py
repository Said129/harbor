"""Exercise private profile sessions, affected account activation and the failed legacy recovery only."""
import json
import os
from pathlib import Path
import re

marker = 'affected:profile-identity'
cases = []
for suite, count in [('ProfileIdentityMigrationTests', 6), ('ProfileIdentitySessionTests', 6), ('HouseholdIdentitySyncTests', 4)]:
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8').split('final class ' + suite + ': XCTestCase {', 1)[1]
    methods = re.findall(r'\bfunc (test\w+)\(', source)
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
affected = {
    'HouseholdActivationTests': ['testFirstAccountPreservesTheDeviceProfileAndEveryExistingDataNamespace',
        'testAnotherAccountHasSeparateProfilesAndCannotCopyTheFirstAccountsSessionsOrShelves',
        'testAProfilePINSurvivesImportAndMustBeVerifiedBeforeTheNewContextCanExposeItsAccount'],
    'HarborIdentityServerTests': ['testEqualProviderIDsOnDifferentServersActivateSeparateHouseholdsAndSourceSessions'],
    'HarborArtworkServerTests': ['testProductionIdentityActivationPassesTheChosenArtworkServerThroughToTheAppearance'],
    'StreamingSyncTests': ['testConflictBackupAndInterruptedApplicationSurviveStorageFailureAndRestart'],
}
for suite, methods in affected.items():
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8')
    for method in methods:
        assert len(re.findall(r'\bfunc ' + method + r'\(', source)) == 1
        cases.append('HarborTests.' + suite + '/' + method)
assert len(cases) == len(set(cases)) == 22
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='ProfileIdentity' + family, family=family,
        seed='HarborTests.ProfileIdentityInterfaceSeedTests/testPrepareAnOwnedRetiredPrimaryIdentityAndAnUnsignedLinkedSecondaryOnAFreshGuest',
        cases=['HarborExistingAppUITests.ProfileIdentityNavigationTests/testHarborIdentityRemainsPrivateAcrossProfileChangesAndExplicitLogoutSurvivesRelaunchOn' + family]))
    captures += ['profile-identity-' + state + '-' + family.lower() for state in ['primary', 'secondary', 'restored', 'logout-reopened']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='profile-identity', selection_marker=marker,
    selected_case_count=22, pending_native_cases=cases, ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']],
    preserve_prepared_app_data=True, fresh_preparation_executions=2, expected_total_executions=26,
    expected_original_images=8, required_original_captures=captures, new_identity_cases=12,
    affected_identity_cases=9, failed_streaming_cases=1, predecessor_run=40216361279,
    approved_account_server_ui_retained=True, approved_phone_and_pad_continuation_ui_retained=True,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    actual_personal_account_login_verified=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Profile identity:12NEW+9AFFECTED+1FAILEDnative+2fresh+2NEW UI=26executions/8captures. Retain approved server/continuation UI; no IPA.')
