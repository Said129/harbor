"""Only new original translation contracts and fresh phone/tablet reading/settings routes."""
import json
import os
from pathlib import Path
import re

marker = 'HarborTests.EBookTranslationTests/'
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
models = [marker + name for name in [
    'testActualJavaScriptCoreMatchesOriginalRequestsSevenStreamCasesAndFourCacheIdentities',
    'testNativeRequestCoalescesAndDurableProfileCacheSurvivesReopeningBeforeAutomaticOrKeyChecks',
    'testCancellationAndTruncatedResponsesNeverPublishOrCachePartialChapterText',
    'testTranslatedBlocksKeepIllustrationsSourceAnchorsAndEveryReturnedParagraph',
    'testKeychainSettingsStayWithinTheirProfileAndInvalidHeaderCannotOverwriteSavedConfiguration']]
seed = 'HarborTests.ReaderTranslationInterfaceSeedTests/testPrepareOwnedCachedTranslationsWithoutAnAPIKeyInOneFreshGuest'
ui = ['HarborUITests.EBookTranslationNavigationTests/testCachedChapterOriginalToggleAndProfileTranslationSettingsOn' + device for device in ['IPhone', 'IPad']]
for case in models + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
batches = [dict(id='Translation' + device, family=device, seed=seed, cases=[case]) for device, case in zip(['IPhone', 'IPad'], ui)]
captures = ['reader-translation-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['cached', 'original', 'settings', 'choices', 'saved', 'restored']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='reader-translation', selected_case_count=5,
    pending_native_cases=models, new_native_cases=5, selection_marker=marker,
    ui_cases=ui, ui_batches=batches, fresh_preparation_executions=2, expected_total_executions=9,
    expected_original_images=12, required_original_captures=captures,
    retained_native_model_cases=30, retained_public_metadata_cases=1, retained_rust_font_cases=5,
    independent_reader_interface_run=39933605950, independent_bookmark_ui_run=39935330648,
    retained_bookmark_native_run=39935330648, retained_bookmark_native_cases=2,
    retained_bookmark_original_archive_sha256='7804060edbda10dcce98c35771444b8bbe829d3175f0dc75f85c2ddc20b5a2c0',
    live_paid_translation_requested=False, fixture_uses_no_api_key=True,
    approved_predecessor_cases_repeated=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in models) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('5 NEW translation contracts+2 fresh keyless guests+2 NEW interfaces,12 captures. Keep30 Native+1 public+5 Rust; original live reader/bookmark UI runs stay independent. No paid request. No IPA.')
