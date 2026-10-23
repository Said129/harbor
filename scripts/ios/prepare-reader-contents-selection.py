"""Only the two new reader interfaces and their necessary fresh preparations."""
import json
import os
from pathlib import Path
import re

marker = 'HarborUITests.EBookReaderContentsNavigationTests/'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
seed = 'HarborTests.ReaderContentsInterfaceSeedTests/testPrepareOwnedVolumesAndSavedBookInOneFreshGuest'
ui = ['HarborUITests.EBookReaderContentsNavigationTests/testOriginalReaderVolumePickerCurrentChapterAndRealChapterChangeOn' + device for device in ['IPhone', 'IPad']]
for case in [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
batches = [dict(id='Contents' + device, family=device, seed=seed, cases=[case]) for device, case in zip(['IPhone', 'IPad'], ui)]
captures = ['reader-contents-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['current', 'volume', 'changed', 'next']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reader-contents', selected_case_count=0,
    pending_native_cases=[], new_native_cases=0, ui_only=True, selection_marker=marker,
    ui_cases=ui, ui_batches=batches, fresh_preparation_executions=2,
    expected_total_executions=4, expected_original_images=8, required_original_captures=captures,
    retained_native_model_cases=27, retained_rust_font_cases=5, independent_reader_position_run=39883561558,
    retained_public_metadata_cases=1, retained_public_metadata_run=39881961134,
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('UI only:2 NEW reader contents interfaces +2 fresh preparations,8 original captures. Build without replaying approved native models. No IPA.')
