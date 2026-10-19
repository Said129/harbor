"""Keep original results, screenshots and recordings after successful or failed UI."""
import json
import os
from pathlib import Path
import shutil
import subprocess

build = Path('ios/build')
guard = build / 'preserved-startup-anime-ui.json'
plan = json.loads(guard.read_text())
assert plan['prior_runs_checked'] and not plan['source_only']
folder = build / 'startup-anime-ui-evidence'
(folder / 'attachments').mkdir(parents=True, exist_ok=True)
for row in plan['executions']:
    bundle = build / (row['bundle'] + '.xcresult')
    if bundle.is_dir():
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(bundle), '--output-path', str(folder / 'attachments' / row['bundle'])], check=True)
for source in [build / 'logs', build / 'canonical', build / 'startup-anime-recordings']:
    if source.is_dir(): shutil.copytree(source, folder / source.name, dirs_exist_ok=True)
shutil.copy2(guard, folder / guard.name)
(folder / 'validation-only.json').write_text(json.dumps(dict(source=os.environ['GITHUB_SHA'], run=int(os.environ['GITHUB_RUN_ID']),
    scope='startup-anime-ui', validation_only=True, ipa_created=False, full_desktop_parity_complete=False), indent=2) + '\n')
archive = build / 'iphone-startup-anime-ui-evidence.zip'
subprocess.run(['ditto', '-c', '-k', '--keepParent', str(folder), str(archive)], check=True)
subprocess.run(['gh', 'release', 'create', 'iphone-startup-anime-ui-evidence-' + os.environ['GITHUB_RUN_ID'], str(archive),
    '--repo', os.environ['GITHUB_REPOSITORY'], '--target', os.environ['GITHUB_SHA'], '--draft', '--prerelease',
    '--title', 'Startup and episode UI evidence ' + os.environ['GITHUB_RUN_ID'],
    '--notes', 'Actual pending/affected simulator journeys and ordinary setup evidence. No IPA, private account or private addon. Full Desktop parity remains in progress.'], check=True)
