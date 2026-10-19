"""Select the new source-aware pool and only behavior whose producer changed."""
import json
import os
from pathlib import Path
import re

methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/AnimeEpisodePoolTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 11
new = ['HarborTests.AnimeEpisodePoolTests/' + method for method in methods]
affected = []
for suite, count in [('EpisodeOrderProjectionTests', 4), ('AnimeEpisodeTests', 4)]:
    names = re.findall(r'\bfunc (test\w+)\(', Path(f'ios/HarborTests/{suite}.swift').read_text('utf-8'))
    names = [name for name in names if not name.startswith('testPrepare')]
    assert len(names) == count
    affected.extend('HarborTests.' + suite + '/' + name for name in names)
affected.extend('HarborTests.' + name for name in [
    'NativeDataTests/testEpisodeAdvanceCrossesSeasonsKeepsSpecialsSeparateAndExcludesUnairedEpisodes',
    'LibraryContinuityTests/testPlayTitleAdvancesPastFinishedEpisodesButKeepsPartialRewatchesAndSpecials',
    'MobileSourcesAndSubtitlesTests/testSubtitlePlansUseVerifiedEpisodeAndSafelyEncodeFileHints',
    'SearchAndSourcesTests/testDanmachiRequestsBothVerifiedIdentitiesWithoutCrossingEpisodes',
    'AnimeFranchiseTests/testFranchiseSelectionKeepsTheActualProviderAndRejectsUnknownOwnerOrWrongMetadata'])
for case in affected:
    suite, method = case.removeprefix('HarborTests.').split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path(f'ios/HarborTests/{suite}.swift').read_text('utf-8'))
cases = new + affected
assert len(cases) == len(set(cases)) == 24
live = dict(bundle='PoolMappingIntegration', suite='ContinuationParityLiveTests',
    method='testActualIMDbAnimeMappingAndEpisodeNinetyNinePresentation', new=False)
live['case'] = 'HarborIntegrationTests.' + live['suite'] + '/' + live['method']
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), pending_native_cases=cases, selected_case_count=24,
    new_native_cases=new, affected_existing_native_cases=affected, public_contracts=[live],
    affected_existing_case_reason='Projection, sequence, mapping identity and stream/subtitle ID producers changed; preserve unrelated passes',
    unrelated_approved_cases_selected=False, full_franchise_graph_suite_repeated=False, ui_cases_selected=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-anime-episode-pool.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'anime-episode-pool-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
print('Eleven new pool cases, thirteen affected native cases and one affected real adapter selected. No unrelated suites or IPA.')
