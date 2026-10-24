"""Retry six failed interfaces without reinstalling their prepared application."""
import json
import os
from pathlib import Path
import re

marker = 'ui-only:prepared-app'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
batches, captures = [], []
metadata = 'EBookMetadataInterfaceSeedTests/testPrepareReadingSourcesAndOriginalPublicBookCacheOnAFreshGuest'
bookmarks = 'ReaderBookmarkInterfaceSeedTests/testPrepareOwnedBookAndTwoBookmarkRoutesInOneFreshGuest'
music = 'MusicExploreInterfaceSeedTests/testPrepareAnUnconfiguredGuestWithOriginalExploreFilters'

def add(label, family, seed, case, names):
    batches.append(dict(id=label + family, family=family, seed='HarborTests.' + seed,
        cases=['HarborExistingAppUITests.' + case + family]))
    captures.extend(name + '-' + family.lower() for name in names)

add('Catalog', 'IPhone', metadata, 'HarborReadingCompletionNavigationTests/testBookCatalogOn',
    ['ebook-catalog-' + state for state in ['grouped', 'detail', 'alternate-reader', 'filters', 'manga-tag']])
add('Metadata', 'IPad', metadata, 'HarborReadingCompletionNavigationTests/testBookMetadataOn',
    ['ebook-metadata-' + state for state in ['discover', 'detail', 'reader', 'search', 'settings', 'cache-cleared']])
add('Focus', 'IPhone', bookmarks, 'EBookReaderChromeNavigationTests/testFocusHidesAndRevealsControlsKeepsPanelsUsableAndRestoresAfterRelaunchOn',
    ['reader-focus-' + state for state in ['initial', 'panel', 'hidden', 'revealed', 'restored', 'disabled']])
for family in ['IPhone', 'IPad']:
    add('Artists', family, music, 'MusicArtistNavigationTests/testPublicGenreArtistsProviderCreditsAndPrivateMetadataSettingsOn',
        ['music-artists-' + state for state in ['credits', 'credit-artist', 'roster', 'roster-detail', 'settings', 'settings-removed']])
add('Billboard', 'IPhone', music, 'MusicBillboardNavigationTests/testPublicRanksAlbumChartLocalSearchCountrySelectionAndReturnToGenresOn',
    ['music-billboard-' + state for state in ['ranks', 'detail', 'albums', 'search', 'country', 'genres']])
ui = [case for batch in batches for case in batch['cases']]
for case in [row['seed'] for row in batches] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    folder = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + folder + '/' + suite + '.swift').read_text('utf-8'))
assert len(set(ui)) == len(batches) == 6 and len(set(captures)) == 35
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='prepared-app', selection_marker=marker,
    selected_case_count=0, pending_native_cases=[], ui_only=True, ui_batches=batches, ui_cases=ui,
    preserve_prepared_app_data=True, fresh_preparation_executions=6, expected_total_executions=12,
    expected_original_images=35, required_original_captures=captures, failed_ui_cases_retried=6,
    retained_reader_native_cases=51, retained_music_artist_native_cases=9, retained_anime_native_cases=8,
    retained_billboard_tablet_ui_run=40134525843, physical_cache_comparison_required=True,
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as file: file.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Six failed UI routes and six fresh preparations only:12 executions/35 captures. Existing approved suites retained. No IPA.')
