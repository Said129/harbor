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
test_source = 'ac673a2154f2cd216cca31417066c594aab2346a'
previous_test_source = 'a4d6092e8902c07a260ece290e21ff0bed294759'
for revision in [application, test_source, previous_test_source]:
    if subprocess.run(['git', 'cat-file', '-e', revision + '^{commit}'], capture_output=True).returncode != 0:
        subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', revision], check=True)
roots = ['ios/Harbor', 'ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge', 'src-tauri']
allowed = {'ios/HarborTests/PlayerCaptionSeedTests.swift', 'ios/HarborUITests/PlayerCaptionNavigationTests.swift',
    'ios/HarborUITests/Fixtures/synthetic-player-caption.mp4', 'ios/project.yml'}
changed = set(subprocess.check_output(['git', 'diff', '--name-only', application, 'HEAD', '--', *roots], text=True).splitlines())
assert changed == allowed, sorted(changed ^ allowed)
assert not subprocess.check_output(['git', 'diff', '--name-only', test_source, 'HEAD', '--',
    'ios/HarborTests/PlayerCaptionSeedTests.swift', 'ios/HarborUITests/PlayerCaptionNavigationTests.swift',
    'scripts/ios/capture-player-display.py', 'scripts/ios/run-player-caption-ui.py'], text=True).strip(), 'Freeze the reviewed assertions and real display capture handoff'
path = 'ios/HarborUITests/PlayerCaptionNavigationTests.swift'
old = subprocess.check_output(['git', 'show', previous_test_source + ':' + path]).decode('utf-8')
current = Path(path).read_text('utf-8')
begin, end = '    private func verifyPlayer(', '    private func capture('
expected = old[old.index(begin):old.index(end)].replace('        capture(app, name:', '        try await capture(app, server: server, name:')
assert current[current.index(begin):current.index(end)] == expected, 'Preserve render-ready, pause, hittable captions, original IDs and manual next assertions'
begin, end = '    func start() async throws', '    private func receive('
assert old[old.index(begin):old.index(end)] == current[current.index(begin):current.index(end)]
begin = '    private func sendClip('
assert old[old.index(begin):] == current[current.index(begin):], 'Byte-range playback and socket cleanup remain unchanged'
assert 'XCUIScreen.main.screenshot()' not in current and 'XCTAttachment(data: receipt.png' in current
assert 'SHA256.hash(data: png)' in current and 'Self.captureRotation(width: width, height: height, request: $0)' in current
assert 'XCTAssertGreaterThan(receipt.displayWidth, receipt.displayHeight)' in current
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
    scope='player-caption', application_source=application, test_source=test_source, application_byte_identical=True,
    clip_bytes=clip.stat().st_size, clip_sha256=digest, clip_owned_synthetic=True,
    fixture_target='HarborUITests', application_resource_configuration_unchanged=True,
    expected_native_seed_executions=2, expected_actual_ui_executions=2, expected_synthetic_screenshots=4,
    native_seed_case='HarborTests.PlayerCaptionSeedTests/testPrepareOrdinaryGuestForSyntheticPlayerCaptionUI',
    ordinary_guest_setting='autoHideControls=false; caption and manual next assertions require visible controls',
    previous_failed_run=39121115983,
    previous_functional_pass_run=39145147124,
    latest_failed_visual_run=39232981721,
    observed_failure='simctl preserved a real complete1206x2622 physical pixel buffer containing the landscape player and E99, while the actual UIKit app frame was874x402. The old landscape-IHDR-only guard rejected it; no ack or next episode occurred. Keep the raw bytes and declare the orientation transform instead of altering pixels.',
    visual_followup='Keep the real player assertions. The test-only listener requests a host simctl full-display PNG, validates the exact returned bytes/hash/dimensions and attaches those original bytes before advancing. No app/production screenshot hook is added.',
    screen_capture_api='xcrun simctl io DEVICE screenshot --type=png; original PNG attached by XCTest after byte/hash verification', expected_geometry_attachments=4,
    expected_host_capture_manifests=4, host_capture_synthetic_protocol_check='external mocked companion check only; actual simulator capture still pending',
    physical_pixel_buffer_preserved=True, pixels_modified=False, display_rotation_metadata_required=True,
    actual_ui_cases=['HarborUITests.PlayerCaptionNavigationTests/testActualIPhonePlayerShowsAbsoluteNinetyNineAndAdvancesToOneHundred',
        'HarborUITests.PlayerCaptionNavigationTests/testActualIPadPlayerShowsAbsoluteNinetyNineAndAdvancesToOneHundred'],
    actual_execution_results='pending', physical_device_validation=False,
    full_desktop_parity_complete=False, ipa_created=False)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Unchanged app and test-only synthetic clip reviewed. Actual phone/tablet playback is pending; no IPA.')
