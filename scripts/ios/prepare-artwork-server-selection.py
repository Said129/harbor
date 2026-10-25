"""Exercise only the newly corrected public index and account artwork routing."""
import json
import os
from pathlib import Path
import re

marker = 'native-only:artwork-server'
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/HarborArtworkServerTests.swift').read_text('utf-8'))
cases = ['HarborTests.HarborArtworkServerTests/' + method for method in methods]
assert len(cases) == len(set(cases)) == 8
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='artwork-server', selection_marker=marker,
    selected_case_count=8, pending_native_cases=cases, ui_cases=[], fresh_preparation_executions=0,
    expected_total_executions=8, expected_original_images=0, required_original_captures=[], new_native_cases=8,
    identity_server_validation_run=40162327075, household_activation_validation_run=40161132799,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    public_availability_probed_anonymously=True, actual_custom_account_avatar_download_verified=False,
    full_roster_layout_hydration_implemented=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('Artwork server:8new index/appearance/origin persistence cases only; no UI replay, unrelated native tests or IPA.')
