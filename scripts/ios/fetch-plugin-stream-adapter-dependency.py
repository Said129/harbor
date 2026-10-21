"""Fetch the exact public-suffix package declared by Desktop 0.9.132, with pinned integrity."""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import tarfile
import urllib.request

p = argparse.ArgumentParser(description=__doc__); p.add_argument('--directory', type=Path, required=True); a = p.parse_args()
version = '7.4.12'
integrity = 'sha512-WylhSDKVeYnWXL3a+vKTaOxjnOeEGw938hImY8zoRWJjRRK/Jp1K+IihBzIONpUmW4e3WmXT6q5FW6vlESVZCA=='
url = 'https://registry.npmjs.org/tldts/-/tldts-' + version + '.tgz'
with urllib.request.urlopen(url, timeout=45) as response: archive = response.read(8 * 1024 * 1024)
assert len(archive) < 8 * 1024 * 1024
assert 'sha512-' + base64.b64encode(hashlib.sha512(archive).digest()).decode() == integrity
directory = a.directory.resolve(); directory.mkdir(parents=True, exist_ok=True)
expected = {'index.umd.min.js': '202d92c731736e54220874e8dd0bdc469a01e773836b4a87169cd05a2c8dd558',
    'LICENSE': 'c64182d48160db948b6aa97a984f1a32974ce4d2053900361264cd33853796cb'}
with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as package:
    for name in ['package/package.json', 'package/LICENSE', 'package/dist/index.umd.min.js']:
        member = package.getmember(name); assert member.isfile() and member.size < 2 * 1024 * 1024
        content = package.extractfile(member).read()
        short = Path(name).name
        if short in expected: assert hashlib.sha256(content).hexdigest() == expected[short]
        else:
            metadata = json.loads(content); assert metadata['name'] == 'tldts' and metadata['version'] == version
        target = directory / short
        assert not target.is_symlink() and target.resolve().is_relative_to(directory)
        if target.exists(): assert target.read_bytes() == content, 'Existing dependency differs; refusing to overwrite'
        else: target.write_bytes(content)
print(json.dumps(dict(name='tldts', version=version, integrity_verified=True, files_verified=3)))
