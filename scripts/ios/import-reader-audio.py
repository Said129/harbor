"""Copy the exact Desktop page-turn sound used by book-view.tsx."""
import hashlib
import json
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parents[2]
reference = Path(sys.argv[1]).resolve(strict=True)
path = 'public/flipbook/assets/mp3/turnPage.mp3'
source = reference / path
target = root / 'ios/Harbor/ReaderAudio/turnPage.mp3'
target.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(source, target)
provenance_path = root / 'docs/ios/beta-vector-provenance.json'
provenance = json.loads(provenance_path.read_text(encoding='utf-8'))
provenance['readerAudio'] = {'source': path, 'consumer': 'src/views/manga/manga-reader/book-view.tsx', 'sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'bytes': source.stat().st_size, 'modified': False}
provenance_path.write_bytes((json.dumps(provenance, indent=2, ensure_ascii=False) + '\n').encode('utf-8'))
print('Copied the original page-turn MP3 unchanged.')
