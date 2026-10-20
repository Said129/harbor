"""Select only the eight new stream-manager contracts, without a new IPA."""
import json
import os
from pathlib import Path
import re

methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/HarborStreamPluginManagerTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 8
cases = ['HarborTests.HarborStreamPluginManagerTests/' + method for method in methods]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), selected_case_count=8, pending_native_cases=cases,
    dependency_validation_run=39511608179, dependency_validation_source='e5cb4c979974d73a0ca377364e36fd41fa99fc2e',
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False, approved_profile_ui_repeated=False,
    plugin_room_complete=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory/'preserved-plugin-manager.json').write_text(json.dumps(plan, indent=2)+'\n', 'utf-8')
(directory/'plugin-manager-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases)+'\n', 'utf-8')
print('Eight new manager contracts selected. Prior contracts are not repeated. No IPA.')
