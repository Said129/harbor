"""Keep a verified unsigned device IPA in a reviewable GitHub draft Release."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--validation-scope", choices=["full", "affected"], default="full")
    args = parser.parse_args()
    report = json.loads(args.report.read_text(encoding="utf-8"))
    with args.ipa.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    if not (
        report["commit"] == args.commit
        and report["signed"] is False
        and report["platform"] == "iPhoneOS"
        and report["deviceFamily"] == [1]
        and report["architecture"] == "arm64"
        and report["sha256"] == digest
        and report["bytes"] == args.ipa.stat().st_size
        and 0 < report["bytes"] < 2 * 1024**3
    ):
        raise SystemExit("Device build report does not match the IPA")
    tag = f"iphone-unsigned-{args.commit[:12]}"
    assets = [str(args.ipa), str(args.report)]
    if args.evidence:
        if not 0 < args.evidence.stat().st_size < 2 * 1024**3:
            raise SystemExit("Invalid evidence archive size")
        assets.append(str(args.evidence))
    # A rerun must not replace an existing review artifact silently.
    existing = subprocess.run(["gh", "release", "view", tag, "--repo", args.repo], capture_output=True, text=True)
    if existing.returncode == 0:
        raise SystemExit(f"Draft build tag already exists: {tag}; review the existing asset before replacing it")
    validation = (
        "Only the browser-dialog close and custom-palette Cancel regressions were rerun on the simulator. "
        "The full native, public-service and UI suites were not rerun for this candidate. "
        if args.validation_scope == "affected" else
        "Simulator service/UI tests pass before this workflow stage. "
    )
    notes = (
        "Native iPhone development build, unsigned. This draft preserves the output for owner review and local signing.\n\n"
        f"Commit: `{args.commit}`\n\n"
        f"SHA-256: `{digest}`\n\n"
        "Requires iOS 17 or later and valid signing before installation. No certificate or provisioning profile is included. "
        f"{validation}Opening the player does not certify physical video/audio playback. "
        "Essential mobile journeys and started native features remain in progress; "
        "the complete Desktop inventory is a reference under docs/ios/MOBILE_SCOPE.md.\n"
    )
    with tempfile.TemporaryDirectory(prefix="harbor-draft-") as temporary:
        body = Path(temporary) / "notes.md"
        body.write_text(notes, encoding="utf-8")
        subprocess.run([
            "gh", "release", "create", tag,
            *assets,
            "--repo", args.repo, "--target", args.commit,
            "--draft", "--prerelease",
            "--title", f"Harbor iPhone unsigned {args.commit[:12]}",
            "--notes-file", str(body),
        ], check=True)


if __name__ == "__main__":
    main()
