"""New tracker readback, real source control routes and affected resume paths only."""
import json
import os
from pathlib import Path
import re

block = 'simkl-playback-import'
marker = 'affected:' + block
cases = []
for suite, count in [('SimklPlaybackImportTests', 7), ('SimklPlaybackImportMountTests', 1)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
affected = [
    'HarborTests.ResumeStoreTests/testRestartRoundTripEpisodeIsolationAndLateCheckpoint',
    'HarborTests.ResumeStoreTests/testCloudOrderingAndProductionAccountIsolation',
    'HarborTests.ResumeRestartTests/testExplicitRestartSurvivesRelaunchAndOlderLegacyCloudAndLateCheckpoints',
    'HarborTests.LibraryContinuityTests/testEarlierViewsDoNotHideTheCurrentSeriesEpisodeOrMovieRewatch',
    'HarborTests.LibraryContinuityTests/testMovieCreditsAreExcludedWhileSeriesKeepTheirCurrentEpisodeLikeDesktop',
    'HarborTests.LibraryContinuityTests/testAnimeVideoCoordinatesAndNumericCloudDatesAreAcceptedWithoutCrossingEpisodes',
]
cases += affected
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='SimklPlaybackSources' + family, family=family,
        seed='HarborTests.SimklPlaybackImportInterfaceSeedTests/testPrepareSourceControlsOnAnOwnedGuestWithoutTrackerCredentials',
        cases=['HarborExistingAppUITests.SimklPlaybackSourcesNavigationTests/testActualSourceTapPersistsAfterRelaunchAndCanBeDisabledOn' + family]))
    captures += ['simkl-playback-source-' + state + '-' + family.lower() for state in ['off', 'enabled', 'restored']]
captures += ['simkl-playback-native-card-' + size for size in ['compact', 'regular']]
for case in cases + [case for batch in batches for case in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
assert len(cases) == len(set(cases)) == 14 and len(captures) == len(set(captures)) == 8
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=14, pending_native_cases=cases, ui_batches=batches,
    ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=2, expected_total_executions=18,
    expected_original_images=8, required_original_captures=captures,
    new_native_cases=8, affected_resume_cases=affected, new_source_ui_cases=2,
    original_reference='ios/HarborTests/Fixtures/simkl-playback-import-reference.json',
    original_oracle_cases=26, personal_simkl_requests_performed=False,
    owned_local_source_ui_server=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, new_rust_tests=1, retained_core_tests=1, parent_rust_compiler_run=40443774165,
    full_desktop_parity_complete=False, physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('8 new native +6 affected resume +2 fresh guests +2 real source UI=18 executions/8captures; failed Rust bridge only, core PASS retained. No IPA.')
