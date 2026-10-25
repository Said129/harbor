"""Validate the previously unexecuted server changes and only the two failed continuation interfaces."""
import json
import os
from pathlib import Path
import re

marker = 'affected:server-completion'
cases = []
for suite, count in [('HarborIdentityServerTests', 8), ('HouseholdIdentitySyncTests', 4), ('HarborArtworkServerTests', 8)]:
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8').split('final class ' + suite + ': XCTestCase {', 1)[1]
    methods = re.findall(r'\bfunc (test\w+)\(', source)
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='ServerCompletion' + family, family=family,
        seed='HarborTests.WatchedByInterfaceSeedTests/testPrepareAnotherOwnedWatcherAndAnExplicitDefaultOnAFreshGuest',
        cases=['HarborExistingAppUITests.HarborIdentityServerNavigationTests/testTheAccountServerIsVisibleAndChangingItClearsThePasswordOn' + family,
            'HarborExistingAppUITests.PageContinuationNavigationTests/testOtherWatcherBadgeCoexistsWithAnimeCustomizationOn' + family]))
    captures += ['identity-server-' + state + '-' + family.lower() for state in ['community', 'custom', 'restored']]
    captures += ['anime-continue-' + state + '-' + family.lower() for state in ['initial', 'editing', 'moved', 'renamed', 'hidden', 'restored']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='server-completion', selection_marker=marker,
    selected_case_count=20, pending_native_cases=cases, ui_batches=batches,
    ui_cases=[case for batch in batches for case in batch['cases']], preserve_prepared_app_data=True,
    fresh_preparation_executions=2, expected_total_executions=26, expected_original_images=18, required_original_captures=captures,
    previously_unexecuted_identity_native_cases=12, previously_unexecuted_artwork_native_cases=8,
    previously_unexecuted_identity_ui_cases=2, failed_continuation_ui_cases_retried=2,
    compiler_only_identity_run=40162327075, compiler_only_artwork_run=40163157918,
    retained_household_activation_run=40161132799, retained_household_activation_native_cases=12,
    retained_direct_activation_cases_selected=False, affected_identity_orchestration_cases=4,
    retained_watched_by_native_run=40157907082, retained_watched_by_native_cases=10,
    retained_player_caption_native_run=40158397002, retained_player_caption_native_cases=3,
    retained_page_layout_native_run=40142488560, retained_page_layout_native_cases=20,
    retained_layout_batch_native_run=40156238216, retained_layout_batch_native_cases=6,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    actual_personal_account_login_verified=False, full_roster_layout_hydration_implemented=False,
    full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Server completion:20previously unexecuted native+2fresh+2unexecuted account UI+2FAILED continuation UI=26/18captures. No unrelated replay or IPA.')
