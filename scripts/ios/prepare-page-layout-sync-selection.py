"""Validate the new Desktop home/anime codec and profile-scoped queue only."""
import json
import os
from pathlib import Path
import re

marker = 'native-only:page-layout-sync'
cases = []
for suite, count in [('DesktopPageLayoutTests', 6), ('PageLayoutSyncTests', 10)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='page-layout-sync', selection_marker=marker,
    selected_case_count=16, pending_native_cases=cases, ui_cases=[], fresh_preparation_executions=0,
    expected_total_executions=16, expected_original_images=0, required_original_captures=[],
    new_native_cases=16, retained_anime_native_cases=8, retained_reader_native_cases=51,
    watched_by_adapter_still_pending=True, household_account_activation_still_pending=True,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    interface_review_pending=True, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('Page layouts:16 new codec/scope/queue/conflict/recovery contracts only; no approved suites repeated, no UI or IPA.')
