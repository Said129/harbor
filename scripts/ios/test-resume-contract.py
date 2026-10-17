"""Offline differential test: actual Desktop resume.ts versus the host Rust C ABI.

Build harbor-ios-bridge first. Node with native TypeScript support is required.
The in-memory localStorage adapter exists only in this test, not in the app.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path)
    args = parser.parse_args()
    module_spec = importlib.util.spec_from_file_location("live_bridge", ROOT / "scripts/ios/integration-live.py")
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    filename = {"win32": "harbor_ios_bridge.dll", "darwin": "libharbor_ios_bridge.dylib"}.get(sys.platform, "libharbor_ios_bridge.so")
    core = module.Bridge(args.library or ROOT / "harbor-ios-bridge/target/debug" / filename)
    cases = [dict(id="tt123", ms=ms, **coordinates) for coordinates in [{}, {"season": 0, "episode": 1}, {"season": 1, "episode": 2}, {"season": 2, "episode": 1}] for ms in [1, 4999, 5000, 5001, 30000, 30001, 120000]]
    script = """
        const input = [];
        for await (const chunk of process.stdin) input.push(chunk);
        const cases = JSON.parse(Buffer.concat(input).toString());
        let saved = new Map();
        globalThis.localStorage = {
            getItem: key => saved.get(key) ?? null,
            setItem: (key, value) => saved.set(key, value)
        };
        const desktop = await import('./src/lib/resume.ts');
        const results = cases.map(c => {
            saved = new Map();
            desktop.saveResumeMs(c.id, c.ms, c.season, c.episode);
            return { entries: JSON.parse(saved.get('harbor.resume')), ms: desktop.readResumeMs(c.id, c.season, c.episode) };
        });
        process.stdout.write(JSON.stringify(results));
    """
    result = subprocess.run(["node", "--input-type=module", "-e", script], input=json.dumps(cases), text=True, capture_output=True, cwd=ROOT, check=True)
    desktop = json.loads(result.stdout)
    for case, expected in zip(cases, desktop, strict=True):
        target = {key: case[key] for key in ["id", "season", "episode"] if key in case}
        record = core.call("resumeCheckpoint", target=target, positionMs=case["ms"], durationMs=0, timestampMs=1, exiting=True)["checkpoint"]
        assert record["key"] in expected["entries"], "desktop-key-mismatch"
        assert record["entry"]["ms"] == expected["ms"], "desktop-position-mismatch"
        plan = core.call("resumePosition", target=target, document=dict(version=1, entries=expected["entries"]), durationMs=0, playback=True, prompt=True)
        # These boundaries come from use-bridge-load.ts, not resume.ts itself.
        assert plan["ms"] == (expected["ms"] if expected["ms"] > 5000 else 0), "start-threshold-mismatch"
        assert plan["prompt"] == (expected["ms"] > 30000), "prompt-threshold-mismatch"
    print(f"PASS: {len(cases)} Desktop/Rust resume contracts through the real C ABI; no network")


if __name__ == "__main__":
    main()
