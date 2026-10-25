"""Serve owned source documents, artwork and a Stremio catalog for fresh UI guests."""
import atexit
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import tempfile
import threading
from urllib.parse import urlsplit, unquote

def start(build):
    canonical = Path(build) / 'canonical'; canonical.mkdir(parents=True, exist_ok=True)
    build = Path(build).resolve()
    folder = tempfile.TemporaryDirectory(prefix='harbor-owned-sources-', dir=build); directory = Path(folder.name)
    base = 'http://127.0.0.1:18734'
    image = Path('ios/Harbor/Assets.xcassets/avatar-eboy_manga_eyes_bw_zoomed.imageset/avatar.png')
    for name in ['cover.png', 'edited.png']: shutil.copy2(image, directory / name)
    shutil.copy2('ios/HarborTests/Fixtures/owned-source-focus.gif', directory / 'focus.gif')
    manifest = dict(id='owned.source.catalog', name='Owned source catalog', version='1.0.0', types=['movie'], resources=['catalog'],
        catalogs=[dict(id='owned', type='movie', name='Owned catalog', extra=[dict(name='skip', isRequired=False)])])
    (directory / 'manifest.json').write_text(json.dumps(manifest), 'utf-8')
    catalog = directory / 'catalog/movie'; catalog.mkdir(parents=True)
    entries = [dict(id='owned-source-title-' + str(i), type='movie', name='Owned catalog title ' + str(i), poster=base + '/cover.png') for i in range(1, 5)]
    (catalog / 'owned.json').write_text(json.dumps(dict(metas=entries)), 'utf-8')
    (catalog / 'owned').mkdir()
    (catalog / 'owned/skip=4.json').write_text(json.dumps(dict(metas=[])), 'utf-8')
    row = dict(id='owned-imported-sources', title='Owned imported folders', future=dict(preserve='owned desktop field'), folders=[
        dict(id='owned-catalog', title='Owned catalog folder', tileShape='LANDSCAPE', coverImageUrl=base + '/cover.png', focusGifUrl=None,
            catalogSources=[dict(addonId='owned.source.catalog', type='movie', catalogId='owned')]),
        dict(id='owned-tmdb', title='Owned TMDB folder', tileShape='LANDSCAPE', coverImageUrl=base + '/cover.png', focusGifUrl=None,
            sources=[dict(provider='tmdb', mediaType='MOVIE', tmdbSourceType='DISCOVER', filters=dict(withGenres='16'))]),
        dict(id='owned-missing-addon', title='Owned missing addon folder', tileShape='LANDSCAPE', coverImageUrl=base + '/cover.png', focusGifUrl=None,
            catalogSources=[dict(addonId='owned.not.installed', type='movie', catalogId='owned')])])
    (directory / 'sources.json').write_text(json.dumps(row), 'utf-8')
    (directory / 'malformed.json').write_text('{"owned_source":', 'utf-8')
    requests, lock = [], threading.Lock()
    class Handler(SimpleHTTPRequestHandler):
        def do_GET(self):
            path = unquote(urlsplit(self.path).path)
            if path.startswith('/catalog/movie/owned'):
                payload = json.dumps(dict(metas=[] if 'skip=4' in path else entries)).encode()
                self.send_response(200); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(payload)))
                self.end_headers(); self.wfile.write(payload); return
            super().do_GET()
        def log_message(self, format, *args):
            with lock:
                requests.append(dict(path=urlsplit(self.path).path, status=str(args[1]) if len(args) > 1 else 'unknown'))
                (canonical / 'CustomSourceFixtureRequests.json').write_text(json.dumps(requests, indent=2) + '\n')
    server = ThreadingHTTPServer(('127.0.0.1', 18734), partial(Handler, directory=folder.name))
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    def close():
        server.shutdown(); server.server_close(); thread.join(timeout=5)
        assert directory.resolve().is_relative_to(build) and directory.name.startswith('harbor-owned-sources-')
        folder.cleanup()
    atexit.register(close)
    (canonical / 'CustomSourceFixtureServer.json').write_text(json.dumps(dict(bind='127.0.0.1', port=18734,
        owned_sources=True, real_catalog_requests=True, production_app_override=False), indent=2) + '\n')
    return close
