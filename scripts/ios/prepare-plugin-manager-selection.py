"""Select new manager/settings contracts and the affected asynchronous WebKit delivery paths."""
import json
import os
from pathlib import Path
import re

methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/HarborStreamPluginManagerTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 8
cases = ['HarborTests.HarborStreamPluginManagerTests/' + method for method in methods]
settings_methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/HarborPluginSettingsTests.swift').read_text('utf-8'))
assert len(settings_methods) == len(set(settings_methods)) == 3
cases += ['HarborTests.HarborPluginSettingsTests/' + method for method in settings_methods]
assert len(cases) == len(set(cases)) == 11
affected = ['HarborTests.HarborPluginRuntimeTests/' + method for method in [
    'testCancellationRejectsItsLateResultAndLeavesAnotherCallUsable',
    'testHTTPAndGRPCUseTheHostContractAndReferenceConcurrencyLimits',
    'testLateHostResponseCannotPublishAfterAnOwnerOrActivationChange']]
affected += ['HarborTests.HarborNativeNetworkTests/testMaximumRPCResponseCrossesActualWebKitWorkerBridge']
for case in affected:
    suite, method = case.split('.', 1)[1].split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
cases += affected
assert len(cases) == len(set(cases)) == 15
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), selected_case_count=15, pending_native_cases=cases,
    new_manager_cases=8, new_settings_cases=3,
    affected_async_bridge_cases=affected,
    affected_reason='sendHostResult uses the asynchronous WebKit API to resolve the actual compiler warning at HarborPluginRuntime.swift:266',
    dependency_validation_run=39511608179, dependency_validation_source='e5cb4c979974d73a0ca377364e36fd41fa99fc2e',
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False, approved_profile_ui_repeated=False,
    plugin_room_complete=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory/'preserved-plugin-manager.json').write_text(json.dumps(plan, indent=2)+'\n', 'utf-8')
(directory/'plugin-manager-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases)+'\n', 'utf-8')
print('11 new manager/settings contracts and 4 affected asynchronous WebKit paths selected. Other approved contracts retained. No IPA.')
