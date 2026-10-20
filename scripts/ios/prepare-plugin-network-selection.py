"""Select new network behavior, its three affected worker paths and the actual CRLF failure."""
import json
import os
from pathlib import Path
import re

methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/HarborNativeNetworkTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 5
cases = ['HarborTests.HarborNativeNetworkTests/' + method for method in methods]
affected = ['testCancellationRejectsItsLateResultAndLeavesAnotherCallUsable',
    'testHTTPAndGRPCUseTheHostContractAndReferenceConcurrencyLimits',
    'testLateHostResponseCannotPublishAfterAnOwnerOrActivationChange']
for method in affected:
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/HarborTests/HarborPluginRuntimeTests.swift').read_text('utf-8'))
cases += ['HarborTests.HarborPluginRuntimeTests/' + method for method in affected]
cases += ['HarborTests.HarborPluginGRPCTests/testMessagesTrailersStatusAndPercentEncodedErrorsMatchDesktop']
assert len(cases) == len(set(cases)) == 9
rust_cases = []
for module in ['plugin_http', 'plugin_network']:
    source = Path(f'harbor-ios-bridge/src/{module}.rs').read_text('utf-8')
    names = re.findall(r'#\[test\]\s+fn (plugin_\w+)\(', source)
    rust_cases += [module + '::tests::' + name for name in names]
assert len(rust_cases) == len(set(rust_cases)) == 8
live = 'HarborIntegrationTests.HarborNativeNetworkLiveTests/testPinnedPublicRepositoryUsesActualNativeTLSAndHTTP2'
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), selected_case_count=9, pending_native_cases=cases,
    selected_rust_cases=rust_cases, public_case=live, new_native_cases=5, affected_worker_cases=3, failed_crlf_case=1,
    preserved_runs=[39414339731, 39417458336, 39504615361], unrelated_approved_cases_selected=False,
    approved_profile_ui_repeated=False, all_preexisting_rust_tests_repeated=False,
    plugin_room_complete=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-network.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-network-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
(directory / 'plugin-network-live-selection.txt').write_text(live.replace('.', '/', 1) + '\n', 'utf-8')
print('9 native contracts, 8 new Rust contracts and one new native TLS/HTTP2 contract selected. No IPA.')
