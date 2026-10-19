"""Select only the new Desktop episode-order engine cases; never package an IPA."""
import json
import os
from pathlib import Path
import re

source = Path('ios/HarborTests/TVDBEpisodeOrderTests.swift').read_text('utf-8')
methods = re.findall(r'\bfunc (test\w+)\(', source)
assert len(methods) == len(set(methods)) == 9
cases = ['HarborTests.TVDBEpisodeOrderTests/' + method for method in methods]
directory = Path('ios/build')
directory.mkdir(parents=True, exist_ok=True)
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), pending_native_cases=cases,
            selected_case_count=9, previously_approved_methods_selected=False,
            reference='Desktop 0.9.132 / 0834340cec5531650bfe78cd628628702e636987',
            purpose='Six TVDB order modes, canonical identity, translations, discovery and pagination',
            provider_responses='owned-synthetic-fixtures', actual_public_network_verified=False,
            full_desktop_parity_complete=False, ui_parity_verified=False, ipa_requested=False)
(directory / 'preserved-episode-order.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'episode-order-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
print('Selected nine new episode-order engine cases; no approved old cases, UI claims or IPA.')
