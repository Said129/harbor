"""Exercise normal-profile and affected language UI on separate ordinary devices."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

build = Path('ios/build')
recordings = build / 'profile-recordings'
recordings.mkdir(parents=True, exist_ok=True)
canonical = build / 'canonical'
canonical.mkdir(parents=True, exist_ok=True)
devices = json.loads((build / 'devices.json').read_text())['devices']
tablet = next(row['udid'] for runtime, rows in devices.items() if 'iOS' in runtime for row in rows if row['name'].startswith('iPad'))
phone = os.environ['IOS_SIMULATOR']

def run(*command): subprocess.run(command, check=True)

def route(device, bundle, suite, method, target='HarborUITests', scheme='HarborLive'):
    command = ['xcodebuild', '-project', 'ios/Harbor.xcodeproj', '-scheme', scheme, '-configuration', 'Debug',
        '-destination', f'platform=iOS Simulator,id={device},arch={os.environ["IOS_SIMULATOR_ARCH"]}',
        '-derivedDataPath', 'ios/build/DerivedData', '-clonedSourcePackagesDirPath', 'ios/build/SourcePackages',
        '-resultBundlePath', str(build / (bundle + '.xcresult')), '-only-testing:' + target + '/' + suite + '/' + method,
        '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'test']
    with (build / 'logs' / (bundle + '.log')).open('w') as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            for line in process.stdout:
                log.write(line); print(line, end='', flush=True)
            if process.wait(): raise RuntimeError('UI route failed: ' + bundle)
        finally:
            if process.poll() is None: process.terminate(); process.wait(timeout=30)
    run(sys.executable, 'scripts/ios/record-live-test-result.py', '--bundle', str(build / (bundle + '.xcresult')),
        '--output', str(canonical / (bundle + '.json')), '--target', target, '--suite', suite, '--method', method)

run('xcrun', 'simctl', 'install', phone, 'ios/build/DerivedData/Build/Products/Debug-iphonesimulator/Harbor.app')
container = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', phone, 'site.harbor.iphone', 'data'], text=True).strip()
run(sys.executable, 'scripts/ios/prepare-model-test-startup.py', '--container', container)
route(phone, 'ProfileAppearanceRetry', 'ProfileAppearanceTests', 'testUnreadableLegacyAppearanceCanRecoverOnExplicitRetryAndIsIgnoredAfterMigration', 'HarborTests', 'Harbor')

for device, family, title in [(phone, 'iphone', 'IPhone'), (tablet, 'ipad', 'IPad')]:
    if device == tablet: run('xcrun', 'simctl', 'shutdown', phone)
    run('xcrun', 'simctl', 'bootstatus', device, '-b')
    # Language checks run first. The profile journey deliberately leaves a real
    # PIN-protected selection, which must not contaminate a following route.
    route(device, 'Profile' + title + 'Language', 'LanguageReferenceNavigationTests',
          'testReferenceLanguagesSwitchInTheOrdinary' + title + 'Settings')
    video = recordings / ('profiles-' + family + '.mp4')
    with (build / 'logs' / ('profiles-' + family + '-recording.log')).open('w') as log:
        recorder = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo', '--codec=h264', str(video)], stdout=log, stderr=subprocess.STDOUT)
        try:
            route(device, 'Profile' + title + 'UI', 'HouseholdProfilesNavigationTests',
                  'testNormalProfileCreationIdentityAndRestartPINWorkOn' + title)
        finally:
            if recorder.poll() is None: recorder.send_signal(signal.SIGINT)
            try: recorder.wait(timeout=30)
            except subprocess.TimeoutExpired: recorder.terminate(); recorder.wait(timeout=10)
    assert video.is_file() and video.stat().st_size > 1_024, 'Preserve the actual picker motion recording'
run('xcrun', 'simctl', 'shutdown', tablet)
print('One new recovery check and four actual UI routes recorded. Approved native checks were not repeated; full parity remains separate.')
