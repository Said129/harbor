"""One native build and an explicit affected-only selection; no full-suite fallback."""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import threading
import time

root = Path(__file__).resolve().parents[2]
os.chdir(root)
build = root / "ios/build"
logs = build / "logs"
logs.mkdir(parents=True, exist_ok=True)
selected = os.environ["HARBOR_FOCUSED_SELECTION"].split(",")
assert selected and all(re.fullmatch(r"Harbor(?:Changed)?Tests/[A-Za-z0-9_]+/test[A-Za-z0-9_]+", name) for name in selected)
assert len(selected) == len(set(selected))
modules = {name.split("/")[0] for name in selected}
assert len(modules) == 1
module = modules.pop()
scheme = "HarborFocused" if module == "HarborChangedTests" else "Harbor"
report = {"source": os.environ["GITHUB_SHA"], "selected": selected, "complete": False, "package_requested": os.environ.get("INPUT_PACKAGE") == "true"}
report["runtime_candidate"] = os.environ.get("HARBOR_MUSIC_RUNTIME_CANDIDATE") == "true"
target = build / "focused-results.json"


def save(phase):
    report["phase"] = phase
    target.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


def run(command, name, timeout=1500, allow_failure=False):
    save(name)
    print("Native phase:", name, flush=True)
    finished = threading.Event()

    def resources():
        with (logs / (name + "-resources.log")).open("w", encoding="utf-8") as stats:
            while not finished.is_set():
                stats.write(f"monotonic_seconds={time.monotonic():.1f}\n")
                try:
                    result = subprocess.run(["ps", "-axo", "pid,ppid,%cpu,rss,comm"], capture_output=True, text=True, timeout=10)
                    lines = result.stdout.splitlines()
                    rows = sorted(lines[1:], key=lambda line: int(line.split(None, 4)[3]), reverse=True)
                    stats.write("\n".join([lines[0], *rows[:12]]) + "\n")
                    memory = subprocess.run(["vm_stat"], capture_output=True, text=True, timeout=10)
                    stats.write(memory.stdout + "\n"); stats.flush()
                except (OSError, ValueError, IndexError, subprocess.TimeoutExpired):
                    stats.write("Resource sample unavailable\n"); stats.flush()
                if finished.wait(60):
                    return

    sampler = threading.Thread(target=resources, daemon=True)
    sampler.start()
    try:
        with (logs / (name + ".log")).open("w", encoding="utf-8") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, text=True, start_new_session=True)
            try:
                status = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                # Stop the actual compiler group too; killing xcodebuild alone
                # leaves expensive frontend children running during cleanup.
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait(timeout=30)
                report["timed_out_phase"] = name
                save(name + "-timeout")
                status = 124
    finally:
        finished.set()
        sampler.join(timeout=25)
    if status:
        print((logs / (name + ".log")).read_text(encoding="utf-8", errors="replace")[-25000:], flush=True)
        if not allow_failure:
            raise SystemExit(status)
    return status


devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))
device = next(d["udid"] for runtime, values in devices["devices"].items() if "iOS" in runtime for d in values if d["name"].startswith("iPhone"))
os.environ["IOS_SIMULATOR"] = device
os.environ["IOS_SIMULATOR_ARCH"] = os.uname().machine
subprocess.run(["python3", "scripts/ios/prepare-simulator-webkit.py"], check=True)
command = ["xcodebuild", "-project", "ios/Harbor.xcodeproj", "-scheme", scheme, "-configuration", "Debug",
           "-destination", f"platform=iOS Simulator,id={device},arch={os.uname().machine}",
           "-derivedDataPath", "ios/build/DerivedData", "-clonedSourcePackagesDirPath", "ios/build/SourcePackages",
           "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-"]
selection = ["-only-testing:" + name for name in selected]
subprocess.run(["python3", "scripts/ios/reuse-native-source-times.py"], check=True)
run(command + selection + ["build-for-testing"], "focused-build", timeout=2700)
# The resource trace showed simulator services competing with the compiler.
# Build for the selected device first; launch it only for actual execution.
subprocess.run(["python3", "scripts/ios/prepare-ci-audio.py", "--verify"], check=True)
subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], check=True, timeout=300)
report["simulator_boot_after_build"] = True
app = build / "DerivedData/Build/Products/Debug-iphonesimulator/Harbor.app"
subprocess.run(["xcrun", "simctl", "install", device, str(app)], check=True, timeout=90)
container = subprocess.check_output(["xcrun", "simctl", "get_app_container", device, "site.harbor.iphone", "data"], text=True).strip()
subprocess.run(["python3", "scripts/ios/prepare-model-test-startup.py", "--container", container], check=True)
test_status = run(command + selection + ["-resultBundlePath", "ios/build/FocusedTests.xcresult", "test-without-building"], "focused-tests", allow_failure=True)
text = (logs / "focused-tests.log").read_text(encoding="utf-8", errors="replace")
rows = re.findall(r"Test Case '-\[" + re.escape(module) + r"\.([A-Za-z0-9_]+) ([A-Za-z0-9_]+)\]' (passed|failed|skipped)", text)
completed = [module + "/" + group + "/" + method for group, method, status in rows if status == "passed"]
report["passed"] = completed
report["rows"] = rows
report["test_exit_code"] = test_status
report["complete"] = test_status == 0 and sorted(completed) == sorted(selected) and len(rows) == len(selected) and "Restarting after" not in text
save("finished")
if (build / "FocusedTests.xcresult").exists():
    export = subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", "ios/build/FocusedTests.xcresult", "--output-path", "ios/build/focused-attachments"], check=False)
    report["attachments_export_exit_code"] = export.returncode
    save("finished")
    assert export.returncode == 0, "Preserve original results; attachment export failed"
assert report["complete"], "Selected native executions were incomplete; inspect original log"
print(json.dumps(report), flush=True)
