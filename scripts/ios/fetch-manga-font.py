"""Validate the bundled OFL Manga typeface without an external font download.

The legacy filename remains for existing build commands. Shared mobile builds
use the unchanged Oswald font and its bundled license.
"""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parents[2]
font = root / 'ios/Harbor/Fonts/Oswald.ttf'
notice = root / 'ios/Harbor/Licenses/Oswald-OFL.txt'
assert font.resolve() == font.absolute() and notice.resolve() == notice.absolute()
assert hashlib.sha256(font.read_bytes()).hexdigest() == '5b38c246e255a12f5712d640d56bcced0472466fc68983d2d0410ec0457c2817'
assert 'SIL OPEN FONT LICENSE Version 1.1' in notice.read_text('utf-8')
assert not (root / 'ios/Harbor/Fonts/QRAmesBeta.otf').exists(), 'Remove the obsolete personal-build resource before packaging'
print('Bundled shareable Manga font and OFL notice verified; no remote font fetch is needed.')
