"""Freeze playback producers and keep the owned synthetic clip in UITests only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
application = '49110c6786903d6480c2febe101d8210f2a4fb9b'
if subprocess.run(['git', 'cat-file', '-e', application + '^{commit}'], capture_output=True).returncode != 0:
    subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', application], check=True)
roots = ['ios/Harbor', 'ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge', 'src-tauri']
allowed = {'ios/HarborTests/PlayerCaptionSeedTests.swift', 'ios/HarborUITests/PlayerCaptionNavigationTests.swift',
    'ios/HarborUITests/Fixtures/synthetic-player-caption.mp4', 'ios/project.yml'}
changed = set(subprocess.check_output(['git', 'diff', '--name-only', application, 'HEAD', '--', *roots], text=True).splitlines())
assert changed == allowed, sorted(changed ^ allowed)
project = Path('ios/project.yml').read_text('utf-8')
original = subprocess.check_output(['git', 'show', application + ':ios/project.yml']).decode('utf-8')
before = '    sources: [HarborUITests]\n'
after = '''    sources:
      - path: HarborUITests
        excludes: [Fixtures]
      - path: HarborUITests/Fixtures
        type: folder
        buildPhase: resources
'''
assert original.count(before) == 1 and project == original.replace(before, after)
clip = Path('ios/HarborUITests/Fixtures/synthetic-player-caption.mp4')
digest = hashlib.sha256(clip.read_bytes()).hexdigest()
assert clip.stat().st_size == 1_352_373 and digest == '8e043f94643f6d39551c8633155ed07d1e3c157b2d12d8f2c29255a2a5729861'
proof = dict(source=os.environ.get('GITHUB_SHA') or subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    scope='player-caption', application_source=application, application_byte_identical=True,
    clip_bytes=clip.stat().st_size, clip_sha256=digest, clip_owned_synthetic=True,
    fixture_target='HarborUITests', application_resource_configuration_unchanged=True,
    expected_native_seed_executions=2, expected_actual_ui_executions=2, expected_synthetic_screenshots=4,
    actual_execution_results='pending', physical_device_validation=False,
    full_desktop_parity_complete=False, ipa_created=False)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Unchanged app and test-only synthetic clip reviewed. Actual phone/tablet playback is pending; no IPA.')
