"""Select only the newly implemented plugin playback block; no predecessor outcomes are assumed."""
import json
import os
from pathlib import Path
import re

requested = os.environ.get('HARBOR_NATIVE_SELECTION', '').strip()
if requested:
    startup = ['HarborTests.HarborNativeNetworkTests/testMaximumRPCResponseCrossesActualWebKitWorkerBridge',
        'HarborTests.HarborPluginRuntimeTests/testWorkerInitializationKeepsItsTenSecondBudgetAfterTheNativeHostIsReady',
        'HarborTests.HarborPluginRuntimeTests/testTimeoutTerminatesABusyWorkerWithoutBlockingAnotherInstance']
    failed = ['HarborTests.HarborPluginStreamAdapterTests/' + method for method in [
        'testActualWebKitRunsAllTwentyOriginalStreamAdapterReferenceCases',
        'testCancellingOneCallerDoesNotRetireAnotherCallOrTheSharedPureContext',
        'testConcurrentCallsKeepEachTrackingPolicyAndSubsequentDefaultIndependent']]
    failed += ['HarborTests.HarborPluginStreamSourceTests/' + method for method in [
        'testActualDetailSelectionMergesPluginWorkersThroughOriginalAdapterRankingAndDirectSubtitleResolution',
        'testMasterPauseCancelsActiveProviderWithoutRemovingItOrBreakingSubsequentPlayback',
        'testRepositoryGroupingKeepsWorkingMembersAndSkipsProviderWithoutTMDBWithoutCountingFailure']]
    selected = [item.strip().replace('HarborTests/', 'HarborTests.', 1) for item in requested.split(',')]
    repair = set(selected) == set(startup + failed)
    cases = startup + failed if repair else startup
    assert len(selected) == len(set(selected)) == len(cases) and set(selected) == set(cases)
    for case in cases:
        suite, method = case.split('.', 1)[1].split('/')
        assert re.search(r'\bfunc ' + method + r'\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
    ui = ['HarborUITests.HarborPluginNavigationTests/testNewPluginPlaybackOptionsPersistOn' + device for device in ['IPhone', 'IPad']] if repair else []
    seed = 'HarborTests.HarborPluginInterfaceSeedTests/testPrepareOwnedPluginInTheOrdinaryLocalInstallation'
    plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='plugin-repair' if repair else 'plugin-startup', selected_case_count=len(cases),
        pending_native_cases=cases, failed_case=cases[0], new_case=cases[1], affected_case=cases[2],
        expected_total_executions=len(cases) + (4 if repair else 0), expected_original_images=4 if repair else 0, ui_cases=ui,
        native_preparation_case=seed if repair else None,
        required_original_captures=['plugin-options-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['paused', 'restored']] if repair else [],
        predecessor_run=39587372660, predecessor_source='cfe4160368baf1c33299aec06ddf8ec365f6e38b',
        predecessor_original_job_log_sha256='505086b292a161ef73f19075453d1d5b1d0563ac7b82e7d18606134e544ea3c0',
        predecessor_completed_executions=28, predecessor_passed_executions=27, predecessor_failed_executions=1,
        unrelated_approved_cases_selected=False, existing_rust_tests_repeated=False,
        full_desktop_parity_complete=False, ipa_requested=False)
    if repair:
        plan.update(playback_predecessor_run=39596075675, playback_predecessor_source='481c346e60bebd16fa49b54fe6605105157f1a57',
            playback_original_model_tree_sha256='cdb88eaa502a3892f171ea823efffe134d73d8f60092c437d2c0267e0f1d21dc',
            playback_failed_native_cases=failed, playback_passed_native_cases_retained=4, prior_preparation_repeated_only_for_fresh_devices=True)
    (directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
    (directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=' + ('true' if repair else 'false') + '\n')
    print(json.dumps(dict(selected_models=len(cases), failed_models=7 if repair else 1, new_models=1, affected_models=1,
        retry_ui=len(ui), approved_request_models_repeated=False, ipa_requested=False)))
    raise SystemExit(0)

cases = []
for suite, count in [('HarborPluginStreamAdapterTests', 3), ('HarborPluginStreamRequestTests', 3), ('HarborPluginStreamSourceTests', 4)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path('ios/HarborTests/' + suite + '.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == count
    cases += ['HarborTests.' + suite + '/' + method for method in methods]
assert len(cases) == len(set(cases)) == 10
seed = 'HarborTests.HarborPluginInterfaceSeedTests/testPrepareOwnedPluginInTheOrdinaryLocalInstallation'
ui = ['HarborUITests.HarborPluginNavigationTests/testNewPluginPlaybackOptionsPersistOn' + device for device in ['IPhone', 'IPad']]
for case in cases + [seed] + ui:
    target, tail = case.split('.', 1); suite, method = tail.split('/')
    assert re.search(r'\bfunc ' + method + r'\(', Path('ios/' + target + '/' + suite + '.swift').read_text('utf-8'))
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), block='plugin-playback', selected_case_count=len(cases),
    pending_native_cases=cases, new_native_cases=10, native_preparation_case=seed, ui_cases=ui,
    expected_total_executions=14, expected_original_images=4,
    required_original_captures=['plugin-options-' + state + '-' + device for device in ['iphone', 'ipad'] for state in ['paused', 'restored']],
    predecessor_run=39587372660, predecessor_source='cfe4160368baf1c33299aec06ddf8ec365f6e38b',
    predecessor_results_assumed=False, predecessor_tests_repeated=False, unrelated_approved_cases_selected=False,
    existing_rust_tests_repeated=False, public_network_case_repeated=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-integration.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-integration-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output: output.write('HARBOR_PLUGIN_UI_REQUIRED=true\n')
print('10 new playback models, 2 fresh device preparations and 2 new option routes. Previous-run outcomes remain independent. No IPA.')
