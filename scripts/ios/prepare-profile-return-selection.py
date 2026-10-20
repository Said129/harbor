"""Select two new lifecycle cases and only the failed phone return journey."""
import json
import os
from pathlib import Path
import re

suite = 'HarborTests.ProfileForegroundCycleTests/'
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/ProfileForegroundCycleTests.swift').read_text('utf-8'))
setup = 'testPrepareOrdinaryExpiredDefaultProfileForTheFailedPhoneReturnJourney'
assert len(methods) == 3 and setup in methods
cases = [suite + method for method in methods if method != setup]
ui = 'HarborUITests.ProfileStartupNavigationTests/testExpiredReturnPromptAndRecentSelectionOnIPhone'
assert 'func ' + ui.split('/')[-1] + '(' in Path('ios/HarborUITests/ProfileStartupNavigationTests.swift').read_text('utf-8')
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), selected_case_count=2, pending_native_cases=cases,
    setup_case=suite + setup, ui_case=ui, previous_failed_run=39237920401, previous_passes_retained=True,
    unrelated_approved_cases_selected=False, approved_profile_creation_ui_repeated=False, expected_original_images=3,
    full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-profile-return.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'profile-return-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
print('Two new lifecycle cases plus one necessary new setup and the failed phone UI journey. Approved journeys retained. No IPA.')
