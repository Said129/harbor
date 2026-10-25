"""Select the new server boundary and the four affected identity orchestration cases."""
import json
import os
from pathlib import Path
import re

marker = 'affected:identity-server'
cases = []
for suite, count in [('HarborIdentityServerTests', 8), ('HouseholdIdentitySyncTests', 4)]:
    source = Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8').split('final class ' + suite + ': XCTestCase {', 1)[1]
    methods = re.findall(r'\bfunc (test\w+)\(', source)
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
requested = os.environ['HARBOR_NATIVE_SELECTION'].strip()
assert requested == marker or requested.split(',') == cases
batches, captures = [], []
for family in ['IPhone', 'IPad']:
    batches.append(dict(id='IdentityServer' + family, family=family,
        seed='HarborTests.HarborIdentityInterfaceSeedTests/testPrepareAnOwnedGuestWithoutAnIdentitySession',
        cases=['HarborExistingAppUITests.HarborIdentityServerNavigationTests/testTheAccountServerIsVisibleAndChangingItClearsThePasswordOn' + family]))
    captures += ['identity-server-' + state + '-' + family.lower() for state in ['community', 'custom', 'restored']]
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='identity-server', selection_marker=marker,
    selected_case_count=12, pending_native_cases=cases, ui_batches=batches, ui_cases=[batch['cases'][0] for batch in batches],
    preserve_prepared_app_data=True, fresh_preparation_executions=2, expected_total_executions=16,
    expected_original_images=6, required_original_captures=captures, new_native_cases=8, affected_identity_cases=4,
    original_server_credentials_automatically_forwarded=False, third_party_account_registration_requested=False,
    retained_household_activation_run=40161132799, unchanged_activation_cases_selected=False,
    retained_watched_by_native_run=40157907082, retained_watched_by_native_cases=10,
    retained_player_caption_native_run=40158397002, retained_player_caption_native_cases=3,
    retained_page_layout_native_run=40142488560, retained_page_layout_native_cases=20,
    retained_layout_batch_native_run=40156238216, retained_layout_batch_native_cases=6,
    unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
    public_artwork_and_per_profile_identity_override_audit_pending=True,
    linked_layout_fanout_still_requires_audit=True, full_desktop_parity_complete=False, ipa_requested=False)
build = Path('ios/build'); build.mkdir(parents=True, exist_ok=True)
(build / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(build / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream: stream.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('Identity server:8new+4affected native cases+2fresh+2new interfaces=16executions/6captures. No unrelated replay or IPA.')
