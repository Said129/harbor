"""Select the first execution of new startup and anime grouping model cases."""
import argparse
import json
import os
from pathlib import Path
import re

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
selected = []
for suite, count in [('ProfileLaunchTests', 8), ('AnimeEpisodeGroupingTests', 3)]:
    source = (Path('ios/HarborTests') / (suite + '.swift')).read_text('utf-8')
    methods = re.findall(r'\bfunc (test\w+)\(', source)
    methods = [method for method in methods if not method.startswith('testPrepare')]
    assert len(methods) == count and len(set(methods)) == count
    selected.extend('HarborTests.' + suite + '/' + method for method in methods)
assert len(selected) == 11
a.output.parent.mkdir(parents=True, exist_ok=True)
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), pending_native_cases=selected,
    selected_case_count=11, purpose='First execution of new model behavior only; no UI or full Desktop parity approval',
    previously_approved_methods_selected=False, ui_validation_pending=True, ipa_requested=False,
    retained_evidence_note='Previously approved unchanged methods are not selected. The separate frozen profile UI run retains its own source and evidence.')
a.output.write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
a.output.with_name('startup-anime-selection.txt').write_text('\n'.join(case.replace('HarborTests.', 'HarborTests/') for case in selected) + '\n', 'utf-8')
print('Selected eleven new model cases; the startup clock/UI fixtures and previous approved cases are excluded.')
