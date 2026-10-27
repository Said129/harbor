"""Retry only the actual failed native-focus journey; retain all source approvals."""
import json
import os
from pathlib import Path
import re

block = 'poster-focus-completion'
marker = 'native-only:' + block
cases = ['HarborTests.PosterBehaviorMountTests/testActualNativeFocusLoadsWidePixelsReservesWidthRevealsTheCardAndCollapsesForPointerWithoutActivatingIt']
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
suite, method = cases[0].split('.', 1)[1].split('/')
assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))) == 1
captures = ['poster-behavior-native-' + state for state in ['initial', 'focused-wide', 'revealed-last', 'pointer-dock']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=1, pending_native_cases=cases, ui_cases=[], fresh_preparation_executions=0,
    expected_total_executions=1, expected_original_images=4, required_original_captures=captures,
    failed_native_cases_retried=1, parent_partial_run=40441446615, retained_parent_actual_passes=10,
    approved_source_ui_replayed=False, approved_simkl_collections_replayed=False,
    native_focus_environment_injection=False, actual_decoded_wide_pixels_and_layout_required=True,
    native_device_family='iPad', actual_scene_focus_system_required=True,
    previous_unsupported_iphone_run=40495850888,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('One actually failed focus journey/4 original captures; all10parentapprovalsretained. No IPA.')
