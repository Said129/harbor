"""Account retirement and source ownership changes, preserving unrelated approved cases."""
import json
import os
from pathlib import Path
import re

block = 'local-source-retirement'
marker = 'affected:' + block
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/LocalSourceMigrationTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 8
cases = ['HarborTests.LocalSourceMigrationTests/' + method for method in methods]
affected = [
    'HarborTests.AppProfileContextTests/testBootstrapKeepsExistingNamespacesAndNeverReadsLegacyAfterTheAtomicClaim',
    'HarborTests.HouseholdActivationTests/testFirstAccountPreservesTheDeviceProfileAndEveryExistingDataNamespace',
]
cases += affected
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
seed = 'HarborTests.ContinuePrivacyInterfaceSeedTests/testPrepareTwoOwnedProfilesSharingAnUnconfiguredGuestSource'
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='HarborLocalAccount' + family, family=family, seed=seed,
        cases=['HarborExistingAppUITests.HarborLocalAccountNavigationTests/testActualAccountKeepsHarborProfilesAndHarborLoginWithoutAnyStremioAccountEntryOn' + family]))
    captures += ['harbor-local-account-' + state + '-' + family.lower() for state in ['profile', 'profiles', 'harbor']]
for case in cases + [item for batch in batches for item in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=10, pending_native_cases=cases, ui_batches=batches,
    ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=2, expected_total_executions=14,
    expected_original_images=6, required_original_captures=captures,
    new_native_cases=8, affected_owner_alias_cases=affected,
    personal_provider_requests=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False,
    actual_bookmark_button_ui_review_complete=False, first_launch_offline_ui_verified=False,
    physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('8 new migration cases +2 affected ownership cases +2 fresh owned guests +2 account UI=14 executions/6 captures; no IPA.')
