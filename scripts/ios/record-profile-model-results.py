"""Authenticate the selected model outcomes from the actual Xcode result tree."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.parse

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--bundle', type=Path, required=True)
p.add_argument('--expected', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--count', type=int, choices=[6, 7, 11, 25], default=25)
a = p.parse_args()
expected = set(json.loads(a.expected.read_text())['pending_native_cases']); assert len(expected) == a.count
raw = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(a.bundle)], capture_output=True, timeout=60, check=True)
a.output.parent.mkdir(parents=True, exist_ok=True)
tree_file = a.output.with_name(a.output.stem + '-tree.json'); tree_file.write_bytes(raw.stdout)
cases = []
def walk(value, context=()):
    if isinstance(value, list):
        for child in value: walk(child, context)
    elif isinstance(value, dict):
        labels = tuple(urllib.parse.unquote(str(value.get(key, ''))) for key in ['name', 'nodeIdentifier', 'testIdentifier', 'testIdentifierURL'])
        context = context + labels
        if re.sub('[^a-z]', '', str(value.get('nodeType', '')).lower()) == 'testcase': cases.append((value, '\n'.join(context)))
        else:
            for child in value.values():
                if isinstance(child, (dict, list)): walk(child, context)
walk(json.loads(raw.stdout))
assert len(cases) == a.count
actual = []
for node, context in cases:
    matches = [case for case in expected if case.split('.', 1)[1].split('/')[0] in context and case.split('/')[-1] in context]
    assert len(matches) == 1 and str(node.get('result', '')).lower() == 'passed'
    actual.append(matches[0])
assert len(set(actual)) == a.count and set(actual) == expected
proof = dict(source=os.environ['GITHUB_SHA'], evidence='xcresulttool-test-results-tests', selected_actual_case_count=a.count,
    actual_passed_cases=sorted(actual), raw_tree_file=tree_file.name, raw_tree_sha256=hashlib.sha256(raw.stdout).hexdigest(), bundle=str(a.bundle))
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('HARBOR_PROFILE_MODEL_RESULTS ' + json.dumps(proof), flush=True)
