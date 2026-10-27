"""New local history, affected projection/binding and actual source controls only."""
import json
import os
from pathlib import Path
import re

block = 'local-continue'
marker = 'affected:' + block
methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/LocalContinueTests.swift').read_text('utf-8'))
assert len(methods) == len(set(methods)) == 8
cases = ['HarborTests.LocalContinueTests/' + method for method in methods]
affected = [
    'HarborTests.SimklPlaybackImportTests/testProductionLibraryMergesImportedCardsWithoutSavingThemInStremioAndDismissalSurvivesRefresh',
    'HarborTests.ProfileLibraryBindingTests/testOnlyTheSameReadyPersonalAndSourceBindingCanReuseTheLoadedLibrary',
]
cases += affected
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='LocalContinueSources' + family, family=family,
        seed='HarborTests.SimklPlaybackImportInterfaceSeedTests/testPrepareSourceControlsOnAnOwnedGuestWithoutTrackerCredentials',
        cases=['HarborExistingAppUITests.LocalContinueSourcesNavigationTests/testActualLibraryAndDownloadSourceChoicesPersistAndKeepSimklIndependentOn' + family]))
    captures += ['local-cw-sources-' + state + '-' + family.lower() for state in ['default', 'restored', 'enabled']]
for case in cases + [case for batch in batches for case in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block=block, selection_marker=marker,
    selected_case_count=10, pending_native_cases=cases, ui_batches=batches,
    ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=2, expected_total_executions=14,
    expected_original_images=6, required_original_captures=captures,
    new_native_cases=8, actually_affected_cases=affected, new_source_ui_cases=2,
    original_reference='ios/HarborTests/Fixtures/local-continue-reference.json',
    original_history_cases=13, original_cloud_absorption_cases=15,
    production_resume_and_history_composition_required=True, personal_account_requests=False,
    private_cw_complete=False, unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    retained_rust_validation_run=40444500933, full_desktop_parity_complete=False,
    physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('8 new native +2 affected +2 fresh guests +2 actual source UI=14 executions/6 captures; Rust approvals retained. No IPA.')
