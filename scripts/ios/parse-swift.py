"""Ask the installed Apple compiler to parse native sources before heavy builds."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
files = sorted(str(path) for directory in ['Harbor', 'HarborTests', 'HarborIntegrationTests', 'HarborUITests'] for path in (root / 'ios' / directory).rglob('*.swift'))
if not files:
    raise SystemExit('No native Swift sources found')
result = subprocess.run(['xcrun', 'swiftc', '-frontend', '-parse', *files], cwd=root, check=False)
if result.returncode:
    raise SystemExit(result.returncode)
print(f'Apple Swift parser accepted {len(files)} native source files; type checking/build remain separate.')
