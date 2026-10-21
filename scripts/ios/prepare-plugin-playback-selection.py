"""Select only the newly implemented plugin playback block; no predecessor outcomes are assumed."""
import json
import os
from pathlib import Path
import re

cases = []
for suite, count in [('HarborPluginStreamAdapterTests', 3), ('HarborPluginStreamRequestTests', 3), ('HarborPluginStreamSourceTests', 4)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
assert len(cases) == len(set(cases)) == 10
seed = 'HarborTests.HarborPluginInterfaceSeedTests/testPrepareOwnedPluginInTheOrdinaryLocalInstallation'
ui = ['HarborUITests.HarborPluginNavigationTests/testNewPluginPlaybackOptionsPersistOn' + device for device in ['IPhone', 'IPad']]
for case in cases + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='plugin-playback', selected_case_count=len(cases),
    pending_native_cases=cases, new_native_cases=10, native_preparation_case=seed, ui_cases=ui,
    expected_total_executions=14, expected_original_images=4,
    required_original_captures=['plugin-options-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['paused', 'restored']],
    predecessor_run=39587372660, predecessor_source='cfe4160368baf1c33299aec06ddf8ec365f6e38b',
    predecessor_results_assumed=False, predecessor_tests_repeated=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, public_network_case_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
print('10 new playback models, 2 fresh device preparations and 2 new option routes. Previous-run outcomes remain independent. No IPA.')
