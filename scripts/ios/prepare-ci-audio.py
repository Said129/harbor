"""Provision an explicit CoreAudio device only in the disposable macOS CI host."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.request

VERSION = "0.7.1"
SHA256 = "57b540f27a3e29c37e310e01bee0fdfab76733087e47f997ef9dccf851400dcf"
URL = f"https://existential.audio/downloads/BlackHole2ch-{VERSION}.pkg"
root = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(verify=False):
    assert os.environ.get("GITHUB_ACTIONS") == "true" and os.uname().sysname == "Darwin"
    output = root / "ios/build"
    logs = output / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    helper = output / "ci-audio-route"
    source = root / "scripts/ios/ci-audio-route.c"
    proof_path = logs / "ci-audio-route.json"
    if verify:
        proof = json.loads(proof_path.read_text("utf-8"))
        assert proof["helperSHA256"] == digest(helper) and proof["sourceSHA256"] == digest(source)
    else:
        archive = Path(os.environ["RUNNER_TEMP"]) / f"Harbor-CI-BlackHole2ch-{VERSION}.pkg"
        request = urllib.request.Request(URL, headers={"User-Agent": "Harbor-CI-audio-validation/1.0",
                                                       "Accept": "application/octet-stream,*/*"})
        with urllib.request.urlopen(request, timeout=45) as response:
            data = response.read(16 * 1024 * 1024 + 1)
        assert len(data) <= 16 * 1024 * 1024 and hashlib.sha256(data).hexdigest() == SHA256
        archive.write_bytes(data)
        subprocess.run(["sudo", "installer", "-pkg", str(archive), "-target", "/"], check=True, timeout=120)
        # The official driver instructions restart this userspace service after installation.
        subprocess.run(["sudo", "killall", "coreaudiod"], check=False, timeout=15)
        subprocess.run(["xcrun", "clang", "-Wall", "-Wextra", "-Werror", str(source),
                        "-framework", "CoreAudio", "-framework", "CoreFoundation", "-o", str(helper)], check=True, timeout=90)
        proof = {"driverVersion": VERSION, "packageSHA256": SHA256, "packageURL": URL,
                 "sourceSHA256": digest(source), "helperSHA256": digest(helper),
                 "hostOnly": True, "libraryEmbeddedInApp": False}
    deadline = time.monotonic() + 45
    last_status = None
    while time.monotonic() < deadline:
        result = subprocess.run([str(helper)], capture_output=True, text=True, timeout=5)
        last_status = result.returncode
        if last_status == 0:
            proof["route"] = json.loads(result.stdout)
            proof_path.write_text(json.dumps(proof, indent=2) + "\n", "utf-8")
            print(json.dumps(proof), flush=True)
            return
        time.sleep(1)
    raise RuntimeError(f"Isolated CoreAudio device did not become ready; stage {last_status}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true")
    prepare(parser.parse_args().verify)
