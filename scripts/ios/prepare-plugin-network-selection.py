"""Select new network behavior, its three affected worker paths and the actual CRLF failure."""
import json
import hashlib
import os
from pathlib import Path
import re

methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/HarborNativeNetworkTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 5
cases = ['HarborTests.HarborNativeNetworkTests/' + method for method in methods]
repository_methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/HarborPluginRepositoryClientTests.swift').read_text('utf-8'))
assert len(repository_methods) == len(set(repository_methods)) == 4
cases += ['HarborTests.HarborPluginRepositoryClientTests/' + method for method in repository_methods]
affected = ['testCancellationRejectsItsLateResultAndLeavesAnotherCallUsable',
    'testHTTPAndGRPCUseTheHostContractAndReferenceConcurrencyLimits',
    'testLateHostResponseCannotPublishAfterAnOwnerOrActivationChange']
for method in affected:
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/HarborTests/HarborPluginRuntimeTests.swift').read_text('utf-8'))
cases += ['HarborTests.HarborPluginRuntimeTests/' + method for method in affected]
cases += ['HarborTests.HarborPluginGRPCTests/testMessagesTrailersStatusAndPercentEncodedErrorsMatchDesktop']
assert len(cases) == len(set(cases)) == 13
previous_source = '78e6adef5168e14fb12005f13790430f2bcd4542'
http_source = Path('harbor-ios-bridge/src/plugin_http.rs').read_bytes()
previous_http_sha256 = 'b3ae8d6e4c69325ba37dcab0d1597d7f1fe3c594b3aba318cb19b9d19c977a56'
assert hashlib.sha256(http_source.replace(b'\r\n', b'\n')).hexdigest() == previous_http_sha256
rust_cases = []
for module in ['plugin_network']:
    source = Path(f'harbor-ios-bridge/src/{module}.rs').read_text('utf-8')
    names = re.findall(r'#\[test\]\s+fn (plugin_\w+)\(', source)
    rust_cases += [module + '::tests::' + name for name in names]
assert len(rust_cases) == len(set(rust_cases)) == 2
live = 'HarborIntegrationTests.HarborNativeNetworkLiveTests/testPinnedPublicRepositoryUsesActualNativeTLSAndHTTP2'
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), selected_case_count=13, pending_native_cases=cases,
    selected_rust_cases=rust_cases, public_case=live, new_native_cases=5, affected_worker_cases=3, failed_crlf_case=1,
    preserved_runs=[39414339731, 39417458336, 39504615361, 39510296663], unrelated_approved_cases_selected=False,
    retained_http_cases=6, retained_rust_source=previous_source, new_repository_cases=4,
    retained_http_source_sha256=previous_http_sha256,
    approved_profile_ui_repeated=False, all_preexisting_rust_tests_repeated=False,
    plugin_room_complete=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-network.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-network-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
(directory / 'plugin-network-live-selection.txt').write_text(live.replace('.', '/', 1) + '\n', 'utf-8')
print('13 pending/new native contracts, 2 affected Rust contracts and one native TLS/HTTP2 contract selected; 6 approved HTTP cases retained. No IPA.')
