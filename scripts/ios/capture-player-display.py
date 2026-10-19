"""Capture the real simulator display only when its ordinary UI test requests it."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import struct
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--device', required=True)
p.add_argument('--family', choices=['iphone', 'ipad'], required=True)
p.add_argument('--bundle', choices=['LiveTests', 'PlayerCaptionTabletUI'], required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
assert re.fullmatch('[A-Fa-f0-9-]{36}', a.device)
output = a.output.resolve(); assert output.is_relative_to(Path('ios/build').resolve())
output.mkdir(parents=True, exist_ok=True)
stopping = False
def stop(*_):
    global stopping
    stopping = True
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
seen = set()
base = 'http://127.0.0.1:48192'
case = 'HarborUITests.PlayerCaptionNavigationTests/testActual' + ('IPhone' if a.family == 'iphone' else 'IPad') + 'PlayerShowsAbsoluteNinetyNineAndAdvancesToOneHundred'
while not stopping:
    try:
        with urllib.request.urlopen(base + '/qa/capture', timeout=2) as response:
            data = response.read(65_537)
        assert len(data) <= 65_536
        request = json.loads(data)
    except (urllib.error.URLError, TimeoutError, ConnectionError):
        time.sleep(0.25); continue
    if request is None:
        time.sleep(0.25); continue
    token, name = request['token'], request['name']
    assert re.fullmatch('[A-Fa-f0-9-]{36}', token)
    assert re.fullmatch('synthetic-player-' + a.family + '-episode-(99|100)', name)
    assert len(request['app']) == len(request['caption']) == 4
    assert request['deviceOrientation'] in ['landscapeLeft', 'landscapeRight']
    assert all(isinstance(value, (int, float)) and math.isfinite(value) for value in request['app'] + request['caption'])
    if token in seen:
        time.sleep(0.25); continue
    seen.add(token)
    png = output / (name + '_simctl.png')
    manifest = output / (name + '_simctl.json')
    assert not png.exists() and not manifest.exists(), 'Preserve the first actual capture rather than overwrite evidence'
    record = dict(source=os.environ['GITHUB_SHA'], case=case, bundle=a.bundle, device=a.device, request=request,
        capture_api='xcrun simctl io DEVICE screenshot --type=png', captured_at_unix=time.time(), manual_visual_review='pending')
    try:
        command = ['xcrun', 'simctl', 'io', a.device, 'screenshot', '--type=png', str(png)]
        capture = subprocess.run(command, capture_output=True, timeout=25)
        record.update(returncode=capture.returncode, stderr=capture.stderr.decode('utf-8', errors='replace')[-4_096:])
        assert capture.returncode == 0 and png.is_file() and 32 <= png.stat().st_size <= 16 * 1024 * 1024
        image = png.read_bytes()
        assert image[:8] == b'\x89PNG\r\n\x1a\n' and image[12:16] == b'IHDR'
        width, height = struct.unpack('>II', image[16:24])
        assert 100 < min(width, height) <= max(width, height) <= 16_384
        app_width, app_height = request['app'][2:]
        assert app_width > app_height > 0
        # simctl may preserve the physical portrait pixel buffer while UIKit's
        # window is landscape. Keep the PNG bytes untouched and state exactly
        # how its full display coordinates map to the actual device orientation.
        rotation = 0 if width > height else -90 if request['deviceOrientation'] == 'landscapeLeft' else 90
        display_width, display_height = (width, height) if rotation == 0 else (height, width)
        assert display_width > display_height and abs(display_width / display_height - app_width / app_height) < 0.03
        digest = hashlib.sha256(image).hexdigest()
        record.update(status='captured', file=png.name, bytes=len(image), width=width, height=height,
            display_width=display_width, display_height=display_height, display_rotation=rotation, sha256=digest, pixels_modified=False)
        # Retain the real file and its association before acknowledging it. The
        # XCTest server validates these exact bytes and attaches the same PNG.
        manifest.write_text(json.dumps(record, indent=2) + '\n')
        query = urllib.parse.urlencode(dict(width=width, height=height, rotation=rotation, sha256=digest))
        upload = urllib.request.Request(base + '/qa/ack/' + token + '?' + query, data=image,
            headers={'Content-Type': 'image/png'}, method='POST')
        with urllib.request.urlopen(upload, timeout=8) as response:
            assert response.status == 200
        record['acknowledged'] = True
    except (AssertionError, subprocess.SubprocessError, OSError) as error:
        record.update(status='capture-failed', error=type(error).__name__, acknowledged=False)
    manifest.write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(dict(name=name, status=record['status'], acknowledged=record.get('acknowledged', False))), flush=True)
