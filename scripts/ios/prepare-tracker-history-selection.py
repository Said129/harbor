"""New shared episode resolution and three actually affected reporter paths only."""
import json
import os
from pathlib import Path
import re

block = 'tracker-history'
marker = 'native-only:' + block
cases = []
for suite, count in [('TrackerEpisodeResolverTests', 5), ('SimklHistoryConfirmationTests', 3)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
affected = [
    'HarborTests.SimklPendingWatchTests/testReporterKeepsTheIntentUntilBothTerminalStopAndHistorySucceed',
    'HarborTests.SimklPendingWatchTests/testTerminalReportsKeepCrossSessionOrderAndRetiredProfilesCannotSendTheirQueuedHistory',
    'HarborTests.SimklPlaybackMountTests/testMountedProductionModifierWaitsForResumeThenReportsActualStateChangesAndTheFinalHistoryOnUnmount',
]
cases += affected
for case in cases:
    suite, method = case.split('.', 1)[1].split('/')
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))) == 1
assert len(cases) == len(set(cases)) == 11
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=11, pending_native_cases=cases, ui_cases=[], fresh_preparation_executions=0,
    expected_total_executions=11, expected_original_images=0, required_original_captures=[],
    new_native_cases=8, affected_reporter_cases=affected, affected_parent_run=40414484295,
    original_reference='ios/HarborTests/Fixtures/tracker-episode-reference.json',
    forced_cinemeta_identity=True, public_anonymous_catalog_only=True,
    personal_account_requests_performed=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=false\n')
print('Eight new resolver/history cases and three affected reporter paths: 11 native executions, no UI replay or IPA.')
