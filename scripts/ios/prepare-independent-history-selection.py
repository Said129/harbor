"""Only new independent history behavior and its changed episode presentation."""
import json
import os
from pathlib import Path
import re

marker = 'affected:independent-history'
cases = []
for suite, count in [('IndependentManualHistoryTests', 3), ('LibraryHistoryMountTests', 1)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches = [dict(id='IndependentHistory' + family, family=family,
    seed='HarborTests.LibraryHistoryInterfaceSeedTests/testPrepareIndependentOwnedHistoryForTheRealLibraryInterface',
    cases=['HarborExistingAppUITests.LibraryHistoryNavigationTests/testEpisodeCaptionUsesTheEnglishCatalogOn' + family]) for family in ['IPhone', 'IPad']]
captures = ['library-history-native-' + mode + '-' + size for size in ['compact', 'regular'] for mode in ['posters', 'episodes']]
captures += ['library-history-episode-caption-' + device for device in ['iphone', 'ipad']]
for case in cases + [item for batch in batches for item in [batch['seed'], *batch['cases']]]:
    target, tail = case.split('.', 1)
    suite, method = tail.split('/')
    target = 'HarborUITests' if target == 'HarborExistingAppUITests' else target
    assert len(re.findall(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))) == 1
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='independent-history', selection_marker=marker,
    selected_case_count=4, pending_native_cases=cases, new_native_cases=3,
    affected_native_cases=[cases[-1]], affected_mount_reason='Localized episode captions and their accessibility value changed in the actual mounted history cards.',
    ui_batches=batches, ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=2, expected_total_executions=8, expected_original_images=6, required_original_captures=captures,
    retained_manual_run=40675700785, retained_manual_source='041ca4830c46bc98d04c104253d7d2795056d2c2',
    independent_history_parent_run=40674798409, original_reference='ios/HarborTests/Fixtures/library-history-reference.json',
    collect_launch_failure_diagnostics=True, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, full_desktop_parity_complete=False, physical_performance_verified=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('3 new native +1 changed component mount +2 fresh +2 new caption interfaces=8 executions/6 originals; all5 approved manual mark cases retained.')
