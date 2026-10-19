"""Select only the new TVDB proxy contract, identity and live endpoint checks."""
import argparse
import json
import os
from pathlib import Path
import re

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
selected = []
for target, suite, count in [('HarborTests', 'TVDBProxyTests', 6), ('HarborIntegrationTests', 'TVDBProxyLiveTests', 1)]:
    source = (Path('ios') / target / (suite + '.swift')).read_text('utf-8')
    methods = re.findall(r'\bfunc (test\w+)\(', source)
    assert len(methods) == count and len(set(methods)) == count
    selected.extend(target + '.' + suite + '/' + method for method in methods)
assert len(selected) == 7
a.output.parent.mkdir(parents=True, exist_ok=True)
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), pending_native_cases=selected,
    selected_case_count=7, purpose='New metadata transport only; the original Desktop proxy protocol and episode identities are preserved',
    previously_approved_methods_selected=False, credentials_sent=False, ipa_requested=False,
    reference='Desktop 0.9.132', community_source='cd2a0aff335fb9936146b6434098a7e10b14a421',
    replacement='https://harborcommunity.site/api/tvdb/v4', full_desktop_parity_complete=False, split_schemes=True)
a.output.write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
models = [case for case in selected if case.startswith('HarborTests.')]
live = [case for case in selected if case.startswith('HarborIntegrationTests.')]
assert len(models) == 6 and len(live) == 1
a.output.with_name('preserved-tvdb-models.json').write_text(json.dumps(plan | dict(pending_native_cases=models, selected_case_count=6), indent=2) + '\n', 'utf-8')
a.output.with_name('tvdb-proxy-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in models) + '\n', 'utf-8')
a.output.with_name('tvdb-proxy-live-selection.txt').write_text(live[0].replace('.', '/', 1) + '\n', 'utf-8')
print('Selected six new contract/identity cases and one real public endpoint check; no previous approved case or IPA.')
