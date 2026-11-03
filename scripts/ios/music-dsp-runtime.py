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

# The app's newer Package.swift still consumes the 1.0.0 binary release.
# Use that release's actual builder and verified 8.1.2 ABI, not its newer README.
SDK = "288527dffbc6d3e63cce147fc7b520c64a791603"
FFMPEG = "38b88335f99e76ed89ff3c93f877fdefce736c13"
FFMPEG_VERSION = "n8.1.2"
BASELINE_BINARY_HASHES = {"Libavfilter": "3e71af8633d99d365f14b88064bceafd57acb23fc64db90e55b715a9c0dca328",
                          "Libavutil": "5dc251c8807c501982edfb0bc9bddfee4148733142d6ebb947738c60fb3bf8d8"}
FILTERS = ["aecho", "crossfeed", "bass", "treble", "lowpass", "highpass", "bandreject",
           "astats", "ametadata", "afade", "acrossfade", "asplit", "asetpts", "alimiter",
           "bandpass", "asetnsamples", "anullsink"]


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
    assert 'return "' + FFMPEG_VERSION + '"' in text
    package = (sdk / "Package.swift").read_text(encoding="utf-8")
    for name, expected in BASELINE_BINARY_HASHES.items():
        assert re.search(r'name: "' + name + r'",\s*url: "[^"]+/1\.0\.0/' + name + r'\.xcframework\.zip",\s*checksum: "' + expected + '"', package)
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
    ffmpeg = dist / ("FFmpeg-" + FFMPEG_VERSION)
    if not ffmpeg.exists():
        subprocess.run(["git", "init", str(ffmpeg)], check=True)
        subprocess.run(["git", "-C", str(ffmpeg), "remote", "add", "origin", "https://github.com/FFmpeg/FFmpeg.git"], check=True)
        subprocess.run(["git", "-C", str(ffmpeg), "fetch", "--depth=1", "origin", FFMPEG], check=True)
        subprocess.run(["git", "-C", str(ffmpeg), "checkout", "--detach", "FETCH_HEAD"], check=True)
    assert git(ffmpeg, "rev-parse", "HEAD") == FFMPEG
    assert not git(ffmpeg, "status", "--porcelain")
    output.mkdir(parents=True, exist_ok=True)
    plan = {"mpvkit": SDK, "ffmpeg": FFMPEG, "ffmpegVersion": FFMPEG_VERSION, "filters": FILTERS,
            "baselineBinarySha256": BASELINE_BINARY_HASHES,
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
        filter_version = value.read("Libavfilter.xcframework/ios-arm64/Libavfilter.framework/Headers/version.h").decode()
        filter_major = value.read("Libavfilter.xcframework/ios-arm64/Libavfilter.framework/Headers/version_major.h").decode()
    assert re.search(r"#define LIBAVFILTER_VERSION_MAJOR\s+11\b", filter_major)
    assert re.search(r"#define LIBAVFILTER_VERSION_MINOR\s+14\b", filter_version)
    assert re.search(r"#define LIBAVFILTER_VERSION_MICRO\s+102\b", filter_version)
    util_version = (sdk / "dist/FFmpeg/ios/thin/arm64/include/libavutil/version.h").read_text(encoding="utf-8")
    for component, expected in [("MAJOR", 60), ("MINOR", 26), ("MICRO", 102)]:
        assert re.search(r"#define LIBAVUTIL_VERSION_" + component + r"\s+" + str(expected) + r"\b", util_version)
    libraries = info["AvailableLibraries"]
    device = [item for item in libraries if item["SupportedPlatform"] == "ios" and "SupportedPlatformVariant" not in item]
    simulator = [item for item in libraries if item["SupportedPlatform"] == "ios" and item.get("SupportedPlatformVariant") == "simulator"]
    assert len(device) == len(simulator) == 1
    assert set(device[0]["SupportedArchitectures"]) == {"arm64"}
    assert set(simulator[0]["SupportedArchitectures"]) == {"arm64", "x86_64"}
    shutil.copyfile(archive, output / archive.name)
    shutil.copyfile(sdk / "LICENSE", output / "MPVKit-LICENSE.txt")
    shutil.copyfile(sdk / ("dist/FFmpeg-" + FFMPEG_VERSION) / "LICENSE.md", output / "FFmpeg-LICENSE.md")
    (output / "ffmpeg-changes.patch").write_text(git(sdk / ("dist/FFmpeg-" + FFMPEG_VERSION), "diff") + "\n", encoding="utf-8")
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
