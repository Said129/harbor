"""Preserve the pinned Desktop public music catalog, with a native context and bounded HTTP body."""
import argparse
import hashlib
import json
from pathlib import Path
import re

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--reference', type=Path, required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
expected = {'LICENSE': 'bab95a485a9589099811f44257f3ba1d67791ff205a48c46ede66313751c241a', 'src-tauri/src/music.rs': '1177dd263c3ebf2d8589da2502daaa0f0d179243ed83160647f1182ea7d773d6', 'src-tauri/src/music/model.rs': '2dd1b17478a59073b578c0788ab995d733871d2d418dc874813a5e6038722aa8', 'src-tauri/src/music/connector.rs': '4490f62a347ac860722bf362e7aee1f25d0ec535dee1e6157510ec1f849fae8d', 'src-tauri/src/music/connectors/catalog/mod.rs': 'dcf0e1835412519962bc1d416497ccdfaeaba070247fad0f37e7d7a5b93c65e0', 'src-tauri/src/music/connectors/catalog/http.rs': '83277edf9d846bd4da5999e83fa3b9b7431e55271112bf83844ed1c90efd9bf4', 'src-tauri/src/music/connectors/catalog/coverart.rs': 'b0e09065606be6dc5b76be160aaa520b4d19a95d7646a28b8f18800f019ea31e', 'src-tauri/src/music/connectors/catalog/deezer.rs': 'f59ce3cf3eca198d41f0a180cf97e9823aa3ac1dfeb7b281750cbe6701e77c0e', 'src-tauri/src/music/connectors/catalog/itunes.rs': 'ea2b96328a7c70f860f200308d38ee9524b1e109f67315aefb93e7d2af390302', 'src-tauri/src/music/connectors/catalog/listenbrainz.rs': 'cd1cb3fe364d9db390a3080cd5431f1ff7a6bfd4aa8ac54e97dd9024e7084983', 'src-tauri/src/music/connectors/catalog/musicbrainz.rs': '9e413ab8ebf761cdc0971e23edaeeba58cbc2ee4ff0b6b83ccc51fd2bdbbedb9'}
for name, digest in expected.items():
    assert hashlib.sha256((a.reference / name).read_bytes()).hexdigest() == digest, name
assert json.loads((a.reference / 'package.json').read_text('utf-8'))['version'] == '0.9.132'
upstream = a.reference / 'src-tauri/src/music'
target = root / 'harbor-ios-bridge/src/music'
catalog = target / 'connectors/catalog'; catalog.mkdir(parents=True, exist_ok=True)
outputs = {}

def save(path, data):
    if isinstance(data, str): data = data.encode('utf-8')
    path.write_bytes(data); outputs[path.relative_to(root).as_posix()] = hashlib.sha256(data).hexdigest()

save(target / 'UPSTREAM-LICENSE', (a.reference / 'LICENSE').read_bytes())
save(target / 'model.rs', (upstream / 'model.rs').read_bytes())
for name in ['coverart.rs', 'deezer.rs', 'itunes.rs', 'listenbrainz.rs', 'musicbrainz.rs']:
    save(catalog / name, (upstream / 'connectors/catalog' / name).read_bytes())

source = (upstream / 'connector.rs').read_text('utf-8')
health = source[source.index('#[derive(Debug, Clone, Copy'):source.index('#[async_trait]')]
save(target / 'connector.rs', 'use serde::Serialize;\nuse std::sync::atomic::{AtomicU8, Ordering};\n\n' + health)
unsupported = source[source.index('    fn unsupported('):source.index('    async fn browse_home(')]

source = (upstream / 'connectors/catalog/mod.rs').read_text('utf-8')
assert source.count('#[async_trait]') == source.count('impl MusicConnector for CatalogConnector') == 1
source = source.replace(', MusicConnector', '').replace('use async_trait::async_trait;\n', '')
source = source.replace('#[async_trait]\nimpl MusicConnector for CatalogConnector {', 'impl CatalogConnector {\n' + unsupported)
start = source.index('impl CatalogConnector {', source.index('impl Default'))
end = source.index('\nasync fn home_rows()')
body = source[start:end].replace('&tauri::AppHandle', '&crate::music::CatalogContext')
body = re.sub(r'^    (async )?fn ', lambda m: '    pub ' + (m[1] or '') + 'fn ', body, flags=re.M)
assert 'tauri::' not in body
source = source[:start] + body + source[end:]
save(catalog / 'mod.rs', source)

source = (upstream / 'connectors/catalog/http.rs').read_text('utf-8')
source = source.replace('env!("CARGO_PKG_VERSION")', '"0.9.132"')
source = source.replace('    let response = CLIENT', '    let mut response = CLIENT')
before = '''    let text = response
        .text()
        .await
        .map_err(|error| format!("{provider} response was unreadable: {error}"))?;'''
after = '''    const MAX_BODY: usize = 8 * 1024 * 1024;
    if response.content_length().is_some_and(|length| length > MAX_BODY as u64) {
        return Err(format!("{provider} response exceeded the native catalog limit"));
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await
        .map_err(|error| format!("{provider} response was unreadable: {error}"))? {
        if bytes.len().saturating_add(chunk.len()) > MAX_BODY {
            return Err(format!("{provider} response exceeded the native catalog limit"));
        }
        bytes.extend_from_slice(&chunk);
    }
    let text = String::from_utf8_lossy(&bytes).into_owned();'''
assert source.count(before) == 1
save(catalog / 'http.rs', source.replace(before, after))

source = (upstream.parent / 'music.rs').read_text('utf-8')
models = source[source.index('#[derive(Debug, Clone, Deserialize, Serialize)]'):source.index('impl MusicStream {')]
duration = source[source.index('fn duration_label(seconds: u64)'):]
assert duration.count('fn ') == 1
save(target / 'types.rs', 'use serde::{Deserialize, Serialize};\n\n' + models + duration)

labels = sorted(set(re.findall(r'"(music\.[A-Za-z0-9_.]+)"', (upstream / 'connectors/catalog/mod.rs').read_text('utf-8'))) | {'music.artist.limited'})
(root / 'ios/Harbor/DesktopMusicCatalogLabels.json').write_text(json.dumps(dict(keys=labels), indent=2) + '\n', 'utf-8')
manifest = dict(reference_version='0.9.132', reference_commit='0834340cec5531650bfe78cd628628702e636987',
    original_inputs=expected, generated_outputs=outputs,
    unchanged_modules=['model.rs', 'coverart.rs', 'deezer.rs', 'itunes.rs', 'listenbrainz.rs', 'musicbrainz.rs'],
    adaptations=['Tauri trait becomes inherent catalog methods taking an empty native context',
        'Keep the original atomic health cell and unsupported-operation text',
        'Keep original algorithms, provider order, ID validation, rate limits and bound artist cursors',
        'HTTP identifies the pinned version and enforces an 8 MiB response-body budget'],
    localized_label_keys=labels, generator_executes_tests=False, full_music_parity_complete=False)
(root / 'docs/ios/music-open-catalog-sources.json').write_text(json.dumps(manifest, indent=2) + '\n', 'utf-8')
print('Pinned public music catalog:', len(outputs), 'outputs; original unit tests preserved, execution pending.')
