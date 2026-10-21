"""Serve one owned repository image over loopback for ordinary reading UI tests."""
import atexit
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import tempfile
import threading


def start(build):
    build = Path(build); canonical = build / 'canonical'; canonical.mkdir(parents=True, exist_ok=True)
    folder = tempfile.TemporaryDirectory(prefix='harbor-owned-reading-')
    source = Path('ios/Harbor/Assets.xcassets/avatar-eboy_manga_eyes_bw_zoomed.imageset/avatar.png')
    assert source.is_file() and source.stat().st_size <= 8 * 1024 * 1024
    shutil.copy2(source, Path(folder.name) / 'page.png')
    requests = []
    log_lock = threading.Lock()

    class Handler(SimpleHTTPRequestHandler):
        def log_message(self, format, *args):
            with log_lock:
                requests.append(dict(path=self.path, status=str(args[1]) if len(args) > 1 else 'unknown'))
                (canonical / 'ReadingFixtureRequests.json').write_text(json.dumps(requests, indent=2) + '\n')

    # A collision fails setup; never silently use an unrelated server.
    server = ThreadingHTTPServer(('127.0.0.1', 18734), partial(Handler, directory=folder.name))
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()

    def close():
        server.shutdown(); server.server_close(); thread.join(timeout=5); folder.cleanup()

    atexit.register(close)
    (canonical / 'ReadingFixtureServer.json').write_text(json.dumps(dict(bind='127.0.0.1', port=18734,
        fixture=str(source), only_owned_image=True, production_app_override=False), indent=2) + '\n')
    return close
