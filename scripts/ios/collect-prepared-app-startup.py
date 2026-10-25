"""Bounded launch diagnostics for a fresh owned simulator, without reinstalling its app."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', required=True)
parser.add_argument('--label', required=True)
parser.add_argument('--phase', choices=['before-ui', 'after-ui'], required=True)
args = parser.parse_args()
assert re.fullmatch(r'[A-Fa-f0-9-]{36}', args.device) and re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', args.label)
folder = Path('ios/build/canonical') / ('StartupProbe-' + args.label)
folder.mkdir(parents=True, exist_ok=True)
bundle_id = 'site.harbor.iphone'
records = []

def capture(name, command, timeout=30):
    try:
        result = subprocess.run(command, capture_output=True, timeout=timeout)
        (folder / name).write_bytes(result.stdout[-1_024 * 1_024:])
        if result.stderr: (folder / (name + '.stderr.txt')).write_bytes(result.stderr[-256 * 1_024:])
        records.append(dict(file=name, code=result.returncode))
    except subprocess.TimeoutExpired as failure:
        (folder / name).write_bytes((failure.stdout or b'')[-1_024 * 1_024:])
        records.append(dict(file=name, timed_out=True))

if args.phase == 'before-ui':
    started = time.time()
    (folder / 'started.json').write_text(json.dumps(dict(epoch=started, device=args.device)) + '\n', 'utf-8')
    capture('launch-help.txt', ['xcrun', 'simctl', 'help', 'launch'])
    app = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.device, bundle_id, 'app'], text=True).strip())
    capture('app-info.txt', ['xcrun', 'simctl', 'appinfo', args.device, bundle_id])
    with (app / 'Info.plist').open('rb') as stream: info = plistlib.load(stream)
    executables = [app / info['CFBundleExecutable'], app / 'Harbor.debug.dylib']
    for executable in executables:
        if executable.is_file(): capture(executable.name + '-dependencies.txt', ['xcrun', 'otool', '-L', str(executable)])
    (folder / 'embedded-frameworks.json').write_text(json.dumps(sorted(item.name for item in (app / 'Frameworks').glob('*'))) + '\n', 'utf-8')
    with (folder / 'ordinary-launch-console.txt').open('w') as stream:
        process = subprocess.Popen(['xcrun', 'simctl', 'launch', '--console-pty', '--terminate-running-process', args.device, bundle_id,
            '-uiLanguage', 'en', '-nativeGuide.initialized.v1', 'YES', '-nativeGuide.completed.v1', 'YES'], stdout=stream, stderr=subprocess.STDOUT)
        try: code = process.wait(timeout=8); exited = True
        except subprocess.TimeoutExpired: code = None; exited = False
        capture('ordinary-launch-screen.txt', ['xcrun', 'simctl', 'io', args.device, 'screenshot', str(folder / 'ordinary-launch-screen.png')])
        if process.poll() is None:
            subprocess.run(['xcrun', 'simctl', 'terminate', args.device, bundle_id], capture_output=True, timeout=15)
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired: process.terminate(); process.wait(timeout=5)
    (folder / 'ordinary-launch.json').write_text(json.dumps(dict(source=os.environ['GITHUB_SHA'], exited_before_capture=exited, exit_code=code), indent=2) + '\n', 'utf-8')
else:
    capture('ui-end-screen.txt', ['xcrun', 'simctl', 'io', args.device, 'screenshot', str(folder / 'ui-end-screen.png')])
    capture('startup-log.txt', ['xcrun', 'simctl', 'spawn', args.device, 'log', 'show', '--last', '5m', '--style', 'compact',
        '--predicate', 'process == "Harbor" OR (eventMessage CONTAINS "site.harbor.iphone" AND process == "runningboardd")'])
    metadata = json.loads((folder / 'started.json').read_text('utf-8'))
    crash_folder = Path.home() / 'Library/Logs/DiagnosticReports'
    crashes = []
    for source in sorted(crash_folder.glob('Harbor*.ips'), key=lambda item: item.stat().st_mtime, reverse=True)[:10]:
        if source.is_symlink() or source.stat().st_mtime < metadata['epoch'] or source.stat().st_size > 2 * 1_024 * 1_024: continue
        content = source.read_bytes()
        if args.device.encode() not in content: continue
        (folder / source.name).write_bytes(content); crashes.append(source.name)
    records.append(dict(crash_reports=crashes))
(folder / (args.phase + '-diagnostics.json')).write_text(json.dumps(records, indent=2) + '\n', 'utf-8')
print(json.dumps(dict(label=args.label, phase=args.phase, source=os.environ['GITHUB_SHA'], app_reinstalled=False)))
