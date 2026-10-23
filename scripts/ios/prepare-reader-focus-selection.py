"""Select only the new focus lifetime contracts and two original-delay mobile journeys."""
import json
import os
from pathlib import Path
import re

marker = 'HarborTests.EBookReaderChromeTests/'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
models = [marker + name for name in [
    'testIdleHidesControlsAndInteractionRestartsTheTimerWithoutAStaleHide',
    'testPresentedPanelAccessibilityAndLeavingTheReaderCancelThePendingHideAndReleaseIt']]
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    case = 'HarborUITests.EBookReaderChromeNavigationTests/testFocusHidesAndRevealsControlsKeepsPanelsUsableAndRestoresAfterRelaunchOn' + family
    batches.append(dict(id=family, family=family, seed='HarborTests.ReaderBookmarkInterfaceSeedTests/testPrepareOwnedBookAndTwoBookmarkRoutesInOneFreshGuest', cases=[case]))
    captures += ['reader-focus-' + state + '-' + family.lower() for state in ['initial', 'panel', 'hidden', 'revealed', 'restored', 'disabled']]
ui = [case for batch in batches for case in batch['cases']]
for case in models + [row['seed'] for row in batches] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reader-focus', selection_marker=marker,
    selected_case_count=2, pending_native_cases=models, new_native_cases=2,
    ui_batches=batches, ui_cases=ui, fresh_preparation_executions=2, new_ui_cases=2,
    expected_total_executions=6, expected_original_images=12, required_original_captures=captures,
    retained_native_model_cases=48, retained_public_metadata_cases=1, retained_rust_font_cases=5,
    retained_reader_ui_methods=14, approved_predecessor_cases_repeated=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
assert len(set(models)) == len(ui) == len(batches) == 2 and len(set(captures)) == 12
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in models) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('2 NEW native focus lifetime cases +2 fresh +2 NEW UI=6cases12captures; no previous approved suites or IPA.')
