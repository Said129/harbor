"""New private histories and the failed/affected composition only."""
import json
import os
from pathlib import Path
import re

block = 'continue-privacy'
marker = 'affected:' + block
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/ContinuePrivacyTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 9
cases = ['HarborTests.ContinuePrivacyTests/' + method for method in methods]
affected = [
    'HarborTests.LocalContinueTests/testThirteenExecutedDesktopHistoriesPreserveOwnersLimitsOrderingThresholdsAndRecordFields',
    'HarborTests.LocalContinueTests/testProductionPlaybackCommitRestoresStreamingAndDownloadsWithoutACloudWrite',
]
cases += affected
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='ContinuePrivacy' + family, family=family,
        seed='HarborTests.ContinuePrivacyInterfaceSeedTests/testPrepareTwoOwnedProfilesSharingAnUnconfiguredGuestSource',
        cases=['HarborExistingAppUITests.ContinuePrivacyNavigationTests/testActualPrivateChoiceLocksSharedSourcesKeepsDownloadsEditableAndRestoresAllChoicesOn' + family]))
    captures += ['continue-private-' + state + '-' + family.lower() for state in ['default', 'locked', 'restored', 'unlocked']]
for case in cases + [case for batch in batches for case in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=11, pending_native_cases=cases, ui_batches=batches,
    ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=2, expected_total_executions=15,
    expected_original_images=8, required_original_captures=captures,
    new_native_cases=9, failed_date_case=affected[0], actually_affected_composition=affected[1],
    original_reference='ios/HarborTests/Fixtures/continue-privacy-reference.json',
    original_scope_cases=18, original_migration_cases=5, original_resume_cases=4,
    parent_validation_run=40494178199, parent_actual_passes=13,
    personal_account_requests=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False,
    physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('9 new native +1 failed date +1 affected composition +2 fresh guests +2 actual privacy UI=15 executions/8 captures; unchanged approvals retained. No IPA.')
