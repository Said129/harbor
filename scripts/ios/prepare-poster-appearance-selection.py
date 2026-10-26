"""Validate new appearance behavior and actual failed source UI; retain approved source logic."""
import json
import os
from pathlib import Path
import re

block = 'poster-appearance'
marker = 'affected:' + block
cases = []
for suite, count in [('PosterCardConfigurationTests', 3), ('ArtworkBitmapTests', 2)]:
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8')
    methods = re.findall(r'\bfunc (test\w+)\(', source)
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
assert len(cases) == len(set(cases)) == 5
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    sources = 'HarborExistingAppUITests.CustomSourceNavigationTests/testDesktopFoldersImportOpenExplainRequirementsEditHideRestoreAndDeleteOn' + family
    appearance = 'HarborExistingAppUITests.PosterAppearanceNavigationTests/testDesktopPosterAndTVChoicesRenderFitPersistAndResetOn' + family
    batches += [dict(id='SourceRepair' + family, family=family,
        seed='HarborTests.CustomSourceInterfaceSeedTests/testPrepareAnOwnedCatalogAndPosterFoldersOnAFreshGuestWithoutAnyAccount', cases=[sources]),
        dict(id='PosterAppearance' + family, family=family,
        seed='HarborTests.PosterAppearanceSeedTests/testPrepareOwnedPosterCatalogWithDesktopDefaultsAndNoPersonalAccount', cases=[appearance])]
    captures += ['source-' + state + '-' + family.lower() for state in ['import-dialog', 'fetch-error', 'format-error', 'imported', 'catalog', 'missing-key', 'missing-addon', 'image-editor', 'images-edited', 'hidden', 'restored', 'deleted']]
    captures += [state + '-' + family.lower() for state in ['poster-grid', 'poster-tv-controls', 'poster-quality-controls', 'poster-tv-grid', 'poster-restored', 'poster-reset']]
for batch in batches:
    for case in [batch['seed'], *batch['cases']]:
        target, tail = case.split('.', 1); suite, method = tail.split('/')
        target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
        assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
assert len(captures) == len(set(captures)) == 36
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=5, pending_native_cases=cases, ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']],
    preserve_prepared_app_data=True, fresh_preparation_executions=4, expected_total_executions=13,
    expected_original_images=36, required_original_captures=captures, new_native_cases=5,
    retained_parent_run=40244262302, retained_parent_source='de4993f9606d42975a0de4b446e5279f82f7bf30',
    retained_parent_native_passes=6, previous_parent_ui_failed=True, owned_local_source_ui_server=True,
    source_native_logic_unchanged_since_approved=True, approved_gif_and_public_trakt_not_replayed=True,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    actual_personal_account_login_verified=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Appearance:5NEW native+4fresh+2failed sourceUI+2NEW appearanceUI=13executions/36captures. Approved source logic retained. No IPA.')
