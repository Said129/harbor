"""Keep independent actual results for the two public franchise contracts."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

build = Path('ios/build')
(build / 'canonical').mkdir(parents=True, exist_ok=True)
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--plan', choices=['preserved-anime-franchise.json', 'preserved-anime-episode-pool.json'], default='preserved-anime-franchise.json')
a = p.parse_args()
plan = json.loads((build / a.plan).read_text())
assert len(plan['public_contracts']) == (2 if a.plan == 'preserved-anime-franchise.json' else 1)
failures = []
for row in plan['public_contracts']:
    bundle = build / (row['bundle'] + '.xcresult')
    log_path = build / 'logs' / (row['bundle'] + '.log')
    command = ['xcodebuild', '-project', 'ios/Harbor.xcodeproj', '-scheme', 'HarborLive', '-configuration', 'Debug',
        '-destination', f'platform=iOS Simulator,id={os.environ["IOS_SIMULATOR"]},arch={os.environ["IOS_SIMULATOR_ARCH"]}',
        '-derivedDataPath', str(build / 'DerivedData'), '-clonedSourcePackagesDirPath', str(build / 'SourcePackages'),
        '-resultBundlePath', str(bundle), '-only-testing:' + row['case'].replace('.', '/', 1), '-parallel-testing-enabled', 'NO',
        'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'test']
    with log_path.open('w') as log:
        execution = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    for line in log_path.read_text('utf-8', errors='replace').splitlines():
        if "Test Case '" in line or 'error:' in line or '** TEST ' in line: print(line, flush=True)
    proof = subprocess.run([sys.executable, 'scripts/ios/record-live-test-result.py', '--bundle', str(bundle),
        '--output', str(build / 'canonical' / (row['bundle'] + '.json')), '--target', 'HarborIntegrationTests',
        '--suite', row['suite'], '--method', row['method']])
    if execution.returncode or proof.returncode:
        failures.append(dict(case=row['case'], xcode=execution.returncode, proof=proof.returncode))
    (build / 'canonical/FranchisePublicFailures.json').write_text(json.dumps(failures, indent=2) + '\n')
if failures: raise RuntimeError('Actual public contract failures preserved; do not repeat independent passes: ' + str(failures))
print('Selected public contracts passed. This does not approve a franchise UI or the full port.')
