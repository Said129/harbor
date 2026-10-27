"""New durable library/dismissal behavior plus only affected models and failed phone UI."""
import json
import os
from pathlib import Path
import re

block = 'continue-dismissal'
marker = 'affected:' + block
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/ContinueDismissalTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 8
affected = [
    'HarborTests.ContinuePrivacyTests/testPrivateProjectionAndResumeExcludeNewerSharedCloudAndOtherProfilesAndKeepDismissalsSeparate',
    'HarborTests.ContinuePrivacyTests/testUnavailablePrivateMigrationCannotFallBackToSharedCardsAndFailedDismissalKeepsPreviousChoices',
    'HarborTests.SimklPlaybackImportTests/testProductionLibraryMergesImportedCardsWithoutSavingThemInStremioAndDismissalSurvivesRefresh',
]
cases = ['HarborTests.ContinueDismissalTests/' + method for method in methods] + affected
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
seed = 'HarborTests.ContinuePrivacyInterfaceSeedTests/testPrepareTwoOwnedProfilesSharingAnUnconfiguredGuestSource'
ui = 'HarborExistingAppUITests.ContinuePrivacyNavigationTests/testActualPrivateChoiceLocksSharedSourcesKeepsDownloadsEditableAndRestoresAllChoicesOnIPhone'
for case in cases + [seed, ui]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=11, pending_native_cases=cases,
    ui_batches=[dict(id='ContinueDismissalIPhone', family='IPhone', seed=seed, cases=[ui])], ui_cases=[ui],
    preserve_prepared_app_data=True, fresh_preparation_executions=1, expected_total_executions=13,
    expected_original_images=4, required_original_captures=['continue-private-' + state + '-iphone' for state in ['default', 'locked', 'restored', 'unlocked']],
    original_reference='ios/HarborTests/Fixtures/continue-dismissal-reference.json',
    original_dismissal_cases=10, original_queue_cases=11, new_native_cases=8, genuinely_affected_cases=affected,
    failed_phone_ui_only=True, parent_validation_run=40499492159, parent_actual_passes=14,
    personal_account_requests=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('8 new +3 affected native; 1 fresh guest +1 previously failed iPhone UI =13 executions/4 captures. No approved iPad replay, no IPA.')
