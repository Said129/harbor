"""Preserve approved build 91 behavior outside the new continuity increment."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request

p = argparse.ArgumentParser()
p.add_argument('--source', required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
assert a.source == '77385750b1f8d7c80b34b04a8123d0a2c32725b5'
subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', a.source], check=True)
changed = set(subprocess.check_output(['git', 'diff', '--name-only', a.source, 'HEAD', '--', 'ios/Harbor', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge'], text=True).splitlines())
allowed = {'ios/Harbor/Models/EpisodePresentation.swift', 'ios/Harbor/Models/ContinueWatchingPresentation.swift', 'ios/Harbor/Services/AnimeLibraryDetection.swift', 'ios/Harbor/Services/AnimeEpisodeService.swift', 'ios/Harbor/ViewModels/AppModel.swift', 'ios/Harbor/Player/PlayerView.swift', 'ios/Harbor/Views/CalendarView.swift', 'ios/Harbor/Views/ContentPageView.swift', 'ios/Harbor/Views/HomeView.swift', 'ios/Harbor/Views/LibraryView.swift', 'ios/Harbor/Views/PlayerEpisodesView.swift', 'ios/Harbor/Views/PlayerUpNextView.swift', 'ios/Harbor/Views/StreamPickerView.swift', 'ios/project.yml'}
assert changed == allowed, 'Review changes outside the continuity increment'

def previous(path):
    return subprocess.check_output(['git', 'show', a.source + ':' + path])

def current(path):
    return Path(path).read_bytes().replace(b'\r\n', b'\n')

guards = {}
for path in subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', a.source, '--', 'ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests'], text=True).splitlines():
    assert previous(path) == current(path), 'Previously approved test changed: ' + path
    guards[path] = hashlib.sha256(current(path)).hexdigest()
for path in ['ios/Harbor/Models/Media.swift', 'ios/Harbor/Models/Resume.swift', 'ios/Harbor/Models/Library.swift', 'ios/Harbor/Models/LibrarySnapshot.swift', 'ios/Harbor/Player/EpisodeSequence.swift', 'ios/Harbor/Services/HarborService.swift', 'ios/Harbor/Services/StreamRequestPolicy.swift', 'ios/Harbor/Services/MediaMetadataStore.swift', 'ios/Harbor/Services/LibraryService.swift', 'ios/Harbor/Services/ResumeStore.swift', 'ios/Harbor/Services/HTTPClient.swift']:
    assert previous(path) == current(path), 'Unrelated identity, source, account or cache behavior changed: ' + path
    guards[path] = hashlib.sha256(current(path)).hexdigest()
for path, boundary in [('ios/Harbor/Services/AnimeEpisodeService.swift', b'    static func applying('), ('ios/Harbor/ViewModels/AppModel.swift', b'    func start()')]:
    before, after = previous(path), current(path)
    assert before[before.index(boundary):] == after[after.index(boundary):], 'Established mapping or account lifecycle changed'
    guards[path + '#preserved-implementation'] = hashlib.sha256(after[after.index(boundary):]).hexdigest()
assert current('ios/project.yml') == previous('ios/project.yml').replace(b'CFBundleVersion: "91"', b'CFBundleVersion: "92"', 1)
api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-continuity-validation'}

def get(path):
    with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as r:
        return json.load(r)

run = get('/actions/runs/38822918265')
assert run['head_sha'] == a.source and run['status'] == 'completed' and run['conclusion'] == 'success'
jobs = get('/actions/runs/38822918265/jobs?per_page=100')['jobs']
assert any(j['conclusion'] == 'success' and any(s['name'] == 'Package and verify unsigned iPhone IPA' and s['conclusion'] == 'success' for s in j['steps']) for j in jobs)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(dict(source=os.environ['GITHUB_SHA'], previous_source=a.source, previous_run=38822918265, unchanged_guards_sha256=guards, scope='Only ContinuationParityTests, the new public IMDb mapping/episode 99 case and the normal Anime/Shows continuation UI execute. Build 91 and its original chained evidence remain recorded for unaffected behavior; this does not recertify changed UI with historical results. The 0.9.132 1:1 goal remains in progress.', affected='Consistent presentation coordinates; IMDb anime recognition, selection and metadata coalescing; ordinary Anime/Shows continue-watching cards.'), indent=2) + '\n', 'utf-8')
print('Verified the delivered build 91 and unchanged services/tests. Only the new continuity cases execute.')
