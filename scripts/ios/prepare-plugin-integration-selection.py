"""Select unexecuted plugin models and the four changed delivery paths; never replay unrelated suites."""
import json
import os
from pathlib import Path
import re

cases = []
for suite, expected in [('HarborStreamPluginManagerTests', 8), ('HarborPluginSettingsTests', 3),
                         ('HarborPluginFormTests', 3), ('HarborStreamPluginPoolTests', 6)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == expected
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
affected = ['HarborTests.HarborPluginRuntimeTests/' + method for method in [
    'testCancellationRejectsItsLateResultAndLeavesAnotherCallUsable',
    'testHTTPAndGRPCUseTheHostContractAndReferenceConcurrencyLimits',
    'testLateHostResponseCannotPublishAfterAnOwnerOrActivationChange']]
affected += ['HarborTests.HarborNativeNetworkTests/testMaximumRPCResponseCrossesActualWebKitWorkerBridge']
cases += affected
assert len(cases) == len(set(cases)) == 24
seed = 'HarborTests.HarborPluginInterfaceSeedTests/testPrepareOwnedPluginInTheOrdinaryLocalInstallation'
ui = ['HarborUITests.HarborPluginNavigationTests/' + method for method in [
    'testRealPluginSettingsAndRepositoryControlsOnIPhone', 'testRealPluginSettingsAndRepositoryControlsOnIPad']]
for case in cases + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), selected_case_count=24, pending_native_cases=cases,
    unexecuted_new_cases=20, affected_worker_cases=affected, native_preparation_case=seed, ui_cases=ui,
    expected_total_executions=28, expected_original_images=10,
    previous_manager_run=39580297724, previous_manager_actual_executions=0,
    previous_manager_failure='Shell count guard expected 11 for 15 selected identifiers, before xcodebuild test.',
    retained_network_validation_run=39511608179, retained_network_native_cases=10, retained_rust_cases=2,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False, public_network_case_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
print('20 unexecuted new models and 4 affected delivery paths; two fresh UI preparations and two new UI routes. No IPA.')
