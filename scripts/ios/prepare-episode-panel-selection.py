"""Validate new projection behavior and only approved cases whose producer changed."""
import json
import os
from pathlib import Path
import re

methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/EpisodeOrderProjectionTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 4
new = ['HarborTests.EpisodeOrderProjectionTests/' + method for method in methods]
new.append('HarborTests.ProfileSettingsTests/testEpisodeOrderAndRichPanelRemainIndependentAcrossProfilesAndRestart')
affected = [
    'HarborTests.TVDBEpisodeOrderTests/testDVDAlternateAndRegionalKeepCanonicalCoordinatesAndFirstOrderedID',
    'HarborTests.NativeDataTests/testEpisodeAdvanceCrossesSeasonsKeepsSpecialsSeparateAndExcludesUnairedEpisodes',
    'HarborTests.LibraryContinuityTests/testPlayTitleAdvancesPastFinishedEpisodesButKeepsPartialRewatchesAndSpecials',
    'HarborTests.AnimeEpisodeGroupingTests/testBothPresentationsRetainProviderSeasonsArtworkAndTheSamePlaybackIdentity',
    'HarborTests.AnimeEpisodeTests/testPresentationKeepsOriginalStreamsResumeWatchedAndNextEpisode',
]
for case in affected:
    suite, method = case.split('.', 1)[1].split('/')
    assert re.search(r'\bfunc ' + re.escape(method) + r'\(', Path('ios/HarborTests', suite + '.swift').read_text('utf-8'))
cases = new + affected
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), pending_native_cases=cases, selected_case_count=10,
    new_projection_and_profile_cases=new, affected_existing_cases=affected,
    affected_reason='EpisodeSequence now accepts a separate navigation projection; TVDB special slots retain their real canonical source identity',
    unrelated_approved_cases_selected=False, unchanged_engine_suite_repeated=False,
    ui_cases=['HarborUITests.EpisodeOrderNavigationTests/testPublicSuperOrderPanelChangesActualEpisodesOnIPhone',
              'HarborUITests.EpisodeOrderNavigationTests/testPublicSuperOrderPanelChangesActualEpisodesOnIPad'],
    expected_original_images=8, expected_original_videos=2, production_test_mode_added=False,
    ipa_requested=False, full_desktop_parity_complete=False)
(build / 'preserved-episode-panel.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'episode-panel-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
print('Selected five new projection/profile cases, five affected cases and two new public panel interfaces. No unrelated suite or IPA.')
