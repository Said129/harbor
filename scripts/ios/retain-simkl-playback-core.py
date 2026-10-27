"""Verify unchanged inputs against the original authenticated Apple job log."""
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request

contract = json.loads(Path('scripts/ios/retained-simkl-playback-core.json').read_text('utf-8'))
for name, digest in contract['source_hashes'].items():
    assert hashlib.sha256(Path(name).read_bytes().replace(b'\r\n', b'\n')).hexdigest() == digest, name
base = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
headers = {'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'Accept': 'application/vnd.github+json', 'User-Agent': 'Harbor-retained-resume-proof'}
def get(path):
    with urllib.request.urlopen(urllib.request.Request(base + path, headers=headers), timeout=45) as response:
        return json.load(response)
run = get('/actions/runs/' + str(contract['run']))
assert run['head_sha'] == contract['source'] and run['status'] == 'completed'
job = get('/actions/jobs/' + str(contract['job']))
assert job['run_id'] == contract['run'] and job['name'] == 'Apple SDK / Swift / iPhone'
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, newurl):
        return None
try:
    response = urllib.request.build_opener(NoRedirect).open(urllib.request.Request(base + '/actions/jobs/' + str(contract['job']) + '/logs', headers=headers), timeout=45)
except urllib.error.HTTPError as redirect:
    if redirect.code != 302: raise
    location = redirect.headers['Location']; parsed = urllib.parse.urlparse(location)
    assert parsed.scheme == 'https' and parsed.hostname
    # Never forward the GitHub token to signed log storage.
    response = urllib.request.urlopen(location, timeout=45)
with response: data = response.read(16 * 1024 * 1024 + 1)
assert len(data) <= 16 * 1024 * 1024 and hashlib.sha256(data).hexdigest() == contract['job_log_sha256']
plain = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', data.decode('utf-8'))
assert 'Finished `dev` profile' in plain
assert 'test ' + contract['retained_core_case'] + ' ... ok' in plain
assert 'test result: ok. 1 passed; 0 failed; 0 ignored;' in plain
logs = Path('ios/build/logs'); logs.mkdir(parents=True, exist_ok=True)
(logs / 'retained-simkl-playback-core.log').write_bytes(data)
proof = dict(source=os.environ['GITHUB_SHA'], inherited=contract, original_run_authenticated=True, unchanged_inputs_verified=True,
    production_cargo_check_passed=True, retained_actual_core_cases=1, core_tests_executed_again=False)
Path('ios/build/preserved-simkl-playback-core.json').write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Authenticated unchanged Rust production check and one actual core PASS; neither rerun.')
