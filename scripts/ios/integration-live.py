"""Opt-in network integration of the real C ABI and public Stremio services.

Build harbor-ios-bridge on the host first. No network is used by unit tests.
The official static addon is installed only within this test, never in the app.
Only counts/status are printed; payloads and playback URLs are never logged.
"""
import argparse
import ctypes
import json
import os
from pathlib import Path
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
LIMIT = 8 * 1024 * 1024
CINEMETA = "https://v3-cinemeta.strem.io/manifest.json"
STATIC_ADDON = "https://raw.githubusercontent.com/Stremio/stremio-static-addon-example/master/manifest.json"


class Failure(Exception):
    pass


class Bridge:
    def __init__(self, path):
        self.library = ctypes.CDLL(str(path))
        self.library.harbor_ios_abi_version.restype = ctypes.c_uint32
        self.library.harbor_ios_call.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        # Keep the pointer so Rust, rather than ctypes, owns and frees it.
        self.library.harbor_ios_call.restype = ctypes.c_void_p
        self.library.harbor_ios_response_free.argtypes = [ctypes.c_void_p]
        if self.library.harbor_ios_abi_version() != 1:
            raise Failure("abi-version")

    def call(self, operation, **fields):
        payload = json.dumps(dict(operation=operation, **fields)).encode()
        buffer = ctypes.create_string_buffer(payload)
        pointer = self.library.harbor_ios_call(buffer, len(payload))
        if not pointer:
            raise Failure("core-no-response")
        try:
            response = json.loads(ctypes.string_at(pointer))
        finally:
            self.library.harbor_ios_response_free(pointer)
        if not response.get("ok"):
            raise Failure(response.get("error", {}).get("code", "core-error"))
        return response["data"]


def get_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Harbor-iOS-Integration/0.1", "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read(LIMIT + 1)
        if len(data) > LIMIT:
            raise Failure("response-too-large")
        return json.loads(data)


def require(value, code):
    if not value:
        raise Failure(code)


def install(core, url):
    normalized = core.call("normalizeAddon", url=url)["url"]
    return core.call("installAddon", url=normalized, manifest=get_json(normalized))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path)
    parser.add_argument("--probe-media", action="store_true", help="Require an actual 206 response from the returned media URL. The old official example's video host may be unavailable.")
    args = parser.parse_args()
    filename = {"win32": "harbor_ios_bridge.dll", "darwin": "libharbor_ios_bridge.dylib"}.get(sys.platform, "libharbor_ios_bridge.so")
    core = Bridge(args.library or ROOT / "harbor-ios-bridge/target/debug" / filename)

    cinemeta = install(core, CINEMETA)
    catalogs = core.call("catalogs", addons=[cinemeta])
    require(catalogs, "no-cinemeta-catalogs")
    metas = get_json(catalogs[0]["url"])["metas"]
    require(metas, "empty-cinemeta-catalog")
    search = core.call("catalogs", addons=[cinemeta], search="Big Buck Bunny")
    require(search, "no-search-plans")
    search_count = sum(len(get_json(plan["url"])["metas"]) for plan in search)
    require(search_count, "empty-real-search")
    plans = core.call("resources", addons=[cinemeta], resource="meta", kind=metas[0]["type"], id=metas[0]["id"])
    require(get_json(plans[0]["url"]).get("meta"), "missing-cinemeta-meta")

    addon = install(core, os.environ.get("HARBOR_IOS_TEST_ADDON", STATIC_ADDON))
    plan = core.call("catalogs", addons=[addon])[0]
    media = get_json(plan["url"])["metas"][0]
    meta_plan = core.call("resources", addons=[addon], resource="meta", kind=media["type"], id=media["id"])[0]
    metadata = get_json(meta_plan["url"])["meta"]
    stream_plan = core.call("resources", addons=[addon], resource="stream", kind=media["type"], id=media["id"])[0]
    streams = core.call("mapStreams", plan=stream_plan, response=get_json(stream_plan["url"]))
    ranked = core.call("rank", streams=streams, trust={"kind": media["type"], "expectedTitle": metadata["name"]}, score={"mediaKind": media["type"]})
    offers = ranked["picker"]["all"]
    require(offers, "no-ranked-public-streams")
    source = core.call("resolveDirect", stream=offers[0])
    summary = {"ok": True, "cinemetaCatalogs": len(catalogs), "catalogItems": len(metas), "searchItems": search_count, "publicStreams": len(offers), "mediaProbe": "not-requested"}
    if not args.probe_media:
        print(json.dumps(summary))
        return
    headers = dict(source.get("headers") or {})
    headers.setdefault("User-Agent", "Harbor-iOS-Integration/0.1")
    headers["Range"] = "bytes=0-1023"
    # A bounded range probe verifies media transport; no video file is saved.
    request = urllib.request.Request(source["url"], headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        status = response.status
        content_type = response.headers.get("Content-Type", "")
        require(response.read(1024), "empty-media-range")
        require(status == 206, "media-range-not-supported")
        require(response.headers.get("Content-Range", "").startswith("bytes 0-1023/"), "invalid-content-range")
    summary.update(mediaProbe="passed", mediaHTTPStatus=status, mediaType=content_type, rangeBytes=1024)
    print(json.dumps(summary))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # urllib exceptions can embed URLs. Never print their descriptions.
        print(json.dumps({"ok": False, "error": str(error) if isinstance(error, Failure) else type(error).__name__}))
        sys.exit(1)
