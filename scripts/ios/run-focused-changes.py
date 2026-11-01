"""One native build and an explicit affected-only selection; no full-suite fallback."""
import json
import os
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[2]
os.chdir(root)
build = root / "ios/build"
logs = build / "logs"
logs.mkdir(parents=True, exist_ok=True)
selected = os.environ["HARBOR_FOCUSED_SELECTION"].split(",")
assert selected and all(re.fullmatch(r"HarborTests/[A-Za-z0-9_]+/test[A-Za-z0-9_]+", name) for name in selected)
assert len(selected) == len(set(selected))
report = {"source": os.environ["GITHUB_SHA"], "selected": selected, "complete": False, "package_requested": os.environ.get("INPUT_PACKAGE") == "true"}
target = build / "focused-results.json"


def save(phase):
    report["phase"] = phase
    target.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


def run(command, name, timeout=1500):
    save(name)
    print("Native phase:", name, flush=True)
    with (logs / (name + ".log")).open("w", encoding="utf-8") as output:
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, text=True, timeout=timeout)
    if result.returncode:
        print((logs / (name + ".log")).read_text(encoding="utf-8", errors="replace")[-25000:], flush=True)
        raise SystemExit(result.returncode)


devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))
device = next(d["udid"] for runtime, values in devices["devices"].items() if "iOS" in runtime for d in values if d["name"].startswith("iPhone"))
os.environ["IOS_SIMULATOR"] = device
os.environ["IOS_SIMULATOR_ARCH"] = os.uname().machine
subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], check=True, timeout=300)
subprocess.run(["python3", "scripts/ios/prepare-simulator-webkit.py"], check=True)
command = ["xcodebuild", "-project", "ios/Harbor.xcodeproj", "-scheme", "Harbor", "-configuration", "Debug",
           "-destination", f"platform=iOS Simulator,id={device},arch={os.uname().machine}",
           "-derivedDataPath", "ios/build/DerivedData", "-clonedSourcePackagesDirPath", "ios/build/SourcePackages",
           "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-"]
selection = ["-only-testing:" + name for name in selected]
run(command + selection + ["build-for-testing"], "focused-build")
app = build / "DerivedData/Build/Products/Debug-iphonesimulator/Harbor.app"
subprocess.run(["xcrun", "simctl", "install", device, str(app)], check=True, timeout=90)
container = subprocess.check_output(["xcrun", "simctl", "get_app_container", device, "site.harbor.iphone", "data"], text=True).strip()
subprocess.run(["python3", "scripts/ios/prepare-model-test-startup.py", "--container", container], check=True)
run(command + selection + ["-resultBundlePath", "ios/build/FocusedTests.xcresult", "test-without-building"], "focused-tests")
text = (logs / "focused-tests.log").read_text(encoding="utf-8", errors="replace")
rows = re.findall(r"Test Case '-\[HarborTests\.([A-Za-z0-9_]+) ([A-Za-z0-9_]+)\]' (passed|failed|skipped)", text)
completed = ["HarborTests/" + group + "/" + method for group, method, status in rows if status == "passed"]
report["passed"] = completed
report["rows"] = rows
report["complete"] = sorted(completed) == sorted(selected) and len(rows) == len(selected) and "Restarting after" not in text
save("finished")
assert report["complete"], "Selected native executions were incomplete; inspect original log"
print(json.dumps(report), flush=True)
