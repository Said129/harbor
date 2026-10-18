"""Record the actual selected live case from Xcode's structured result bundle."""
# Xcode 16 interfaces: https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes
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
p.add_argument('--output', type=Path, required=True)
p.add_argument('--target', required=True)
p.add_argument('--suite', required=True)
p.add_argument('--method', required=True)
a = p.parse_args()
a.output.parent.mkdir(parents=True, exist_ok=True)
raw = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(a.bundle)], capture_output=True, timeout=60)
tree_file = a.output.with_name(a.output.stem + '-tree.json')
tree_file.write_bytes(raw.stdout)
if raw.stderr: a.output.with_name(a.output.stem + '-stderr.txt').write_bytes(raw.stderr)
assert raw.returncode == 0, 'The live result bundle must be readable before its case is accepted'
tree = json.loads(raw.stdout)
cases = []
def walk(value, context=()):
    if isinstance(value, list):
        for child in value: walk(child, context)
    elif isinstance(value, dict):
        identifiers = [urllib.parse.unquote(str(value.get(key, ''))) for key in ['name', 'nodeIdentifier', 'testIdentifier', 'testIdentifierURL']]
        next_context = context + tuple(identifiers)
        if re.sub('[^a-z]', '', str(value.get('nodeType', '')).lower()) == 'testcase':
            cases.append((value, next_context))
        else:
            for child in value.values():
                if isinstance(child, (dict, list)): walk(child, next_context)
walk(tree)
assert len(cases) == 1, 'Exactly the one selected live case must have actually run'
node, context = cases[0]
identity = '\n'.join(context)
assert a.suite in identity and a.method in identity, 'The result must identify the selected suite and method'
assert str(node.get('result', '')).lower() == 'passed', 'The live case must have passed in the result bundle'
case = a.target + '.' + a.suite + '/' + a.method
result = dict(case=case, result='passed', source=os.environ.get('GITHUB_SHA'), evidence='xcresulttool-test-results-tests',
              raw_tree_file=tree_file.name, raw_tree_sha256=hashlib.sha256(raw.stdout).hexdigest(),
              bundle=str(a.bundle), selected_actual_case_count=1)
a.output.write_text(json.dumps(result, indent=2) + '\n', 'utf-8')
print('HARBOR_CANONICAL_TEST_RESULT ' + json.dumps(result), flush=True)
