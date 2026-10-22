"""Retain every original independent UI result, including partial failures."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.parse

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--bundle', type=Path, required=True); p.add_argument('--output', type=Path, required=True); p.add_argument('--cases', required=True)
a = p.parse_args(); expected = set(json.loads(a.cases))
plan = json.loads(Path('ios/build/preserved-plugin-integration.json').read_text('utf-8'))
assert len(expected) in (3, 5) and any(set(group) == expected for group in plan['ui_device_cases'])
raw = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(a.bundle)], capture_output=True, timeout=60, check=True)
tree_file = a.output.with_name(a.output.stem + '-tree.json'); tree_file.write_bytes(raw.stdout)
rows = []
def walk(value, context=()):
    if isinstance(value, list):
        for child in value: walk(child, context)
    elif isinstance(value, dict):
        context += tuple(urllib.parse.unquote(str(value.get(key, ''))) for key in ['name', 'nodeIdentifier', 'testIdentifier', 'testIdentifierURL'])
        if re.sub('[^a-z]', '', str(value.get('nodeType', '')).lower()) == 'testcase':
            label = '\n'.join(context)
            matches = [case for case in expected if case.split('.', 1)[1].split('/')[0] in label and case.split('/')[-1] in label]
            assert len(matches) == 1
            rows.append(dict(case=matches[0], result=str(value.get('result', '')).lower()))
        else:
            for child in value.values():
                if isinstance(child, (dict, list)): walk(child, context)
walk(json.loads(raw.stdout))
assert len(rows) == len({row['case'] for row in rows})
passed = len(rows) == len(expected) and {row['case'] for row in rows} == expected and all(row['result'] == 'passed' for row in rows)
result = dict(source=os.environ['GITHUB_SHA'], bundle=str(a.bundle), raw_tree_sha256=hashlib.sha256(raw.stdout).hexdigest(),
    expected_cases=sorted(expected), actual_cases=rows, status='passed' if passed else 'partial-failure')
a.output.write_text(json.dumps(result, indent=2) + '\n', 'utf-8')
print(json.dumps(result), flush=True)
if not passed: raise SystemExit('Actual independent interface failures retained.')
