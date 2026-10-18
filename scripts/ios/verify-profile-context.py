"""Freeze the new context source for its first actual Apple model executions."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
application = '49110c6786903d6480c2febe101d8210f2a4fb9b'
if subprocess.run(['git', 'cat-file', '-e', application + '^{commit}'], capture_output=True).returncode != 0:
    subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', application], check=True)
roots = ['ios/Harbor', 'ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge', 'src-tauri']
assert not subprocess.check_output(['git', 'diff', '--name-only', application, 'HEAD', '--', *roots], text=True).strip(), 'The prepared application and tests must remain byte-identical'
cases = []
for suite in ['HouseholdProfileTests', 'HouseholdSessionTests', 'AppProfileContextTests', 'ProfileLibraryBindingTests', 'ProfilePlaybackRegistryTests', 'ProfileSettingsTests', 'HouseholdRosterSyncTests']:
    text = subprocess.check_output(['git', 'show', f'{application}:ios/HarborTests/{suite}.swift']).decode('utf-8')
    cases.extend('HarborTests.' + suite + '/' + name for name in re.findall(r'\bfunc (test\w+)\(', text))
assert len(cases) == len(set(cases)) == 55
affected = ['HarborTests.PlaybackControlTests/testPausedResumeAndBackwardJumpReachTheRequestedPosition',
            'HarborTests.PlaybackControlTests/testPictureInPictureStartsFromPausedVideoAndRestoresTheSameSession']
proof = dict(source=os.environ.get('GITHUB_SHA') or subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    scope='profile-context', application_source=application, prepared_native_cases=sorted(cases), affected_existing_cases=affected,
    expected_actual_executions=57, new_prepared_case_count=55, actual_execution_results='pending',
    previous_unexecuted_compiler_run=39117565521,
    full_profile_interface_complete=False, full_desktop_parity_complete=False,
    unrelated_native_public_and_ui_tests_repeated=False, ipa_created=False)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Frozen corrected context source reviewed. First execution of 55 new cases and two affected playback cases is pending. No IPA.')
