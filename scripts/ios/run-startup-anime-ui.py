"""Run nine pending/affected UI journeys, preserving passed model checks."""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys

build = Path('ios/build')
canonical = build / 'canonical'; canonical.mkdir(parents=True, exist_ok=True)
recordings = build / 'startup-anime-recordings'; recordings.mkdir(parents=True, exist_ok=True)
plan = json.loads((build / 'preserved-startup-anime-ui.json').read_text())
rows = plan['executions']; assert len(rows) == 13 and sum(not row['fixture'] for row in rows) == 9
devices = json.loads((build / 'devices.json').read_text())['devices']
types = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devicetypes', '--json'], text=True))['devicetypes']
phone = os.environ['IOS_SIMULATOR']
phone_runtime, phone_info = next((runtime, row) for runtime, values in devices.items() for row in values if row['udid'] == phone)
tablet_runtime, tablet_info = next((runtime, row) for runtime, values in devices.items() if runtime == phone_runtime for row in values if row['name'].startswith('iPad'))
selected = {'profiles-iphone': phone, 'profiles-ipad': tablet_info['udid']}

def run(*command): subprocess.run(command, check=True)

def fresh(group, info, runtime):
    kind = info.get('deviceTypeIdentifier') or next(row['identifier'] for row in types if row['name'] == info['name'])
    device = subprocess.check_output(['xcrun', 'simctl', 'create', 'Harbor ' + group, kind, runtime], text=True).strip()
    assert re.fullmatch('[A-Fa-f0-9-]{36}', device)
    return device

def execute(device, row):
    scheme = 'Harbor' if row['fixture'] else 'HarborLive'
    identifier = row['target'] + '/' + row['suite'] + '/' + row['method']
    command = ['xcodebuild', '-project', 'ios/Harbor.xcodeproj', '-scheme', scheme, '-configuration', 'Debug',
        '-destination', f'platform=iOS Simulator,id={device},arch={os.environ["IOS_SIMULATOR_ARCH"]}',
        '-derivedDataPath', str(build / 'DerivedData'), '-clonedSourcePackagesDirPath', str(build / 'SourcePackages'),
        '-resultBundlePath', str(build / (row['bundle'] + '.xcresult')), '-only-testing:' + identifier,
        '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'test']
    with (build / 'logs' / (row['bundle'] + '.log')).open('w') as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            for line in process.stdout: log.write(line); print(line, end='', flush=True)
            if process.wait(): raise RuntimeError('Pending journey failed: ' + identifier)
        finally:
            if process.poll() is None: process.terminate(); process.wait(timeout=30)
    run(sys.executable, 'scripts/ios/record-live-test-result.py', '--bundle', str(build / (row['bundle'] + '.xcresult')),
        '--output', str(canonical / (row['bundle'] + '.json')), '--target', row['target'], '--suite', row['suite'], '--method', row['method'])

failures = []
for group in dict.fromkeys(row['group'] for row in rows):
    if group not in selected:
        info, runtime = (phone_info, phone_runtime) if group.endswith('iphone') else (tablet_info, tablet_runtime)
        selected[group] = fresh(group, info, runtime)
    device = selected[group]
    run('xcrun', 'simctl', 'bootstatus', device, '-b')
    run('xcrun', 'simctl', 'install', device, str(build / 'DerivedData/Build/Products/Debug-iphonesimulator/Harbor.app'))
    container = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, 'site.harbor.iphone', 'data'], text=True).strip()
    run(sys.executable, 'scripts/ios/prepare-model-test-startup.py', '--container', container)
    (canonical / 'StartupAnimeDevices.json').write_text(json.dumps(selected, indent=2) + '\n')
    video = recordings / (group + '.mp4')
    with (build / 'logs' / (group + '-recording.log')).open('w') as log:
        recorder = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo', '--codec=h264', str(video)], stdout=log, stderr=subprocess.STDOUT)
        try:
            for row in rows:
                if row['group'] == group: execute(device, row)
        except (RuntimeError, subprocess.CalledProcessError) as error:
            failures.append(dict(group=group, case=row['target'] + '.' + row['suite'] + '/' + row['method'], error=str(error)))
            (canonical / 'StartupAnimeGroupFailures.json').write_text(json.dumps(failures, indent=2) + '\n')
            print('Group failed; preserving its originals and continuing independent devices: ' + group, flush=True)
        finally:
            if recorder.poll() is None: recorder.send_signal(signal.SIGINT)
            try: recorder.wait(timeout=30)
            except subprocess.TimeoutExpired: recorder.terminate(); recorder.wait(timeout=10)
    assert video.is_file() and video.stat().st_size > 1_024
    run('xcrun', 'simctl', 'shutdown', device)
if failures:
    raise RuntimeError('Pending groups failed; independent groups were still attempted: ' + ', '.join(row['group'] for row in failures))
print('Nine UI journeys and four necessary setup executions recorded; approved model methods were not repeated. Full parity remains in progress.')
