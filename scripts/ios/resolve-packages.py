"""Resolve pinned packages, recovering one interrupted SwiftPM artifact cache."""
from pathlib import Path
import shutil
import subprocess
import sys


def main() -> int:
    if sys.platform != "darwin":
        raise RuntimeError("Package resolution requires the Apple build host")
    root = Path(__file__).resolve().parents[2]
    packages = root / "ios/build/SourcePackages"
    logs = root / "ios/build/logs"
    logs.mkdir(parents=True, exist_ok=True)
    command = ["xcodebuild", "-resolvePackageDependencies", "-project", "ios/Harbor.xcodeproj",
               "-scheme", "Harbor", "-clonedSourcePackagesDirPath", str(packages)]
    for attempt in range(2):
        lines = []
        with (logs / f"packages-{attempt + 1}.log").open("w", encoding="utf-8") as log:
            process = subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True)
            for line in process.stdout:
                print(line, end="", flush=True)
                log.write(line)
                lines.append(line)
            status = process.wait()
        if status == 0:
            return 0
        output = "".join(lines)
        collision = "failed downloading" in output and "already exists in file system" in output
        if attempt != 0 or not collision:
            return status
        # Only artifact caches are disposable. Keep checkouts, version pins and
        # normal checksum verification; never derive deletion paths from logs.
        candidates = [Path.home() / "Library/Caches/org.swift.swiftpm/artifacts",
                      packages / "artifacts"]
        for cache in candidates:
            if cache.is_symlink():
                raise RuntimeError("Refusing a redirected package artifact cache")
            if cache.exists():
                shutil.rmtree(cache)
        print("Retrying pinned dependencies after clearing interrupted artifact caches.", flush=True)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
