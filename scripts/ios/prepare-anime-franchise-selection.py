"""Select new franchise cases and one affected real mapping adapter only."""
import json
import os
from pathlib import Path
import re

methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/AnimeFranchiseTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 9
cases = ['HarborTests.AnimeFranchiseTests/' + method for method in methods]
live = [dict(bundle='FranchisePublicContract', suite='AnimeFranchiseLiveTests', method='testPublicKitsuResourcesAndVerifiedMappingDescribeTheSameAnime', new=True),
        dict(bundle='FranchiseMappingIntegration', suite='ContinuationParityLiveTests', method='testActualIMDbAnimeMappingAndEpisodeNinetyNinePresentation', new=False)]
for row in live:
    text = Path('ios/HarborIntegrationTests', row['suite'] + '.swift').read_text('utf-8')
    assert re.search(r'\bfunc ' + row['method'] + r'\(', text)
    row['case'] = 'HarborIntegrationTests.' + row['suite'] + '/' + row['method']
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), pending_native_cases=cases, selected_case_count=9,
    public_contracts=live, affected_existing_case_reason='AnimeEpisodeService.fetch now shares the verified public mapping response cache',
    unrelated_approved_cases_selected=False, panel_suite_repeated=False, ui_cases_selected=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-anime-franchise.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'anime-franchise-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
print('Selected nine new graph/selection/identity cases, one new public contract and one affected real adapter. No unrelated suite or IPA.')
