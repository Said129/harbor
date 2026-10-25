"""Validate the newly fixed late episode-order caption without repeating prior passes."""
import json
import os
from pathlib import Path
import re

marker = 'native-only:player-order-caption'
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/PlayerEpisodePresentationTests.swift').read_text('utf-8'))
cases = ['HarborTests.PlayerEpisodePresentationTests/' + method for method in methods]
assert len(cases) == len(set(cases)) == 3
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='player-order-caption', selection_marker=marker,
    selected_case_count=3, pending_native_cases=cases, ui_cases=[], fresh_preparation_executions=0,
    expected_total_executions=3, expected_original_images=0, required_original_captures=[], new_native_cases=3,
    retained_page_layout_native_run=40142488560, retained_page_layout_native_cases=20,
    retained_layout_batch_native_run=40156238216, retained_layout_batch_native_cases=6,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    interface_review_pending=True, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('Player order caption:3new stale-session/source-identity cases only. Old episode/order passes retained. No UI replay or IPA.')
