"""Expose the selected simulator's own Swift WebKit overlay to Xcode 16.4.

Apple's simulator-only workaround: developer.apple.com/forums/thread/785964.
The installed app, deployment target and runtime remain unchanged.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess

devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json']))['devices']
runtime_id, = [runtime for runtime, values in devices.items() if any(row['udid'] == os.environ['IOS_SIMULATOR'] for row in values)]
runtimes = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '--json']))['runtimes']
runtime, = [row for row in runtimes if row['identifier'] == runtime_id and row.get('isAvailable', True)]
root = Path(runtime['bundlePath']) / 'Contents/Resources/RuntimeRoot'
ordinary = root / 'usr/lib/swift/libswiftWebKit.dylib'
overlay = root / 'System/Cryptexes/OS/usr/lib/swift/libswiftWebKit.dylib'
outputs = [Path('ios/build') / directory / 'Build/Products/Debug-iphonesimulator/libswiftWebKit.dylib'
    for directory in ['DerivedData', 'ExistingAppUIData']]
linked = not ordinary.is_file() and overlay.is_file()
if linked:
    # The independent UI runner has its own DYLD_LIBRARY_PATH. Keep the same
    # selected runtime available there without reinstalling the prepared app.
    for output in outputs:
        output.parent.mkdir(parents=True, exist_ok=True)
        if output.is_symlink():
            assert output.resolve() == overlay.resolve(), 'Unexpected existing WebKit overlay'
        else:
            assert not output.exists(), 'Never replace a build product with a runtime overlay'
            output.symlink_to(overlay)
proof = dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), simulator_runtime=runtime_id,
    runtime_version=runtime['version'], applied=linked, simulator_only=True,
    deployment_target_changed=False, library_embedded_in_app=False)
if linked:
    proof.update(runtime_library_sha256=hashlib.sha256(overlay.read_bytes()).hexdigest(), runtime_library=str(overlay),
        build_product_link=str(outputs[0]), build_product_links=[str(output) for output in outputs])
target = Path('ios/build/canonical/SimulatorWebKitOverlay.json'); target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print(json.dumps(proof))
