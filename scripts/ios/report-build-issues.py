"""Report actual Apple build issues when the console log omits their details."""
import json
from pathlib import Path
import sys


def main():
    path = Path(sys.argv[1])
    try:
        if not 0 < path.stat().st_size < 100 * 1024**2:
            raise ValueError("invalid result size")
        result = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        print("Apple build result was unavailable; preserve the raw build log for diagnosis.")
        return
    issues = result.get("issues", {})
    found = False
    for kind in ("errorSummaries", "warningSummaries"):
        for issue in issues.get(kind, {}).get("_values", []):
            found = True
            location = issue.get("documentLocationInCreatingWorkspace", {}).get("url", {}).get("_value", "")
            message = issue.get("message", {}).get("_value", "")
            print(f"{kind}: {location}\n{message}")
    if not found:
        print("Apple recorded no issue summaries; inspect the raw build log.")


if __name__ == "__main__":
    main()
