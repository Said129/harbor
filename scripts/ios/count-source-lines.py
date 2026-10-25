"""Count first-party iOS application, shared core, native bridge and test sources."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, help='Optionally save the JSON count; otherwise print it only')
args = parser.parse_args()
repository = Path(__file__).resolve().parents[2]
extensions = {'.swift', '.rs', '.h', '.m', '.mm', '.c', '.cc', '.cpp', '.js', '.ts', '.css', '.html', '.metal'}
excluded_directories = {'assets.xcassets', 'target', 'build', '.build', 'deriveddata', 'pods', 'carthage', 'generated', 'node_modules', 'vendor'}
roots = {
    'application': ['ios/Harbor', 'harbor-core/src', 'harbor-ios-bridge/src'],
    'tests': ['ios/HarborTests', 'ios/HarborUITests', 'ios/HarborIntegrationTests', 'harbor-core/tests', 'harbor-ios-bridge/tests'],
}
groups = {}
for group, folders in roots.items():
    components = {}
    for folder in folders:
        directory = repository / folder
        assert directory.is_dir(), folder
        counts = dict(files=0, lines=0, nonblank_lines=0)
        for path in sorted(directory.rglob('*')):
            if not path.is_file() or path.suffix.lower() not in extensions:
                continue
            if any(part.lower() in excluded_directories for part in path.relative_to(repository).parts) or 'uniffi' in path.name.lower():
                continue
            lines = path.read_text(encoding='utf-8-sig').splitlines()
            counts['files'] += 1
            counts['lines'] += len(lines)
            counts['nonblank_lines'] += sum(bool(line.strip()) for line in lines)
        components[folder] = counts
    groups[group] = dict(components=components, **{key: sum(item[key] for item in components.values()) for key in ['files', 'lines', 'nonblank_lines']})
report = dict(observed_at=datetime.now(timezone.utc).isoformat(),
    head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repository, text=True).strip(),
    count='Current saved files, including uncommitted edits. Physical lines include comments and blank lines.',
    excludes='Dependencies, generated bindings, resources, translations, configuration and build/validation tooling.',
    application=groups['application'], tests=groups['tests'],
    total_lines=sum(value['lines'] for value in groups.values()))
text = json.dumps(report, ensure_ascii=False, indent=2) + '\n'
if args.output:
    args.output.write_text(text, encoding='utf-8', newline='\n')
print(text, end='')
