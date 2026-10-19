"""Capture both actual order panels on fresh ordinary iPhone/iPad guests."""
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys

build = Path('ios/build')
canonical = build / 'canonical'; canonical.mkdir(parents=True, exist_ok=True)
recordings = build / 'service-recordings'; recordings.mkdir(parents=True, exist_ok=True)
plan = json.loads((build / 'preserved-episode-panel.json').read_text())
assert len(plan['ui_cases']) == 2 and plan['expected_original_images'] == 8
devices = json.loads((build / 'devices.json').read_text())['devices']
runtime, phone = next((runtime, row) for runtime, values in devices.items() for row in values if row['udid'] == os.environ['IOS_SIMULATOR'])
tablet = next(row for row in devices[runtime] if row['name'].startswith('iPad'))
types = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devicetypes', '--json'], text=True))['devicetypes']
subprocess.run(['xcrun', 'simctl', 'shutdown', os.environ['IOS_SIMULATOR']], check=True)
failures, selected_devices = [], {}
for label, info, case in zip(['IPhone', 'IPad'], [phone, tablet], plan['ui_cases']):
    kind = info.get('deviceTypeIdentifier') or next(row['identifier'] for row in types if row['name'] == info['name'])
    device = subprocess.check_output(['xcrun', 'simctl', 'create', 'Harbor Episode Order ' + label, kind, runtime], text=True).strip()
    selected_devices[label] = device
    (canonical / 'EpisodeOrderDevices.json').write_text(json.dumps(selected_devices, indent=2) + '\n')
    subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True)
    subprocess.run(['xcrun', 'simctl', 'install', device, str(build / 'DerivedData/Build/Products/Debug-iphonesimulator/Harbor.app')], check=True)
    container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, 'site.harbor.iphone', 'data'], text=True).strip())
    subprocess.run([sys.executable, 'scripts/ios/prepare-model-test-startup.py', '--container', str(container)], check=True)
    preferences = container / 'Library/Preferences/site.harbor.iphone.plist'
    values = plistlib.loads(preferences.read_bytes())
    values.update({'tvdbSeasonType': 'aired', 'tvdbOrderPanel': True, 'hideSpoilers': False, 'interface.autoRotateBanners': False})
    preferences.write_bytes(plistlib.dumps(values, fmt=plistlib.FMT_BINARY))
    bundle = build / ('EpisodeOrder' + label + 'UI.xcresult')
    video = recordings / ('episode-order-' + label.lower() + '.mp4')
    with (build / 'logs' / ('episode-order-' + label.lower() + '-recording.log')).open('w') as recording_log:
        recorder = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo', '--codec=h264', str(video)], stdout=recording_log, stderr=subprocess.STDOUT)
        try:
            command = ['xcodebuild', '-project', 'ios/Harbor.xcodeproj', '-scheme', 'HarborLive', '-configuration', 'Debug',
                '-destination', f'platform=iOS Simulator,id={device},arch={os.environ["IOS_SIMULATOR_ARCH"]}',
                '-derivedDataPath', str(build / 'DerivedData'), '-clonedSourcePackagesDirPath', str(build / 'SourcePackages'),
                '-resultBundlePath', str(bundle), '-only-testing:' + case.replace('.', '/', 1), '-parallel-testing-enabled', 'NO',
                'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'test']
            log_path = build / 'logs' / ('episode-order-' + label.lower() + '.log')
            with log_path.open('w') as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
            for line in log_path.read_text('utf-8', errors='replace').splitlines():
                if "Test Case '" in line or 'error:' in line or '** TEST ' in line: print(line, flush=True)
            method = case.split('/')[-1]
            proof = subprocess.run([sys.executable, 'scripts/ios/record-live-test-result.py', '--bundle', str(bundle),
                '--output', str(canonical / ('EpisodeOrder' + label + 'UI.json')), '--target', 'HarborUITests',
                '--suite', 'EpisodeOrderNavigationTests', '--method', method])
            if result.returncode or proof.returncode: failures.append(dict(device=label, case=case, xcode=result.returncode, proof=proof.returncode))
        finally:
            if recorder.poll() is None: recorder.send_signal(signal.SIGINT)
            try: recorder.wait(timeout=30)
            except subprocess.TimeoutExpired: recorder.terminate(); recorder.wait(timeout=10)
            subprocess.run(['xcrun', 'simctl', 'shutdown', device], check=True)
    assert video.is_file() and video.stat().st_size > 1024
    (canonical / 'EpisodeOrderUIFailures.json').write_text(json.dumps(failures, indent=2) + '\n')
if failures: raise RuntimeError('Actual order UI failures preserved; retain any independent passes: ' + str(failures))
print('Both new order panel interfaces completed with original simulator captures. No IPA or full-port approval.')
