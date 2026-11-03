"""Retain compiler-cache input timestamps only when the actual bytes match."""
import hashlib
import json
import os
from pathlib import Path
import re

INPUTS = ["ios/Harbor", "ios/HarborTests", "ios/Harbor.xcodeproj", "ios/Frameworks", "ios/MPVKitMusic"]
MANIFEST = "ios/build/DerivedData/Build/Intermediates.noindex/harbor-source-times.json"


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def prepare(root):
    root = root.resolve()
    target = root / MANIFEST
    assert target.resolve().is_relative_to(root) and not target.is_symlink()
    previous = {}
    if target.is_file() and target.stat().st_size <= 4 * 1024 * 1024:
        try:
            value = json.loads(target.read_text("utf-8"))
            if value.get("schema") == 1 and isinstance(value.get("files"), dict):
                previous = value["files"]
        except (OSError, ValueError, AttributeError):
            pass
    current, restored = {}, 0
    for relative in INPUTS:
        folder = root / relative
        assert folder.resolve().is_relative_to(root) and not folder.is_symlink()
        for path in sorted(folder.rglob("*")):
            if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(folder.resolve()):
                continue
            key = path.relative_to(root).as_posix()
            fingerprint, stat = digest(path), path.stat()
            saved = previous.get(key)
            if (isinstance(saved, dict) and saved.get("sha256") == fingerprint
                    and isinstance(saved.get("mtime_ns"), int) and not isinstance(saved["mtime_ns"], bool)
                    and 0 < saved["mtime_ns"] < 9_000_000_000_000_000_000
                    and re.fullmatch("[0-9a-f]{64}", saved["sha256"])):
                if stat.st_mtime_ns != saved["mtime_ns"]:
                    os.utime(path, ns=(stat.st_atime_ns, saved["mtime_ns"]))
                    restored += 1
            current[key] = {"sha256": fingerprint, "mtime_ns": path.stat().st_mtime_ns}
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({"schema": 1, "files": current}, separators=(",", ":")) + "\n", "utf-8")
    return {"inputs": len(current), "unchanged_timestamps_restored": restored, "content_verification": "sha256"}


if __name__ == "__main__":
    assert os.environ.get("GITHUB_ACTIONS") == "true", "Only adjust timestamps in the isolated CI checkout"
    print(json.dumps(prepare(Path(__file__).resolve().parents[2])))
