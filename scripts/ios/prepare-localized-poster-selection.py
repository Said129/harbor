"""Validate localized portrait artwork, shared requests and the changed offline preview."""
import json
import os
from pathlib import Path
import re

block = 'localized-posters'
marker = 'affected:' + block
cases = []
for suite, count in [('LocalizedPosterTests', 4), ('SettingsPreviewArtworkTests', 3)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
affected = 'HarborTests.CardArtworkResolverTests/testLocalizedTMDBArtOverridesCuratedAndOwnLogosWhileAnExplicitPinAlwaysWins'
cases.append(affected)
assert len(cases) == len(set(cases)) == 8
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='PosterPreview' + family, family=family,
        seed='HarborTests.PosterAppearanceSeedTests/testPrepareOwnedPosterCatalogWithDesktopDefaultsAndNoPersonalAccount',
        cases=['HarborExistingAppUITests.PosterAppearanceNavigationTests/testDesktopPosterAndTVChoicesRenderFitPersistAndResetOn' + family]))
    captures += [state + '-' + family.lower() for state in ['poster-grid', 'poster-fallback-preview', 'poster-fallback-tv-preview', 'poster-tv-controls', 'poster-quality-controls', 'poster-tv-grid', 'poster-restored', 'poster-reset']]
for batch in batches:
    for case in [batch['seed'], *batch['cases']]:
        target, tail = case.split('.', 1); suite, method = tail.split('/')
        target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
        assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
assert len(captures) == len(set(captures)) == 16
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=8, pending_native_cases=cases, ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']],
    preserve_prepared_app_data=True, fresh_preparation_executions=2, expected_total_executions=12,
    expected_original_images=16, required_original_captures=captures, new_native_cases=7, affected_native_cases=[affected],
    changed_preview_ui_cases=2, owned_local_source_ui_server=True,
    parent_run=40317824549, parent_results_not_assumed=True,
    unchanged_language_anime_bitmap_fitted_and_profile_contracts_not_selected=True,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    actual_personal_account_login_verified=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Localized posters:7NEW+1AFFECTED native,2fresh+2AFFECTED previewUI=12executions/16captures. No IPA.')
