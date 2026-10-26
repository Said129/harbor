"""Exercise only new artwork contracts and image-language routes, independently of appearance UI."""
import json
import os
from pathlib import Path
import re

block = 'card-artwork'
marker = 'affected:' + block
cases = []
for suite, count in [('CardArtworkPolicyTests', 2), ('CardArtworkResolverTests', 3), ('TitleArtworkPreferencesTests', 1), ('CardArtworkPublicTests', 1), ('FittedArtworkTests', 1)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
assert len(cases) == len(set(cases)) == 8
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    method = 'testPinnedArtworkAndOriginalImageLanguageChipsReorderRemoveAndPersistOn' + family
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/HarborUITests/CardArtworkNavigationTests.swift').read_text('utf-8'))) == 1
    batches.append(dict(id='CardArtwork' + family, family=family,
        seed='HarborTests.CardArtworkInterfaceSeedTests/testPrepareOwnedPinnedArtworkAndImageLanguagesOnAFreshGuest',
        cases=['HarborExistingAppUITests.CardArtworkNavigationTests/' + method]))
    batches.append(dict(id='SourceRepair' + family, family=family,
        seed='HarborTests.CustomSourceInterfaceSeedTests/testPrepareAnOwnedCatalogAndPosterFoldersOnAFreshGuestWithoutAnyAccount',
        cases=['HarborExistingAppUITests.CustomSourceNavigationTests/testDesktopFoldersImportOpenExplainRequirementsEditHideRestoreAndDeleteOn' + family]))
    batches.append(dict(id='PosterAppearance' + family, family=family,
        seed='HarborTests.PosterAppearanceSeedTests/testPrepareOwnedPosterCatalogWithDesktopDefaultsAndNoPersonalAccount',
        cases=['HarborExistingAppUITests.PosterAppearanceNavigationTests/testDesktopPosterAndTVChoicesRenderFitPersistAndResetOn' + family]))
    captures += [state + '-' + family.lower() for state in ['card-artwork-pinned-catalog', 'card-image-languages', 'card-image-order', 'card-image-restored']]
    captures += ['source-' + state + '-' + family.lower() for state in ['import-dialog', 'fetch-error', 'format-error', 'imported', 'catalog', 'missing-key', 'missing-addon', 'image-editor', 'images-edited', 'hidden', 'restored', 'deleted']]
    captures += [state + '-' + family.lower() for state in ['poster-grid', 'poster-tv-controls', 'poster-quality-controls', 'poster-tv-grid', 'poster-restored', 'poster-reset']]
assert len(captures) == len(set(captures)) == 44
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=8, pending_native_cases=cases, ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']],
    preserve_prepared_app_data=True, fresh_preparation_executions=6, expected_total_executions=20,
    expected_original_images=44, required_original_captures=captures, new_native_cases=8,
    retained_source_native_run=40244262302, retained_source_native_passes=6,
    retained_appearance_run=40308939041, retained_appearance_native_passes=5, failed_parent_ui_cases=3,
    affected_parent_ui_cases=1, previous_phone_ui_replayed_because_caption_alignment_changed=True,
    owned_local_source_ui_server=True, public_artwork_case_is_new=True, gallery_pin_button_ui_verified=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    actual_personal_account_login_verified=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Card artwork:8NEW native+6fresh+2NEW/3FAILED/1AFFECTED UI=20executions/44captures. Retain5appearance and6source native passes. No IPA.')
