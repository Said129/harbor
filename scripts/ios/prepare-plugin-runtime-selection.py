"""Select only seven new native worker/bridge contracts, without installed-provider claims."""
import json
import os
from pathlib import Path
import re

methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/HarborPluginRuntimeTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 7
cases = ['HarborTests.HarborPluginRuntimeTests/' + method for method in methods]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), selected_case_count=7, pending_native_cases=cases,
    unrelated_approved_cases_selected=False, public_provider_execution=False, installed_plugin_manager_complete=False,
    plugin_room_complete=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-runtime.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-runtime-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
print('Seven new native runtime contracts selected. No public provider, Plugins room completion or IPA claim.')
