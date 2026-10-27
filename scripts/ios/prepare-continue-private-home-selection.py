"""Only the new actual Home/profile/privacy journeys; no model replay."""
import json
import os
from pathlib import Path
import re

block = 'continue-private-home'
marker = 'ui-only:' + block
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='ContinuePrivateHome' + family, family=family,
        seed='HarborTests.ContinuePrivacyHomeSeedTests/testPrepareActualPrivateHistoriesForTwoOwnedProfilesOnOneGuestSource',
        cases=['HarborExistingAppUITests.ContinuePrivacyHomeNavigationTests/testActualHomeSwitchesPrivateHistoriesKeepsDismissalAfterRestartAndRevealsSharedModeOn' + family]))
    captures += ['private-home-' + state + '-' + family.lower() for state in ['primary', 'dismissed', 'other', 'restored', 'shared']]
for case in [case for batch in batches for case in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=0, pending_native_cases=[], ui_only=True, ui_batches=batches,
    ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=2, expected_total_executions=4,
    expected_original_images=10, required_original_captures=captures,
    new_home_ui_cases=2, actual_profile_switch_and_private_dismissal_required=True,
    actual_relaunch_and_shared_mode_required=True, parent_validation_run=40499492159,
    previous_model_results_assumed=False, personal_account_requests=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('2 new actual Home/profile UI +2 fresh owned history preparations=4 executions/10 original captures; no model replay and no IPA.')
