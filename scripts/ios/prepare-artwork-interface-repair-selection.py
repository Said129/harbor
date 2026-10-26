"""Retry three failed artwork routes and the tablet source route affected by sibling controls."""
import json
import os
from pathlib import Path
import re

block = 'artwork-interface-repair'
marker = 'ui-only:' + block
assert os.environ['HARBOR_NATIVE_SELECTION'].strip() == marker
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='CardArtwork' + family, family=family,
        seed='HarborTests.CardArtworkInterfaceSeedTests/testPrepareOwnedPinnedArtworkAndImageLanguagesOnAFreshGuest',
        cases=['HarborExistingAppUITests.CardArtworkNavigationTests/testPinnedArtworkAndOriginalImageLanguageChipsReorderRemoveAndPersistOn' + family]))
    batches.append(dict(id='SourceRepair' + family, family=family,
        seed='HarborTests.CustomSourceInterfaceSeedTests/testPrepareAnOwnedCatalogAndPosterFoldersOnAFreshGuestWithoutAnyAccount',
        cases=['HarborExistingAppUITests.CustomSourceNavigationTests/testDesktopFoldersImportOpenExplainRequirementsEditHideRestoreAndDeleteOn' + family]))
    captures += [state + '-' + family.lower() for state in ['card-artwork-pinned-catalog', 'card-image-languages', 'card-image-search', 'card-image-added', 'card-image-order', 'card-image-restored']]
    captures += ['source-' + state + '-' + family.lower() for state in ['import-dialog', 'fetch-error', 'format-error', 'imported', 'catalog', 'missing-key', 'missing-addon', 'image-editor', 'images-edited', 'hidden', 'restored', 'deleted']]
for batch in batches:
    for case in [batch['seed'], *batch['cases']]:
        target, tail = case.split('.', 1); suite, method = tail.split('/')
        target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
        assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
assert len(captures) == len(set(captures)) == 36
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=0, pending_native_cases=[], ui_only=True, ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']],
    preserve_prepared_app_data=True, fresh_preparation_executions=4, expected_total_executions=8,
    expected_original_images=36, required_original_captures=captures,
    parent_run=40317824549, parent_source='4de5469575595051ef32246df67e2de9bd9a9dc7', retained_parent_native_passes=8,
    failed_ui_cases_retried=3, affected_passed_ui_cases=1,
    affected_passed_reason='Folder image buttons are now siblings of navigation actions with an explicit 44-point hit region on both device families.',
    owned_local_source_ui_server=True, approved_native_cases_replayed=False, approved_appearance_ui_replayed=False,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    actual_personal_account_login_verified=False, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Artwork repair:UI only3FAILED+1AFFECTED,4fresh=8executions/36captures. Preserve8actual native passes and untouched appearance UI. No IPA.')
