"""Exercise actual plugin management on separate fresh iPhone/iPad guests and retain independent outcomes."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import runpy
import re
import plistlib

build = Path('ios/build'); canonical = build / 'canonical'; canonical.mkdir(parents=True, exist_ok=True)
recordings = build / 'service-recordings'; recordings.mkdir(parents=True, exist_ok=True)
plan = json.loads((build / 'preserved-plugin-integration.json').read_text())
batches = plan.get('ui_batches')
if not batches:
    device_cases = plan.get('ui_device_cases', plan['ui_cases'])
    assert len(device_cases) == 2
    batches = [dict(id=family, family=family, seed=plan['native_preparation_case'], cases=case) for family, case in zip(['IPhone', 'IPad'], device_cases)]
else:
    expected = plan['fresh_preparation_executions']
    assert 1 <= expected <= 9 and len(batches) == len({batch['id'] for batch in batches}) == expected
    assert all(re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', batch['id']) and batch['cases'] for batch in batches)
    assert {batch['family'] for batch in batches} == {'IPhone', 'IPad'}
assert plan['expected_original_images'] in (4, 6, 8, 10, 12, 13, 16, 26, 28, 34, 36, 38, 39, 47, 48, 54, 58, 61)
if plan.get('block') in ('reading-plugins', 'reading-repair', 'ebook-catalog', 'reading-bulk', 'reading-consolidated', 'reading-html', 'reading-metadata', 'reading-adaptations', 'reading-navigation', 'reading-surface', 'reading-source-refresh'):
    runpy.run_path('scripts/ios/reading-plugin-fixture-server.py')['start'](build)
if plan['selected_case_count']:
    assert (canonical / 'PluginIntegrationModels-tree.json').is_file(), 'The model bundle did not execute; do not repeat its compilation on two UI devices.'
else:
    assert plan.get('ui_only') is True and plan['pending_native_cases'] == [] and plan['block'] in ('reader-contents', 'reader-interface-completion')
devices = json.loads((build / 'devices.json').read_text())['devices']
runtime, phone = next((runtime, row) for runtime, values in devices.items() for row in values if row['udid'] == os.environ['IOS_SIMULATOR'])
tablet = next(row for row in devices[runtime] if row['name'].startswith('iPad') and row.get('isAvailable', True))
types = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devicetypes', '--json'], text=True))['devicetypes']
prebuilt = plan.get('block') in ('reading-metadata', 'reading-adaptations', 'ebook-detail', 'reading-display', 'web-fonts', 'reading-navigation', 'book-pagination', 'reader-completion', 'reading-surface', 'reader-position', 'reader-contents', 'reader-interface-completion', 'reader-bookmarks', 'reader-translation', 'reader-annotations', 'reader-narration', 'reader-narration-repair', 'reading-source-refresh')
if prebuilt:
    # A live metadata selection has not built the separate HarborTests preparation target.
    schemes = ['Harbor', 'HarborLive'] if plan.get('native_scheme') == 'HarborLive' or plan.get('ui_only') else ['HarborLive']
    with (build / 'logs' / 'reading-ui-build.log').open('w') as log:
        for scheme in schemes:
            command = ['xcodebuild', '-project', 'ios/Harbor.xcodeproj', '-scheme', scheme, '-configuration', 'Debug',
                '-destination', f'platform=iOS Simulator,id={os.environ["IOS_SIMULATOR"]},arch={os.environ["IOS_SIMULATOR_ARCH"]}',
                '-derivedDataPath', str(build / 'DerivedData'), '-clonedSourcePackagesDirPath', str(build / 'SourcePackages'),
                'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'build-for-testing']
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=900, check=True)
    native_bundle = build / 'DerivedData/Build/Products/Debug-iphonesimulator/Harbor.app/PlugIns/HarborTests.xctest'
    with (native_bundle / 'Info.plist').open('rb') as file: native_info = plistlib.load(file)
    assert (native_bundle / native_info['CFBundleExecutable']).is_file(), 'The fresh preparation bundle must exist before starting either device.'
subprocess.run(['xcrun', 'simctl', 'shutdown', os.environ['IOS_SIMULATOR']], check=True)
failures, selected = [], {}

def execute(device, prefix, scheme, case):
    cases = case if isinstance(case, list) else [case]
    bundle = build / (prefix + '.xcresult')
    command = ['xcodebuild', '-project', 'ios/Harbor.xcodeproj', '-scheme', scheme, '-configuration', 'Debug',
        '-destination', f'platform=iOS Simulator,id={device},arch={os.environ["IOS_SIMULATOR_ARCH"]}',
        '-derivedDataPath', str(build / 'DerivedData'), '-clonedSourcePackagesDirPath', str(build / 'SourcePackages'),
        '-resultBundlePath', str(bundle), *['-only-testing:' + item.replace('.', '/', 1) for item in cases], '-parallel-testing-enabled', 'NO',
        'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'test-without-building' if prebuilt else 'test']
    log_path = build / 'logs' / (prefix + '.log')
    with log_path.open('w') as log: result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=1200)
    for line in log_path.read_text('utf-8', errors='replace').splitlines():
        if "Test Case '" in line or 'error:' in line or '** TEST ' in line: print(line, flush=True)
    if isinstance(case, list):
        proof = subprocess.run([sys.executable, 'scripts/ios/record-reading-completion-results.py', '--bundle', str(bundle),
            '--output', str(canonical / (prefix + '.json')), '--cases', json.dumps(cases)])
    else:
        target, tail = case.split('.', 1); suite, method = tail.split('/')
        proof = subprocess.run([sys.executable, 'scripts/ios/record-live-test-result.py', '--bundle', str(bundle),
            '--output', str(canonical / (prefix + '.json')), '--target', target, '--suite', suite, '--method', method])
    if result.returncode or proof.returncode:
        failures.append(dict(device=device, case=case, xcode=result.returncode, proof=proof.returncode))
        return False
    return True

for batch in batches:
    label, case = batch['id'], batch['cases']
    info = phone if batch['family'] == 'IPhone' else tablet
    kind = info.get('deviceTypeIdentifier') or next(row['identifier'] for row in types if row['name'] == info['name'])
    device = subprocess.check_output(['xcrun', 'simctl', 'create', 'Harbor Plugin UI ' + label, kind, runtime], text=True).strip()
    selected[label] = device
    (canonical / 'PluginIntegrationDevices.json').write_text(json.dumps(selected, indent=2) + '\n')
    recorder = None
    try:
        subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True)
        subprocess.run(['xcrun', 'simctl', 'install', device, str(build / 'DerivedData/Build/Products/Debug-iphonesimulator/Harbor.app')], check=True)
        container = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, 'site.harbor.iphone', 'data'], text=True).strip()
        subprocess.run([sys.executable, 'scripts/ios/prepare-model-test-startup.py', '--container', container], check=True)
        if not execute(device, 'PluginSeed' + label, 'Harbor', batch['seed']): continue
        video = recordings / ('plugin-' + label.lower() + '.mp4')
        with (build / 'logs' / ('plugin-' + label.lower() + '-recording.log')).open('w') as recording_log:
            recorder = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo', '--codec=h264', str(video)], stdout=recording_log, stderr=subprocess.STDOUT)
            try: execute(device, 'PluginUI' + label, 'HarborLive', case)
            finally:
                if recorder.poll() is None: recorder.send_signal(signal.SIGINT)
                try: recorder.wait(timeout=30)
                except subprocess.TimeoutExpired: recorder.terminate(); recorder.wait(timeout=10)
                recorder = None
        if not video.is_file() or video.stat().st_size <= 1024: failures.append(dict(device=device, recording='missing-or-incomplete'))
    except (subprocess.SubprocessError, OSError) as error:
        failures.append(dict(device=device, setup_error=type(error).__name__))
    finally:
        if recorder is not None and recorder.poll() is None: recorder.terminate(); recorder.wait(timeout=10)
        subprocess.run(['xcrun', 'simctl', 'shutdown', device], check=False)
        (canonical / 'PluginIntegrationUIFailures.json').write_text(json.dumps(failures, indent=2) + '\n')
if failures: raise RuntimeError('Original partial plugin interface outcomes retained: ' + json.dumps(failures))
print('Both new real plugin management routes completed. Captures still require inspection. No IPA or full-port approval.')
