"""Keep approved reader/provider evidence while checking EPUB taps and PDF density."""
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
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
assert a.source == 'de34523b24386c26aa543221f6aafd9e6169f206'
native_source = '1123cc1560ce132288ed99d59c08fa81a38dbed6'
for ref in [a.source, native_source]: subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', ref], check=True)
def source(ref, path): return subprocess.check_output(['git', 'show', ref + ':' + path]).decode('utf-8')
changed = set(subprocess.check_output(['git', 'diff', '--name-only', a.source, 'HEAD', '--', 'ios/Harbor', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge'], text=True).splitlines())
allowed = {'ios/Harbor/Views/EBooksView.swift', 'ios/Harbor/Services/ReadingArtwork.swift', 'ios/Harbor/Views/MangaReaderView.swift'}
assert changed == allowed, 'Reassess production changes outside EPUB hit area and PDF rendering'
guards = {}
for path in sorted(allowed):
    before = source(a.source, path)
    expected = before
    if path.endswith('EBooksView.swift'):
        expected = before.replace('                    }\n                }.buttonStyle(.plain).accessibilityIdentifier("ebook-card-" + book.id)', '                    }.contentShape(Rectangle())\n                }.buttonStyle(.plain).accessibilityIdentifier("ebook-card-" + book.id)', 1)
    elif path.endswith('MangaReaderView.swift'):
        expected = before.replace('.frame(width: width, height: width / ratio).id(page.id)', '.frame(width: width, height: width / ratio).accessibilityIdentifier("manga-page-\\(page.id)").id(page.id)', 1)
        expected = expected.replace('.frame(width: max(40, displayWidth), height: max(40, displayWidth / ratio))', '.frame(width: max(40, displayWidth), height: max(40, displayWidth / ratio)).accessibilityIdentifier("manga-page-\\(page.id)")', 1)
    else:
        expected = before.replace('        let scale = CGFloat(min(2200, max(100, maxPixels))) / max(bounds.width, bounds.height)\n        let width = max(1, Int((bounds.width * scale).rounded())), height = max(1, Int((bounds.height * scale).rounded()))', '        let rotation = (page.rotationAngle % 360 + 360) % 360\n        let swapped = rotation == 90 || rotation == 270\n        let pageSize = CGSize(width: swapped ? bounds.height : bounds.width, height: swapped ? bounds.width : bounds.height)\n        let scale = CGFloat(min(2200, max(100, maxPixels))) / max(pageSize.width, pageSize.height)\n        let width = max(1, Int((pageSize.width * scale).rounded())), height = max(1, Int((pageSize.height * scale).rounded()))')
        expected = expected.replace('        context.concatenate(page.getDrawingTransform(.cropBox, rect: rectangle, rotate: 0, preserveAspectRatio: true))', '        // Keep page geometry separate from raster density at both thumbnail\n        // and full-reader resolution, including rotated crop boxes.\n        context.scaleBy(x: CGFloat(width) / pageSize.width, y: CGFloat(height) / pageSize.height)\n        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: pageSize), rotate: 0, preserveAspectRatio: true))')
    actual = Path(path).read_text('utf-8')
    assert actual == expected, 'Reassess implementation: ' + path
    guards[path] = hashlib.sha256(actual.encode()).hexdigest()

def method(text, name):
    start = text.index('func ' + name + '('); opening = text.index('{', start); level = 1
    for end in range(opening + 1, len(text)):
        level += (text[end] == '{') - (text[end] == '}')
        if level == 0: return text[start:end + 1]
    raise AssertionError(name)
native_path = 'ios/HarborTests/ReadingUpdatesTests.swift'
before_native, after_native = source(native_source, native_path), Path(native_path).read_text('utf-8')
for name in ['testAddedSkipPreferenceKeepsEarlierPlaybackSettings', 'testNaturalShelfOrderingAndTitleAuthorSearch', 'testRealGutenbergSVGWrappersAndImportedCoversKeepProgress', 'testSkipButtonSeeksTheActualMPVWithoutReloading', 'testSkipProvidersMergeBoundsAndRealChapterFallback']:
    before, after = method(before_native, name), method(after_native, name)
    assert before == after, 'Do not change an accepted native case: ' + name
    guards[native_path + '/' + name] = hashlib.sha256(after.encode()).hexdigest()
for path in ['ios/HarborTests/StableMobileTests.swift', 'ios/HarborTests/MangaArchiveTests.swift']:
    assert source(native_source, path) == Path(path).read_text('utf-8')
    guards[path] = hashlib.sha256(Path(path).read_text('utf-8').encode()).hexdigest()
for path in ['ios/Harbor/Services/HTTPClient.swift', 'ios/Harbor/Services/SkipIntroService.swift', 'ios/Harbor/Services/GutenbergCatalog.swift', 'ios/Harbor/Services/EBookService.swift', 'ios/HarborIntegrationTests/ReadingLiveTests.swift']:
    assert source(a.source, path) == Path(path).read_text('utf-8'), 'Public provider validation must remain applicable: ' + path
    guards[path] = hashlib.sha256(Path(path).read_text('utf-8').encode()).hexdigest()

api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-reading-final'}
def get(path):
    path += ('&' if '?' in path else '?') + 'observed=' + str(time.time_ns())
    with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as r: return json.load(r)
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args): return None
def rows(run_id, ref):
    run = get(f'/actions/runs/{run_id}')
    assert run['status'] == 'completed' and run['head_sha'] == ref
    jobs = get(f'/actions/runs/{run_id}/jobs?per_page=100')['jobs']; result = []
    for job in jobs:
        if job['conclusion'] == 'skipped': continue
        if run_id == 38738164986:
            assert next(s for s in job['steps'] if s['name'] == 'Preserve approved native reading checks before provider and UI follow-up')['conclusion'] == 'success'
            assert next(s for s in job['steps'] if s['name'] == 'Run real addon services on iPhone simulator')['conclusion'] == 'success'
        request = urllib.request.Request(api + f'/actions/jobs/{job["id"]}/logs', headers=headers)
        try: response = urllib.request.build_opener(NoRedirect).open(request, timeout=45)
        except urllib.error.HTTPError as error:
            assert error.code == 302 and error.headers['Location'].startswith('https://')
            response = urllib.request.urlopen(error.headers['Location'], timeout=60)
        with response: log = response.read(50 * 1024 * 1024).decode('utf-8')
        assert 'Unbalanced calls to begin/end appearance transitions' not in log
        for m in re.finditer(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(([^)]+)\)", log): result.append(dict(case=m[1] + '/' + m[2], result=m[3], duration=m[4], source=ref, run=run_id, device='iPhone'))
    return result
base_rows = rows(38731103925, native_source)
followup_rows = rows(38738164986, a.source)
excluded = {'HarborTests.ReadingUpdatesTests/testPDFMangaPagesCoversAndOwnerIsolation', 'HarborTests.ReadingUpdatesTests/testPrepareOrdinaryReadingShelfUIFixtures'}
native = [r for r in base_rows if r['case'].startswith('HarborTests.') and r['case'] not in excluded]
providers = [r for r in followup_rows if r['case'].startswith('HarborIntegrationTests.ReadingLiveTests/')]
assert len(native) == 8 and len(providers) == 2 and all(r['result'] == 'passed' for r in native + providers)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(dict(source=os.environ['GITHUB_SHA'], preserved_native_executions=native, preserved_public_executions=providers, preserved_executions=native + providers, reviewed_transformations_sha256=guards, failed_observations=[r for r in base_rows + followup_rows if r['result'] != 'passed'], superseded_visual_observation='The earlier phone PDF reader case passed interaction checks but showed a small page in a white canvas; it is superseded by actual pixel checks and full-page UI review.', pending='PDF density at 600/2200 pixels, full-card EPUB tap, fresh fixture preparation and affected phone/tablet reading interactions'), indent=2) + '\n', 'utf-8')
print('Preserved eight native functional cases and both real provider passes; only PDF density and pending phone/tablet interactions execute.')
