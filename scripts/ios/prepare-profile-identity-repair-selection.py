"""Select the failed account fixture, affected signed-out cache and new shared watches."""
import json
import os
from pathlib import Path
import re

marker = 'affected:profile-identity-repair'
selected = [
    'HarborTests.ProfileIdentitySessionTests/testExplicitAuthenticationToAnotherHouseholdKeepsTheInitiatingIdentityPrivateAndDoesNotShareItWithOtherProfiles',
    'HarborTests.ProfileIdentitySessionTests/testSigningOutAndReopeningRetainAllCachedSectionsAndSharedWatchAttributionWithoutResurrectingTheLegacyToken',
    'HarborTests.ProfileIdentitySessionTests/testSharedWatchAttributionStaysCurrentAcrossPrivateIdentityCoordinatorsWithoutSharingTheirCredentials',
]
for case in selected:
    suite, method = case.split('.', 1)[1].split('/')
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8')
    assert len(re.findall(r'\bfunc ' + method + r'\(', source)) == 1
assert len(selected) == len(set(selected)) == 3
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == selected
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='profile-identity-repair', selection_marker=marker,
    selected_case_count=3, pending_native_cases=selected, ui_cases=[], fresh_preparation_executions=0,
    expected_total_executions=3, expected_original_images=0, required_original_captures=[],
    new_shared_watch_cases=1, failed_identity_cases=1, affected_signed_out_cache_cases=1, predecessor_run=40219962030,
    predecessor_executions=26, predecessor_native_passed=21, predecessor_native_failed=1,
    retained_unaffected_native_passes=20, retained_fresh_preparations=2, retained_identity_ui_passes=2,
    approved_account_server_ui_retained=True, approved_phone_and_pad_continuation_ui_retained=True,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    actual_personal_account_login_verified=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in selected) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('Profile identity repair:1NEW+1FAILED+1AFFECTEDnative=3executions. Retain 20 unaffected native passes and both approved identity UI flows; no IPA.')
