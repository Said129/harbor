"""Package the C ABI as an embedded framework with an isolated Rust runtime."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
INSTALL_NAME = "@rpath/HarborCore.framework/HarborCore"
EXPORTS = {"_harbor_ios_abi_version", "_harbor_ios_call", "_harbor_ios_response_free"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--framework", type=Path, required=True)
    parser.add_argument("--platform", choices=["iPhoneOS", "iPhoneSimulator"], required=True)
    args = parser.parse_args()
    architectures = ["arm64"] if args.platform == "iPhoneOS" else ["arm64", "x86_64"]
    # Validate every slice before exposing it to Xcode. Runtime symbols must stay
    # private: MPVKit's Libdovi also includes Rust, with a different toolchain.
    for architecture in architectures:
        symbols = subprocess.check_output(["xcrun", "nm", "-arch", architecture, "-gUj", str(args.binary)], text=True)
        if set(symbols.splitlines()) != EXPORTS:
            raise SystemExit(f"Unexpected HarborCore exports for {architecture}")
        names = subprocess.check_output(["xcrun", "otool", "-arch", architecture, "-D", str(args.binary)], text=True)
        if INSTALL_NAME not in {line.strip() for line in names.splitlines()}:
            raise SystemExit(f"Unexpected HarborCore install name for {architecture}")
    (args.framework / "Headers").mkdir(parents=True, exist_ok=True)
    (args.framework / "Modules").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args.binary, args.framework / "HarborCore")
    shutil.copyfile(ROOT / "harbor-ios-bridge/include/harbor_ios.h", args.framework / "Headers/harbor_ios.h")
    (args.framework / "Modules/module.modulemap").write_text('framework module HarborCore {\n    umbrella header "harbor_ios.h"\n    export *\n}\n', encoding="utf-8")
    info = {
        "CFBundleIdentifier": "site.harbor.iphone.core",
        "CFBundleName": "HarborCore",
        "CFBundleExecutable": "HarborCore",
        "CFBundlePackageType": "FMWK",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "1",
        "CFBundleSupportedPlatforms": [args.platform],
        "MinimumOSVersion": "17.0",
    }
    (args.framework / "Info.plist").write_bytes(plistlib.dumps(info))
    print(f"HarborCore {args.platform}: {','.join(architectures)}; ABI exports and install name verified")


if __name__ == "__main__":
    main()
