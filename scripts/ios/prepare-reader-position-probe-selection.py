"""Diagnose the one actual failed mounted contract without repeating the live UI run."""
import json
import os
from pathlib import Path
import re

cases = ['HarborTests.ReadingPositionMountTests/testActualMountedNativeScrollRestoresThePrintedParagraphThenJumpsAndAcceptsScrollingBack']
marker = 'native-only:HarborTests.ReadingPositionMountTests/'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
assert re.search(r'\bfunc ' + cases[0].split('/')[-1] + r'\(', Path('ios/HarborTests/ReadingPositionMountTests.swift').read_text('utf-8'))
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reader-position-probe', selected_case_count=1,
    pending_native_cases=cases, new_native_cases=0, failed_native_cases_retried=1,
    selection_marker=marker,
    ui_cases=[], expected_total_executions=1, expected_original_images=0, required_original_captures=[],
    retained_native_model_cases=27, retained_rust_font_cases=5, retained_public_metadata_cases=1,
    independent_ui_run=39883561558, prior_failed_native_run=39883561558,
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text(cases[0].replace('.', '/', 1) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('Only the one failed native mounted contract with phase/offset diagnostics. Its independent8UI remain in the original run; no approved tests repeated. No IPA.')
