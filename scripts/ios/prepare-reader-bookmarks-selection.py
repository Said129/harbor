"""Only new bookmark behavior and its real phone/tablet interfaces; retain prior results."""
import json
import os
from pathlib import Path
import re

marker = 'HarborTests.EBookBookmarkTests/'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
models = [marker + name for name in [
    'testLegacyBookmarksUpgradeOnceAndStableSourceIDsNeverJumpToAReorderedOrRemovedChapter',
    'testActualProfilePersistenceKeepsNewestFirstDeduplicatesCapsAndPreservesBookmarksAcrossPositionWrites']]
seed = 'HarborTests.ReaderBookmarkInterfaceSeedTests/testPrepareOwnedBookAndTwoBookmarkRoutesInOneFreshGuest'
ui = ['HarborUITests.EBookBookmarkNavigationTests/testOriginalBookmarkPanelDeduplicationChapterJumpsRemovalAndRelaunchOn' + device for device in ['IPhone', 'IPad']]
for case in models + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
batches = [dict(id='Bookmarks' + device, family=device, seed=seed, cases=[case]) for device, case in zip(['IPhone', 'IPad'], ui)]
captures = ['reader-bookmarks-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['newest', 'local-jump', 'chapter-jump', 'restored', 'deleted', 'empty']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reader-bookmarks', selected_case_count=2,
    pending_native_cases=models, new_native_cases=2, selection_marker=marker,
    ui_cases=ui, ui_batches=batches, fresh_preparation_executions=2, expected_total_executions=6,
    expected_original_images=12, required_original_captures=captures,
    retained_native_model_cases=28, retained_public_metadata_cases=1, retained_rust_font_cases=5,
    independent_reader_interface_run=39933605950, independent_reader_interface_source='5349c486b31ab7453baa8e3b13fa94f96fae7417',
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in models) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('2 new bookmark contracts+2 fresh preparations+2 new interfaces,12 captures. Preserve28 Native+1 public metadata+5 Rust; no approved cases repeated. No IPA.')
