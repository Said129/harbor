"""Prepare the verified FFmpeg audio-filter candidate without changing the default project."""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import zipfile

root = Path(__file__).resolve().parents[2]
component = root / "ios/AudioRuntime"
package = root / "ios/MPVKitMusic"
expected = "b3d8406c8ebf61018709e18fac526e13910e032b870ff9fe35ac4a1ef2f6934a"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


inputs = json.loads((component / "package-inputs.json").read_text("utf-8"))
assert inputs["componentSHA256"] == expected
assert digest(component / "Libavfilter.xcframework.zip") == expected
assert digest(package / "Package.swift") == inputs["candidatePackageSHA256"]
for relative, expected_hash in inputs["packageShims"].items():
    path = (package / relative).resolve()
    assert path.is_relative_to(package.resolve()) and not path.is_symlink()
    assert digest(path) == expected_hash
for relative, expected_hash in inputs["licenseSHA256"].items():
    path = (component / relative).resolve()
    assert path.is_relative_to(component.resolve()) and not path.is_symlink()
    assert digest(path) == expected_hash
output = package / "Libavfilter.xcframework"
assert not output.is_symlink()
with zipfile.ZipFile(component / "Libavfilter.xcframework.zip") as archive:
    entries = [entry for entry in archive.infolist() if not entry.is_dir()]
    assert entries
    for entry in entries:
        assert "\\" not in entry.filename
        assert entry.filename.startswith("Libavfilter.xcframework/")
        assert (entry.external_attr >> 16) & 0o170000 != 0o120000
        target = (package / entry.filename).resolve()
        assert target.is_relative_to(output.resolve())
        data = archive.read(entry)
        if target.exists():
            assert target.is_file() and not target.is_symlink()
            assert target.read_bytes() == data, "A generated runtime file was changed"
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)

info = plistlib.loads((output / "Info.plist").read_bytes())
slices = info["AvailableLibraries"]
assert {(item["SupportedPlatform"], item.get("SupportedPlatformVariant"), tuple(item["SupportedArchitectures"])) for item in slices} == {
    ("ios", None, ("arm64",)),
    ("ios", "simulator", ("arm64", "x86_64")),
}
headers = output / "ios-arm64/Libavfilter.framework/Headers"
for file, name, version in [
    ("version_major.h", "LIBAVFILTER_VERSION_MAJOR", 11),
    ("version.h", "LIBAVFILTER_VERSION_MINOR", 14),
    ("version.h", "LIBAVFILTER_VERSION_MICRO", 102),
]:
    assert re.search(r"#define " + name + r"\s+" + str(version) + r"\b", (headers / file).read_text())

original = (root / "ios/project.yml").read_text("utf-8")
anchor = (
    "  MPVKit:\n"
    "    url: https://github.com/mpvkit/MPVKit.git\n"
    "    revision: f82e06d4f5ef4fc4aa9faba3782a462dbbef870c"
)
assert original.count(anchor) == 1
candidate = original.replace(anchor, "  MPVKit:\n    path: MPVKitMusic")
generated = root / "ios/project.music-runtime.generated.yml"
generated.write_text(candidate, "utf-8", newline="\n")
logs = root / "ios/build/logs"
logs.mkdir(parents=True, exist_ok=True)
(logs / "music-runtime-candidate.json").write_text(json.dumps({
    **inputs,
    "preparedArchiveSHA256": digest(component / "Libavfilter.xcframework.zip"),
    "generatedSpecSHA256": hashlib.sha256(candidate.encode()).hexdigest(),
    "runtimeCandidateSelected": True,
    "applicationDefaultChanged": False,
    "currentRunExecutionValidated": False,
}, indent=2) + "\n", "utf-8")
print("Verified device/simulator filter candidate prepared; default project unchanged.")
