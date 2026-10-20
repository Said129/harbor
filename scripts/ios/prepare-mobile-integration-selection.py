"""Combine only unexecuted new/affected scopes after the shared compiler repair."""
import json
import os
from pathlib import Path
import subprocess
import sys

directory = Path('ios/build')
scopes = ['franchise-extras', 'season-artwork', 'profile-return']
plans = []
for scope in scopes:
    subprocess.run([sys.executable, 'scripts/ios/prepare-' + scope + '-selection.py'], check=True)
    plans.append(json.loads((directory / ('preserved-' + scope + '.json')).read_text('utf-8')))
cases = [case for plan in plans for case in plan['pending_native_cases']]
assert len(cases) == len(set(cases)) == 23
assert not any(plan['unrelated_approved_cases_selected'] or plan['ipa_requested'] for plan in plans)
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), selected_case_count=23, pending_native_cases=cases,
    public_case=plans[0]['public_contracts'][0]['case'], setup_case=plans[2]['setup_case'], ui_case=plans[2]['ui_case'],
    combined_unexecuted_scopes=scopes, compile_failure_run=39406575431, cancelled_before_tests=[39408467770, 39409591059, 39410867608],
    unrelated_approved_cases_selected=False, approved_profile_creation_ui_repeated=False, expected_original_images=3,
    full_desktop_parity_complete=False, ipa_requested=False)
(directory / 'preserved-mobile-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'mobile-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
print('23 pending native cases, one new public contract and the necessary seed/failed phone journey planned together. Approved unrelated results retained; no IPA.')
