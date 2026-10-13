"""Validate an explicit native follow-up selection without invoking passed tests."""
import argparse
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--selection', required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
allowed = {'SearchAndSourcesTests', 'SubtitleAutoSyncTests', 'SubtitlePlaybackTests', 'AccountCollectionTests'}
selected = args.selection.split(',')
assert selected and len(set(selected)) == len(selected)
for identifier in selected:
    match = re.fullmatch(r'HarborTests/(\w+)(?:/(test\w+))?', identifier)
    assert match and match[1] in allowed, 'Unsupported native feature test selection'
    text = (Path('ios/HarborTests') / (match[1] + '.swift')).read_text('utf-8')
    if match[2]:
        assert re.search(r'func ' + re.escape(match[2]) + r'\(', text), 'Selected test does not exist'
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text('\n'.join(selected) + '\n', 'utf-8')
print('Selected native follow-up cases: ' + ', '.join(selected))
