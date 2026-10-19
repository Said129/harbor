"""Run the real player journey with a bounded host display-capture companion."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--device', required=True)
p.add_argument('--family', choices=['iphone', 'ipad'], required=True)
p.add_argument('--bundle', choices=['LiveTests', 'PlayerCaptionTabletUI'], required=True)
a = p.parse_args()
build = Path('ios/build')
method = 'testActual' + ('IPhone' if a.family == 'iphone' else 'IPad') + 'PlayerShowsAbsoluteNinetyNineAndAdvancesToOneHundred'
command = ['xcodebuild', '-project', 'ios/Harbor.xcodeproj', '-scheme', 'HarborLive', '-configuration', 'Debug',
    '-destination', f'platform=iOS Simulator,id={a.device},arch={os.environ["IOS_SIMULATOR_ARCH"]}',
    '-derivedDataPath', str(build / 'DerivedData'), '-clonedSourcePackagesDirPath', str(build / 'SourcePackages'),
    '-resultBundlePath', str(build / (a.bundle + '.xcresult')),
    '-only-testing:HarborUITests/PlayerCaptionNavigationTests/' + method,
    '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'test']
with (build / 'logs' / (a.bundle + '-display-capture.log')).open('w') as capture_log:
    companion = subprocess.Popen([sys.executable, 'scripts/ios/capture-player-display.py', '--device', a.device,
        '--family', a.family, '--bundle', a.bundle, '--output', str(build / 'canonical/player-displays')], stdout=capture_log, stderr=subprocess.STDOUT)
    try:
        with (build / 'logs' / ('live.log' if a.family == 'iphone' else 'player-caption-tablet.log')).open('w') as log:
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                for line in process.stdout: log.write(line); print(line, end='', flush=True)
                result = process.wait()
            finally:
                if process.poll() is None: process.terminate(); process.wait(timeout=30)
    finally:
        if companion.poll() is None: companion.send_signal(signal.SIGTERM)
        try: companion.wait(timeout=30)
        except subprocess.TimeoutExpired: companion.kill(); companion.wait(timeout=10)
if result: raise SystemExit(result)
if companion.returncode: raise SystemExit('The actual display capture companion failed; preserve its diagnostics.')
