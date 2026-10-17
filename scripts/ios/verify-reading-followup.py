"""Retain approved native reading tests while fixing provider headers and UI input."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.error
import urllib.request

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', required=True)
p.add_argument('--run', type=int, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
assert a.source == '1123cc1560ce132288ed99d59c08fa81a38dbed6' and a.run == 38731103925
subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', a.source], check=True)
paths = ['ios/Harbor', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge']
changed = set(subprocess.check_output(['git', 'diff', '--name-only', a.source, 'HEAD', '--', *paths], text=True).splitlines())
allowed = {'ios/Harbor/Services/EBookService.swift', 'ios/Harbor/Services/HTTPClient.swift', 'ios/Harbor/Services/SkipIntroService.swift', 'ios/Harbor/Views/HarborControls.swift', 'ios/Harbor/Views/EBooksView.swift', 'ios/Harbor/Views/MangaView.swift'}
assert changed == allowed, 'Reassess production changes outside the reviewed provider/search fix'
guards = {}
for path in sorted(allowed):
    before = subprocess.check_output(['git', 'show', a.source + ':' + path]).decode('utf-8')
    expected = before
    if path.endswith('EBookService.swift'):
        start = before.index('    private var mirrorBlockedUntil')
        end = before.index('    func open(', start)
        expected = before[:start] + '    func catalog(query: String, language: String, page: Int) async throws -> ([EBook], Bool) {\n        // Query the publisher directly; an unavailable mirror delayed every first search.\n        return try await GutenbergCatalog.catalog(query: query, language: language, page: page)\n    }\n' + before[end:]
    elif path.endswith('HTTPClient.swift'):
        expected = expected.replace('credentialed: Bool = false) async throws', 'credentialed: Bool = false, accept: String = "application/json") async throws')
        expected = expected.replace('["https", "http"].contains(url.scheme) else', '["https", "http"].contains(url.scheme), ["application/json", "application/vnd.api+json"].contains(accept) else')
        expected = expected.replace('        let request = URLRequest(url: url, cachePolicy: credentialed', '        var request = URLRequest(url: url, cachePolicy: credentialed')
        expected = expected.replace('        for attempt in 0..<2 {', '        request.setValue(accept, forHTTPHeaderField: "Accept")\n        for attempt in 0..<2 {', 1)
        expected = expected.replace('        request.setValue("application/json", forHTTPHeaderField: "Accept")', '        if request.value(forHTTPHeaderField: "Accept") == nil { request.setValue("application/json", forHTTPHeaderField: "Accept") }')
    elif path.endswith('SkipIntroService.swift'):
        expected = expected.replace('json("https://kitsu.io/api/edge/anime/\\(identifier)/mappings")', 'json("https://kitsu.io/api/edge/anime/\\(identifier)/mappings", accept: "application/vnd.api+json")')
    elif path.endswith('HarborControls.swift'):
        expected = expected.replace('    @Binding var text: String\n', '    @Binding var text: String\n    var dismissOnSubmit = false\n    @FocusState private var focused: Bool\n', 1)
        field = '            TextField(prompt, text: $text).font(HarborTheme.font(14)).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)\n'
        expected = expected.replace(field, field + '                .focused($focused).onSubmit { if dismissOnSubmit { focused = false } }\n', 1)
    elif path.endswith('EBooksView.swift'):
        expected = expected.replace('"Buscar en tu estantería…", text: $query)', '"Buscar en tu estantería…", text: $query, dismissOnSubmit: true)', 1)
    elif path.endswith('MangaView.swift'):
        expected = expected.replace('HarborSearchField(prompt: "Buscar manga…", text: $query)', 'HarborSearchField(prompt: "Buscar manga…", text: $query, dismissOnSubmit: true)', 1)
    actual = Path(path).read_text('utf-8')
    assert actual == expected, 'Reassess changed implementation: ' + path
    guards[path] = hashlib.sha256(actual.encode()).hexdigest()
for path in ['ios/HarborTests/ReadingUpdatesTests.swift', 'ios/HarborTests/StableMobileTests.swift', 'ios/HarborTests/MangaArchiveTests.swift']:
    before = subprocess.check_output(['git', 'show', a.source + ':' + path]).decode('utf-8')
    assert before == Path(path).read_text('utf-8'), 'Accepted native tests must remain unchanged'
    guards[path] = hashlib.sha256(before.encode()).hexdigest()

api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-reading-followup'}
def get(path):
    path += ('&' if '?' in path else '?') + 'observed=' + str(time.time_ns())
    with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as r: return json.load(r)
run = get(f'/actions/runs/{a.run}')
assert run['status'] == 'completed' and run['conclusion'] == 'failure' and run['head_sha'] == a.source
jobs = get(f'/actions/runs/{a.run}/jobs?per_page=100')['jobs']
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args): return None
rows = []
for job in jobs:
    if job['conclusion'] == 'skipped': continue
    assert next(s for s in job['steps'] if s['name'] == 'Run bridge and model tests on iPhone simulator')['conclusion'] == 'success'
    request = urllib.request.Request(api + f'/actions/jobs/{job["id"]}/logs', headers=headers)
    try: response = urllib.request.build_opener(NoRedirect).open(request, timeout=45)
    except urllib.error.HTTPError as error:
        assert error.code == 302 and error.headers['Location'].startswith('https://')
        response = urllib.request.urlopen(error.headers['Location'], timeout=60)
    with response: log = response.read(50 * 1024 * 1024).decode('utf-8')
    assert 'Unbalanced calls to begin/end appearance transitions' not in log
    for m in re.finditer(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(([^)]+)\)", log):
        rows.append(dict(case=m[1] + '/' + m[2], result=m[3], duration=m[4], run=a.run, source=a.source, device='iPhone'))
native = [r for r in rows if r['case'].startswith('HarborTests.')]
assert len(native) == 10 and all(r['result'] == 'passed' for r in native)
failed = [r for r in rows if r['result'] != 'passed']
assert len(failed) == 3 and all(r['result'] == 'failed' for r in failed)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(dict(source=os.environ['GITHUB_SHA'], preserved_source=a.source, preserved_run=a.run, preserved_executions=native, failed_observations=failed, reviewed_transformations_sha256=guards, pending='Kitsu JSON:API headers, direct publisher search and phone/tablet keyboard/navigation interactions; native seed only prepares fresh simulator data'), indent=2) + '\n', 'utf-8')
print('Preserved ten native passes. Only provider/search follow-up and pending phone/tablet interactions execute; the native seed prepares fresh data.')
