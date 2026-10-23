"""New native Edge narration and mobile panels plus the still-unexecuted note block."""
import json
import os
from pathlib import Path
import re
import runpy

marker = 'HarborTests.EBookNarrationTests/'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
os.environ['HARBOR_NATIVE_SELECTION'] = 'HarborTests.EBookAnnotationTests/'
try:
    runpy.run_path('scripts/ios/prepare-reader-annotations-selection.py')
finally:
    os.environ['HARBOR_NATIVE_SELECTION'] = marker
build = Path('ios/build')
plan = json.loads((build / 'preserved-plugin-integration.json').read_text('utf-8'))
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/EBookNarrationTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 6
plan['pending_native_cases'] += [marker + method for method in methods]
seed = 'HarborTests.ReaderBookmarkInterfaceSeedTests/testPrepareOwnedBookAndTwoBookmarkRoutesInOneFreshGuest'
for family in ['IPhone', 'IPad']:
    case = 'HarborUITests.EBookNarrationNavigationTests/testVoiceSearchSelectionRestorationAndRotatedPanelOn' + family
    plan['ui_batches'].append(dict(id='Narration' + family, family=family, seed=seed, cases=[case]))
    plan['ui_cases'].append(case)
    plan['required_original_captures'] += ['reader-narration-' + state + '-' + family.lower() for state in ['voices', 'search', 'selected', 'restored', 'rotated']]
plan.update(block='reader-narration', selected_case_count=11, new_native_cases=6, unexecuted_annotation_cases=5,
    selection_marker=marker, fresh_preparation_executions=8, expected_total_executions=27, expected_original_images=48,
    new_unexecuted_ui_cases=4, failed_ui_cases_retried=4, previous_annotation_compiler_run=39947821170,
    native_live_edge_cases=1, native_live_edge_text='Harbor owned narration test.')
assert len(plan['pending_native_cases']) == 11 and len(plan['ui_cases']) == len(plan['ui_batches']) == 8
assert len(set(plan['required_original_captures'])) == 48
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in plan['pending_native_cases']) + '\n', 'utf-8')
print('6 NEW narration contracts +5 unexecuted note contracts +8 fresh preparations +8 affected/new UI=27cases48captures. No passed predecessor replay or IPA.')
