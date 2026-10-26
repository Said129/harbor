"""Run unexecuted cards, new Simkl authorization and the two actually failed source journeys."""
import json
import os
from pathlib import Path
import re

block = 'poster-simkl-completion'
marker = 'affected:' + block
cases = []
for suite, count in [('PosterBehaviorTests', 2), ('PosterBehaviorProfileTests', 1), ('ExpandingCardArtworkTests', 3), ('SimklArtworkTests', 3), ('WideCardArtworkResolverTests', 2), ('PosterBehaviorMountTests', 1), ('SimklClientTests', 4), ('SimklAccountTests', 5)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
affected = 'HarborTests.SettingsPreviewArtworkTests/testLiveSamplesRejectPlaceholdersAdultAndUnratedTitlesCoalesceAndKeepTheVerifiedPoster'
cases.append(affected)
assert len(cases) == len(set(cases)) == 22
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches += [
        dict(id='PosterCompletion' + family, family=family,
            seed='HarborTests.PosterAppearanceSeedTests/testPrepareOwnedPosterCatalogWithDesktopDefaultsAndNoPersonalAccount',
            cases=['HarborExistingAppUITests.PosterAppearanceNavigationTests/testDesktopPosterAndTVChoicesRenderFitPersistAndResetOn' + family]),
        dict(id='SourceCompletion' + family, family=family,
            seed='HarborTests.CustomSourceInterfaceSeedTests/testPrepareAnOwnedCatalogAndPosterFoldersOnAFreshGuestWithoutAnyAccount',
            cases=['HarborExistingAppUITests.CustomSourceNavigationTests/testDesktopFoldersImportOpenExplainRequirementsEditHideRestoreAndDeleteOn' + family]),
        dict(id='SimklCompletion' + family, family=family,
            seed='HarborTests.PosterAppearanceSeedTests/testPrepareOwnedPosterCatalogWithDesktopDefaultsAndNoPersonalAccount',
            cases=['HarborExistingAppUITests.SimklAccountNavigationTests/testPublicDeviceCodeCopyCancelAndReopenWithoutAuthorizingAnyPersonalAccountOn' + family]),
    ]
    captures += [state + '-' + family.lower() for state in ['poster-grid', 'poster-fallback-preview', 'poster-fallback-tv-preview', 'poster-tv-controls', 'poster-quality-controls', 'poster-tv-grid', 'poster-restored', 'poster-reset', 'poster-behavior-controls', 'poster-behavior-restored', 'poster-behavior-reset']]
    captures += ['source-' + state + '-' + family.lower() for state in ['import-dialog', 'fetch-error', 'format-error', 'imported', 'catalog', 'missing-key', 'missing-addon', 'image-editor', 'images-edited', 'hidden', 'restored', 'deleted']]
    captures += ['simkl-' + state + '-' + family.lower() for state in ['disconnected', 'code', 'cancelled-restored']]
captures += ['poster-behavior-native-' + state for state in ['initial', 'focused-wide', 'revealed-last', 'pointer-dock']]
for batch in batches:
    for case in [batch['seed'], *batch['cases']]:
        target, tail = case.split('.', 1); suite, method = tail.split('/')
        target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
        assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
assert len(captures) == len(set(captures)) == 56
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=22, pending_native_cases=cases, ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']],
    preserve_prepared_app_data=True, fresh_preparation_executions=6, expected_total_executions=34,
    expected_original_images=56, required_original_captures=captures,
    unexecuted_native_cases=13, new_simkl_native_cases=9, affected_native_cases=[affected],
    failed_source_ui_cases_retried=2, unexecuted_appearance_ui_cases=2, new_simkl_ui_cases=2,
    owned_local_source_ui_server=True, parent_compiler_run=40362055020, parent_interface_run=40352341225,
    parent_results_not_assumed=True, behavior_reference='ios/HarborTests/Fixtures/poster-behavior-reference.json',
    simkl_reference='ios/HarborTests/Fixtures/simkl-retry-reference.json',
    actual_native_focus_and_decoded_pixels_required=True, public_simkl_device_code_only=True,
    personal_simkl_authorization_not_performed=True, approved_language_ui_replayed=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    actual_personal_account_login_verified=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Cards/Simkl:13unexecuted+9NEW native,6fresh+6pending/new/failedUI=34executions/56captures. No IPA.')
