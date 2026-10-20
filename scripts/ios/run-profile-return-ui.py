"""Reproduce the failed phone return without replaying approved creation/settings UI."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

build = Path('ios/build')
canonical = build / 'canonical'; canonical.mkdir(parents=True, exist_ok=True)
recordings = build / 'service-recordings'; recordings.mkdir(parents=True, exist_ok=True)
plan = json.loads((build / 'preserved-profile-return.json').read_text())
assert plan['selected_case_count'] == 2 and not plan['approved_profile_creation_ui_repeated'] and not plan['ipa_requested']
device = os.environ['IOS_SIMULATOR']

def execute(case, name):
    command = ['xcodebuild', '-project', 'ios/Harbor.xcodeproj', '-scheme', 'HarborLive', '-configuration', 'Debug',
        '-destination', f'platform=iOS Simulator,id={device},arch={os.environ["IOS_SIMULATOR_ARCH"]}',
        '-derivedDataPath', str(build / 'DerivedData'), '-clonedSourcePackagesDirPath', str(build / 'SourcePackages'),
        '-resultBundlePath', str(build / (name + '.xcresult')), '-only-testing:' + case.replace('.', '/', 1),
        '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'test']
    log = build / 'logs' / (name + '.log')
    with log.open('w') as stream: result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
    for line in log.read_text('utf-8', errors='replace').splitlines():
        if "Test Case '" in line or 'error:' in line or '** TEST ' in line: print(line, flush=True)
    target, detail = case.split('.', 1); suite, method = detail.split('/')
    proof = subprocess.run([sys.executable, 'scripts/ios/record-live-test-result.py', '--bundle', str(build / (name + '.xcresult')),
        '--output', str(canonical / (name + '.json')), '--target', target, '--suite', suite, '--method', method])
    if result.returncode or proof.returncode: raise RuntimeError('Actual targeted execution failed: ' + case)

execute(plan['setup_case'], 'ProfileReturnSeed')
video = recordings / 'profile-return-iphone.mp4'
with (build / 'logs/profile-return-recording.log').open('w') as log:
    recorder = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo', '--codec=h264', str(video)], stdout=log, stderr=subprocess.STDOUT)
    try: execute(plan['ui_case'], 'ProfileReturnPhoneUI')
    finally:
        if recorder.poll() is None: recorder.send_signal(signal.SIGINT)
        try: recorder.wait(timeout=30)
        except subprocess.TimeoutExpired: recorder.terminate(); recorder.wait(timeout=10)
assert video.is_file() and video.stat().st_size > 1_024
print('Only the necessary new seed and previously failed phone return executed. Original recording retained. No IPA.')
