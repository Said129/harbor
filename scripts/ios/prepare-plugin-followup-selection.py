"""Select six failed/crashed cases, six new contracts and one affected write contract."""
import json
import os
from pathlib import Path
import re

pending = [
    ('AnimeFranchiseExtraTests', 'testMovieSelectionRoutesItsActualResumeSubtitleAndProgressIdentityWithoutChangingTheMainSeries'),
    ('AnimeSeasonArtworkTests', 'testLocalizedTMDBSeasonParserRejectsUntranslatedScriptsAndRetainsSpecialSeasons'),
    ('AnimeSeasonArtworkTests', 'testOptionalSeasonMetadataLoadsOnceWithoutReplacingPlaybackIdentityAndCanRetryAfterFailure'),
    ('AnimeSeasonArtworkTests', 'testSeasonMetadataCannotPublishAfterCancellationOwnerOrActivationChanges'),
    ('HarborPluginRuntimeTests', 'testInitializationAndMissingMethodsReportRealFailuresInsteadOfEmptyResults'),
    ('HarborPluginRuntimeTests', 'testPinnedHarborWorkerParsesActualHTMLAndExposesDeclaredMethods'),
    ('ResumeStoreTests', 'testFailedWriteDoesNotCommitMemory'),
]
for suite, expected_count in [('ResumeRestartTests', 2), ('HarborPluginGRPCTests', 4)]:
    methods = re.findall(r'\bfunc (test\w+)\(', Path(f'ios/HarborTests/{suite}.swift').read_text('utf-8'))
    assert len(methods) == len(set(methods)) == expected_count
    pending += [(suite, method) for method in methods]
for suite, method in pending:
    assert re.search(r'\bfunc ' + re.escape(method) + r'\(', Path(f'ios/HarborTests/{suite}.swift').read_text('utf-8'))
cases = ['HarborTests.' + suite + '/' + method for suite, method in pending]
assert len(cases) == len(set(cases)) == 13
assert not any('HarborPluginCatalogTests' in case or 'ProfileForegroundCycleTests' in case for case in cases)
plan = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), selected_case_count=13, pending_native_cases=cases,
    failed_or_crashed_reexecutions=6, new_grpc_cases=4, new_explicit_restart_cases=2, affected_resume_write_cases=1,
    preserved_runs=[dict(run=39414339731, source='679b6290e55a19f0ae75c29e883304c6f19b3aa2', native_passes=24, other_passes=3),
        dict(run=39417458336, source='fbdb2c62bae375b9df45d1a8987a1e9f50b8341b', native_passes=8, compiler_warning_requires_recheck=True)],
    unrelated_approved_cases_selected=False, public_provider_execution=False, approved_profile_ui_repeated=False,
    plugin_room_complete=False, full_desktop_parity_complete=False, ipa_requested=False)
directory = Path('ios/build'); directory.mkdir(parents=True, exist_ok=True)
(directory / 'preserved-plugin-followup.json').write_text(json.dumps(plan, indent=2) + '\n', 'utf-8')
(directory / 'plugin-followup-selection.txt').write_text('\n'.join(case.replace('.', '/', 1) for case in cases) + '\n', 'utf-8')
print('13 failed/crashed, new or affected contracts selected. The actual 35 recent passes are retained.')
