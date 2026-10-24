"""Verify only the new original Anime row definitions, oracle and direct-ranking adapters."""
import json
import os
from pathlib import Path
import re

marker = 'native-only:HarborTests.DesktopAnimeRowTests/'
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/DesktopAnimeRowTests.swift').read_text('utf-8'))
cases = ['HarborTests.DesktopAnimeRowTests/' + method for method in methods]
assert len(cases) == len(set(cases)) == 3
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker or os.environ['HARBOR_NATIVE_SELECTION'].strip().split(',') == cases
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='anime-desktop-rows', selection_marker=marker,
    selected_case_count=3, pending_native_cases=cases, ui_cases=[], fresh_preparation_executions=0,
    expected_total_executions=3, expected_original_images=0, required_original_captures=[],
    new_native_cases=3, original_catalog_rows=20, added_native_catalog_rows=15,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    interface_review_pending=True, full_anime_parity_complete=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('Anime rows:3new native contracts; original20row plans/gems oracle/direct MAL additions only. Interface review remains pending; no IPA.')
