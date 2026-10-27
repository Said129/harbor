"""Only failed, genuinely extended or unexecuted behavior after the first queue run."""
import json
import os
from pathlib import Path
import re

block = 'continue-focus-completion'
marker = 'native-only:' + block
cases = [
    'HarborTests.PosterBehaviorMountTests/testActualNativeFocusLoadsWidePixelsReservesWidthRevealsTheCardAndCollapsesForPointerWithoutActivatingIt',
    'HarborTests.ContinueDismissalTests/testDismissalCleanupCannotEraseANewerRealCheckpoint',
    'HarborTests.ContinueDismissalTests/testElevenExecutedDesktopQueueHistoriesMatchActualRequestsAndProtectedReopenWithoutCredentials',
]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
seed = 'HarborTests.ContinuePrivacyInterfaceSeedTests/testPrepareTwoOwnedProfilesSharingAnUnconfiguredGuestSource'
ui = 'HarborExistingAppUITests.ContinuePrivacyNavigationTests/testActualPrivateChoiceLocksSharedSourcesKeepsDownloadsEditableAndRestoresAllChoicesOnIPhone'
for case in cases + [seed, ui]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=3, pending_native_cases=cases, ui_cases=[ui],
    ui_batches=[dict(id='ContinueFocusIPhone', family='IPhone', seed=seed, cases=[ui])],
    preserve_prepared_app_data=True, fresh_preparation_executions=1, expected_total_executions=5,
    expected_original_images=8, required_original_captures=['poster-behavior-native-' + state for state in ['initial', 'focused-wide', 'revealed-last', 'pointer-dock']]
        + ['continue-private-' + state + '-iphone' for state in ['default', 'locked', 'restored', 'unlocked']],
    actual_native_keyboard_focus_required=True, native_device_family='iPad', actual_held_import_and_late_checkpoint_required=True,
    parent_focus_run=40501919855, parent_dismissal_run=40507342605,
    retained_parent_native_passes=9, failed_queue_case_retried=True, unexecuted_phone_ui_only=True, hardware_data_protection_verified=False,
    personal_account_requests=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('3 native failed/extended cases on iPad +1 fresh guest +1 pending phone UI =5 executions/8 captures; retain9 native passes and all approved tablet/Home/source journeys. No IPA.')
