"""Select new extras plus one failed fixture and two explicitly affected cases."""
import json
import os
from pathlib import Path
import re

methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/AnimeFranchiseExtraTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 10
new = ['HarborTests.AnimeFranchiseExtraTests/' + method for method in methods]
failed = ['HarborTests.AnimeEpisodePoolTests/testDetailRoutesTheActualSessionResumeSubtitlesAndMetadataToTheSelectedEntry']
affected = ['HarborTests.AnimeEpisodePoolTests/testPairCorrectsStaleTVDBIDAndForeignSeriesDoesNotStealASlot',
    'HarborTests.NativeDataTests/testCloudResumeMatchesTheEpisodeAndRecognizesCompletedMovies']
for case in failed + affected:
    suite, method = case.removeprefix('HarborTests.').split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path(f'ios/HarborTests/{suite}.swift').read_text('utf-8'))
cases = new + failed + affected
assert len(cases) == len(set(cases)) == 13
live = dict(bundle='FranchiseExtrasPublicContract', suite='AnimeFranchiseExtraLiveTests',
    method='testActualKitsuMovieKeepsItsDefaultVideoIdentityAndVerifiedIMDbFallback', new=True)
live['case'] = 'HarborIntegrationTests.' + live['suite'] + '/' + live['method']
assert re.search(r'\bfunc ' + live['method'] + r'\(', Path('ios/HarborIntegrationTests/AnimeFranchiseExtraLiveTests.swift').read_text('utf-8'))
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), selected_case_count=13, pending_native_cases=cases,
    new_native_cases=new, failed_previous_cases=failed, affected_existing_cases=affected, public_contracts=[live],
    affected_case_reasons=['Repair the owned stream fixture with the required addon identity',
        'Verify unmatched sibling retention after the forward projection refinement', 'Shared cloud-resume movie identity branch changed'],
    preserved_run=39329283077, previous_native_passes_retained=23, previous_public_passes_retained=1,
    unrelated_approved_cases_selected=False, full_pool_suite_repeated=False, ui_cases_selected=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-franchise-extras.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'franchise-extras-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
print('Ten new extras cases, the one failed fixture and two affected cases selected; unrelated native/public passes retained. No IPA.')
