"""Validate new section isolation and diagnose one failed existing-app route."""
import json
import os
from pathlib import Path
import re

marker = 'affected:layout-batch-startup'
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/LayoutSyncBatchTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 6
cases = ['HarborTests.LayoutSyncBatchTests/' + method for method in methods]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches = [dict(id='AnimeContinuationIPhone', family='IPhone',
    seed='HarborTests.PageContinuationInterfaceSeedTests/testPrepareOwnedContinueHistoryAndPublicAnimeRowsOnAFreshGuest',
    cases=['HarborExistingAppUITests.PageContinuationNavigationTests/testAnimeContinueRowMovesRenamesHidesAndRestoresAfterRelaunchOnIPhone'])]
captures = ['anime-continue-' + state + '-iphone' for state in ['initial', 'editing', 'moved', 'renamed', 'hidden', 'restored']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='layout-batch-startup', selection_marker=marker,
    selected_case_count=6, pending_native_cases=cases, ui_batches=batches, ui_cases=batches[0]['cases'],
    startup_probe=True, preserve_prepared_app_data=True, fresh_preparation_executions=1,
    expected_total_executions=8, expected_original_images=6, required_original_captures=captures,
    new_native_cases=6, failed_ui_cases_retried=1, retained_page_layout_native_run=40142488560,
    retained_page_layout_native_cases=20, retained_reader_native_cases=51, retained_anime_native_cases=8,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Section isolation:6new native+1fresh+1failed UI=8executions/6captures. Startup console/crash diagnostics;20approved native retained. No IPA.')
