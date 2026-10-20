"""Select only the eight new manifest and local installation contracts."""
import json
import os
from pathlib import Path
import re

methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/HarborPluginCatalogTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 8
cases = ['HarborTests.HarborPluginCatalogTests/' + method for method in methods]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), selected_case_count=8, pending_native_cases=cases,
    unrelated_approved_cases_selected=False, public_provider_execution=False, installed_plugin_manager_complete=False,
    plugin_room_complete=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-catalog.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-catalog-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
print('Eight new catalog contracts selected; no public provider or Plugins room completion claim.')
