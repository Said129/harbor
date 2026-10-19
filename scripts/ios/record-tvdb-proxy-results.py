"""Combine the actual six-model and one-live canonical Xcode result proofs."""
import hashlib
import json
import os
from pathlib import Path

build = Path('ios/build')
folder = build / 'canonical'
plan = json.loads((build / 'preserved-tvdb-proxy.json').read_text())
models = json.loads((folder / 'TVDBProxyModels.json').read_text())
live = json.loads((folder / 'TVDBProxyLive.json').read_text())
source = os.environ['GITHUB_SHA']
assert plan['source'] == models['source'] == live['source'] == source
assert models['selected_actual_case_count'] == 6 and live['selected_actual_case_count'] == 1 and live['result'] == 'passed'
cases = models['actual_passed_cases'] + [live['case']]
assert len(cases) == len(set(cases)) == 7 and set(cases) == set(plan['pending_native_cases'])
trees = []
for record in [models, live]:
    tree = folder / record['raw_tree_file']
    assert hashlib.sha256(tree.read_bytes()).hexdigest() == record['raw_tree_sha256']
    trees.append(dict(file=tree.name, sha256=record['raw_tree_sha256'], bundle=record['bundle']))
proof = dict(source=source, selected_actual_case_count=7, actual_passed_cases=sorted(cases),
             evidence='two-independent-xcresulttool-result-trees', raw_trees=trees,
             schemes=['Harbor', 'HarborLive'], full_desktop_parity_complete=False, ipa_created=False)
(folder / 'TVDBProxy.json').write_text(json.dumps(proof, indent=2) + '\n')
print('Six actual native outcomes and one actual public-service outcome authenticated from their own schemes/result trees.')
