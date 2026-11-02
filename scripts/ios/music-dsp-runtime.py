"""Build the missing Desktop audio filters from the existing pinned MPVKit/FFmpeg sources."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import zipfile

SDK = "f82e06d4f5ef4fc4aa9faba3782a462dbbef870c"
FFMPEG = "bf1b838f2ab88b4f8fd83443325c782ea0e0f7fa"
FILTERS = ["aecho", "crossfeed", "bass", "treble", "lowpass", "highpass", "bandreject",
           "astats", "ametadata", "afade", "acrossfade", "asplit", "asetpts", "alimiter"]


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def git(folder, *arguments):
    return subprocess.check_output(["git", "-C", str(folder), *arguments], text=True).strip()


def prepare(sdk, output):
    assert git(sdk, "rev-parse", "HEAD") == SDK
    assert not git(sdk, "status", "--porcelain"), "Use a clean pinned SDK checkout"
    source = sdk / "Sources/BuildScripts/XCFrameworkBuild/main.swift"
    text = source.read_text(encoding="utf-8")
    original_hash = digest(source)
    assert 'return "n9.0.1"' in text
    assert text.count('"--disable-filters",') == 1
    # Build the same FFmpeg and dependency configuration. libmpv itself, its
    # subtitle decoder and the other shipped frameworks remain the pinned ones.
    for name in ["BuildUchardet", "BuildLuaJIT", "BuildMPV", "BuildSmbclient"]:
        call = f"    try {name}().buildALL()"
        assert text.count(call) == 1
        text = text.replace(call, "")
    options = ", ".join('"--enable-filter=' + name + '"' for name in FILTERS)
    text = text.replace('"--disable-filters",', '"--disable-filters",\n        ' + options + ',')
    source.write_text(text, encoding="utf-8", newline="\n")
    dist = sdk / "dist"
    dist.mkdir(exist_ok=True)
    ffmpeg = dist / "FFmpeg-n9.0.1"
    if not ffmpeg.exists():
        subprocess.run(["git", "init", str(ffmpeg)], check=True)
        subprocess.run(["git", "-C", str(ffmpeg), "remote", "add", "origin", "https://github.com/FFmpeg/FFmpeg.git"], check=True)
        subprocess.run(["git", "-C", str(ffmpeg), "fetch", "--depth=1", "origin", FFMPEG], check=True)
        subprocess.run(["git", "-C", str(ffmpeg), "checkout", "--detach", "FETCH_HEAD"], check=True)
    assert git(ffmpeg, "rev-parse", "HEAD") == FFMPEG
    assert not git(ffmpeg, "status", "--porcelain")
    output.mkdir(parents=True, exist_ok=True)
    plan = {"mpvkit": SDK, "ffmpeg": FFMPEG, "filters": FILTERS,
            "originalBuilderSha256": original_hash, "patchedBuilderSha256": digest(source)}
    (output / "prepare.json").write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
    (output / "mpvkit-changes.patch").write_text(git(sdk, "diff", "--", "Sources/BuildScripts/XCFrameworkBuild/main.swift") + "\n", encoding="utf-8")
    print("Pinned FFmpeg audio-filter build prepared; the application has not switched runtimes.", flush=True)


def collect(sdk, output):
    plan = json.loads((output / "prepare.json").read_text(encoding="utf-8"))
    source = sdk / "Sources/BuildScripts/XCFrameworkBuild/main.swift"
    assert plan["mpvkit"] == SDK and plan["ffmpeg"] == FFMPEG
    assert digest(source) == plan["patchedBuilderSha256"]
    checked = []
    for platform, arch in [("ios", "arm64"), ("isimulator", "arm64"), ("isimulator", "x86_64")]:
        config = sdk / f"dist/FFmpeg/{platform}/scratch/{arch}/config_components.h"
        content = config.read_text(encoding="utf-8")
        for name in FILTERS:
            assert re.search(r"^#define CONFIG_" + name.upper() + r"_FILTER 1$", content, re.M), (platform, arch, name)
        checked.append({"platform": platform, "architecture": arch, "configSha256": digest(config)})
    archive = sdk / "dist/release/Libavfilter.xcframework.zip"
    with zipfile.ZipFile(archive) as value:
        info = plistlib.loads(value.read("Libavfilter.xcframework/Info.plist"))
    libraries = info["AvailableLibraries"]
    device = [item for item in libraries if item["SupportedPlatform"] == "ios" and "SupportedPlatformVariant" not in item]
    simulator = [item for item in libraries if item["SupportedPlatform"] == "ios" and item.get("SupportedPlatformVariant") == "simulator"]
    assert len(device) == len(simulator) == 1
    assert set(device[0]["SupportedArchitectures"]) == {"arm64"}
    assert set(simulator[0]["SupportedArchitectures"]) == {"arm64", "x86_64"}
    shutil.copyfile(archive, output / archive.name)
    shutil.copyfile(sdk / "LICENSE", output / "MPVKit-LICENSE.txt")
    shutil.copyfile(sdk / "dist/FFmpeg-n9.0.1/LICENSE.md", output / "FFmpeg-LICENSE.md")
    (output / "ffmpeg-changes.patch").write_text(git(sdk / "dist/FFmpeg-n9.0.1", "diff") + "\n", encoding="utf-8")
    dependencies = [{"path": str(path.relative_to(sdk / "dist")), "sha256": digest(path)}
                    for path in sorted((sdk / "dist").glob("*/*.zip")) if path.parent.name != "release"]
    report = {**plan, "architectures": checked, "archiveSha256": digest(archive),
              "libraries": libraries, "downloadedDependencyArchives": dependencies,
              "applicationIntegrated": False, "nativeFilterExecutionValidated": False}
    (output / "runtime.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("All additional filter definitions and device/simulator slices verified. Native effect execution is still required.", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "collect"])
    parser.add_argument("--sdk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    (prepare if arguments.action == "prepare" else collect)(arguments.sdk.resolve(), arguments.output.resolve())
