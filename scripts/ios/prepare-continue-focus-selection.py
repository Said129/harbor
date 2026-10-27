"""Only the unresolved native keyboard journey and the new clear/import race."""
import json
import os
from pathlib import Path
import re

block = 'continue-focus-completion'
marker = 'native-only:' + block
cases = [
    'HarborTests.PosterBehaviorMountTests/testActualNativeFocusLoadsWidePixelsReservesWidthRevealsTheCardAndCollapsesForPointerWithoutActivatingIt',
    'HarborTests.ContinueDismissalTests/testDismissalCleanupCannotEraseANewerRealCheckpoint',
]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
for case in cases:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=2, pending_native_cases=cases, ui_cases=[], fresh_preparation_executions=0, expected_total_executions=2,
    expected_original_images=4, required_original_captures=['poster-behavior-native-' + state for state in ['initial', 'focused-wide', 'revealed-last', 'pointer-dock']],
    actual_native_keyboard_focus_required=True, native_device_family='iPad', actual_held_import_and_late_checkpoint_required=True,
    parent_focus_run=40501919855, parent_dismissal_run=40507342605,
    personal_account_requests=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('One failed actual native keyboard journey plus one genuinely extended clear/import race:2 native cases on iPad/4 original captures, no source/settings/Home replay or IPA.')
