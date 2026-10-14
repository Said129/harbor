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
    parser.add_argument("--validation-scope", choices=["full", "affected", "sources-search-subtitles", "mobile-sources-subtitles"], default="full")
    parser.add_argument("--native-selection", default="")
    parser.add_argument("--previous-runs", default="")
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
    reserved = args.validation_scope in ["sources-search-subtitles", "mobile-sources-subtitles"] and existing.returncode == 0
    if existing.returncode == 0 and not reserved:
        raise SystemExit(f"Draft build tag already exists: {tag}; review the existing asset before replacing it")
    if reserved:
        detail = json.loads(subprocess.check_output(["gh", "release", "view", tag, "--repo", args.repo, "--json", "isDraft,targetCommitish,assets"], text=True))
        if not detail["isDraft"] or detail["targetCommitish"] != args.commit or any(a["name"].endswith((".ipa", ".zip")) for a in detail["assets"]):
            raise SystemExit("Reserved draft identity or immutable delivery assets do not match")
    validation = (
        "Only the browser-dialog close and custom-palette Cancel regressions were rerun on the simulator. "
        "The full native, public-service and UI suites were not rerun for this candidate. "
        if args.validation_scope == "affected" else
        "Affected native source/search/account/subtitle tests, live Danmachi identity mapping, and content-only search/history UI pass. "
        "Unchanged features retain the accepted build 86 validation; the full suite was not repeated. "
        if args.validation_scope == "sources-search-subtitles" else
        "Simulator service/UI tests pass before this workflow stage. "
    )
    if args.validation_scope == "sources-search-subtitles" and args.native_selection:
        if not args.previous_runs:
            raise SystemExit("A focused follow-up must identify its preserved feature validation")
        validation = (
            f"Native follow-up cases passed: {args.native_selection}. "
            f"Accepted unchanged native cases are preserved from completed run(s) {args.previous_runs}. "
            "Live Danmachi mapping and content-only search/recent-history UI pass in this run. "
            "Unchanged features retain build 86 validation; the full suite was not repeated. "
        )
    notes = (
        "Native iPhone development build, unsigned. This draft preserves the output for owner review and local signing.\n\n"
        f"Commit: `{args.commit}`\n\n"
        f"SHA-256: `{digest}`\n\n"
        "Requires iOS 17 or later and valid signing before installation. No certificate or provisioning profile is included. "
        f"{validation}Opening the player does not certify physical video/audio playback. "
        "The Desktop inventory and documented platform limits remain under docs/ios/MOBILE_SCOPE.md.\n"
    )
    if args.validation_scope == "mobile-sources-subtitles":
        if not args.native_selection or not args.previous_runs:
            raise SystemExit("Mobile follow-up must identify its selected tests and preserved validation")
        notes = (
            "Native iPhone 88, unsigned. Direct source list with quality/provider filters; installed subtitle addon discovery and on-demand subtitle loading.\n\n"
            f"Commit: `{args.commit}`\n\nSHA-256: `{digest}`\n\n"
            f"Affected native cases: {args.native_selection}. Actual public subtitle queries tested for movie, series and mapped anime. "
            f"Accepted unchanged validation is preserved from {args.previous_runs}; the full suite was not repeated. "
            "Native view attachments are layout evidence with clearly identified test data. Requires iOS 17 or later and valid signing before installation. "
            "No account session, signing certificate or provisioning profile is included. Physical-device validation remains with the owner."
        )
    with tempfile.TemporaryDirectory(prefix="harbor-draft-") as temporary:
        body = Path(temporary) / "notes.md"
        body.write_text(notes, encoding="utf-8")
        if reserved:
            subprocess.run(["gh", "release", "upload", tag, *assets, "--repo", args.repo], check=True)
            title = "Harbor iPhone 88 — unsigned reviewed candidate" if args.validation_scope == "mobile-sources-subtitles" else "Harbor iPhone 87 — unsigned reviewed candidate"
            subprocess.run(["gh", "release", "edit", tag, "--repo", args.repo, "--title", title, "--notes-file", str(body)], check=True)
            return
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
