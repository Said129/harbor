"""Select only new season-artwork behavior; retain unrelated actual outcomes."""
import json
import os
from pathlib import Path
import re

path = Path('ios/HarborTests/AnimeSeasonArtworkTests.swift')
methods = re.findall(r'\bfunc (test\w+)\(', path.read_text('utf-8'))
assert len(methods) == len(set(methods)) == 8
cases = ['HarborTests.AnimeSeasonArtworkTests/' + method for method in methods]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), selected_case_count=8, pending_native_cases=cases,
    new_native_cases=cases, unrelated_approved_cases_selected=False, public_contracts_repeated=False,
    ui_cases_selected=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-season-artwork.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'season-artwork-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
print('Eight new season-artwork cases selected; unrelated native/public passes retained. No IPA.')
