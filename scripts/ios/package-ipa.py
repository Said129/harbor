"""Validate and package a device build for later signing, without credentials."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def verify_arm64(binary):
    subprocess.run(["xcrun", "lipo", str(binary), "-verify_arch", "arm64"], check=True)


def linked_frameworks(binary):
    libraries = subprocess.check_output(["xcrun", "otool", "-L", str(binary)], text=True)
    return set(re.findall(r"@rpath/([^/\s]+\.framework)/", libraries))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--commit", default="unknown")
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    output = args.output.resolve()
    require(app.name == "Harbor.app" and app.is_dir(), "Expected Harbor.app device bundle")
    require(output.suffix == ".ipa" and app not in output.parents, "IPA output must be outside the app bundle")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == "site.harbor.iphone", "Unexpected app bundle identifier")
    require(info.get("UIDeviceFamily") == [1], f"This port must target iPhone only; declared family={info.get('UIDeviceFamily')}")
    require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "Simulator builds cannot be packaged as device IPA")
    require(info.get("CFBundleExecutable") == "Harbor", "Unexpected app executable")
    icon = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
    require(icon.get("CFBundleIconName") == "AppIcon", "Original Harbor app icon is not configured")
    require(bool(icon.get("CFBundleIconFiles")) and (app / "Assets.car").is_file(), "Compiled icon assets missing")
    require(not (app / "_CodeSignature").exists() and not (app / "embedded.mobileprovision").exists(), "Expected an unsigned build without provisioning")
    for entry in app.rglob("*"):
        if entry.is_symlink():
            require(entry.resolve().is_relative_to(app), "Bundle symlink points outside the app")
    verify_arm64(app / "Harbor")
    require((app / "Harbor").stat().st_mode & stat.S_IXUSR, "App executable permission missing")
    frameworks = list((app / "Frameworks").glob("*.framework"))
    require(any(framework.name == "HarborCore.framework" for framework in frameworks), "Embedded Rust framework missing")
    required = linked_frameworks(app / "Harbor") | {"HarborCore.framework"}
    binaries = {}
    resource_frameworks = set()
    for framework in frameworks:
        framework_info = plistlib.loads((framework / "Info.plist").read_bytes())
        executable = framework_info.get("CFBundleExecutable", "")
        require(executable and Path(executable).name == executable, "Invalid framework executable")
        binary = framework / executable
        if binary.is_file():
            verify_arm64(binary)
            binaries[framework.name] = binary
            required |= linked_frameworks(binary)
        else:
            # Xcode removes static executables after linking their code into
            # Harbor, retaining framework resources. Every dynamic dependency
            # must still have a real executable in the bundle.
            resource_frameworks.add(framework.name)
    require(required <= binaries.keys(), "A linked dynamic framework executable is missing")
    output.parent.mkdir(parents=True, exist_ok=True)
    # ditto retains Unix modes and framework symlinks required by a signing tool.
    # The archive contains Payload/Harbor.app; it has no certificate or profile.
    with tempfile.TemporaryDirectory(prefix="harbor-ipa-") as temporary:
        payload = Path(temporary) / "Payload"
        payload.mkdir()
        shutil.copytree(app, payload / app.name, symlinks=True)
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--keepParent", str(payload), str(output)], check=True)
    with zipfile.ZipFile(output) as archive:
        require(archive.testzip() is None, "IPA ZIP integrity check failed")
        require("Payload/Harbor.app/Harbor" in archive.namelist(), "IPA payload missing")
        require(all(name == "Payload/" or name.startswith("Payload/Harbor.app/") for name in archive.namelist()), "Unexpected IPA contents")
        executable = archive.getinfo("Payload/Harbor.app/Harbor")
        require(executable.external_attr >> 16 & stat.S_IXUSR, "IPA lost app executable permission")
    with output.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    report = {
        "commit": args.commit,
        "bundleIdentifier": info["CFBundleIdentifier"],
        "version": info["CFBundleShortVersionString"],
        "build": info["CFBundleVersion"],
        "platform": "iPhoneOS",
        "deviceFamily": [1],
        "architecture": "arm64",
        "signed": False,
        "frameworkCount": len(frameworks),
        "dynamicFrameworkCount": len(binaries),
        "resourceFrameworkCount": len(resource_frameworks),
        "bytes": output.stat().st_size,
        "sha256": digest,
    }
    output.with_suffix(".json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Unsigned IPA verified: arm64 iPhone; frameworks={len(frameworks)} bytes={report['bytes']} sha256={digest}")
    print("Installation requires separate valid signing; no paid service or credentials used.")


if __name__ == "__main__":
    main()
