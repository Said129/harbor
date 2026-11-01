"""Review only unresolved candidate cases, using a fresh simulator per batch."""
import json
import os
from pathlib import Path
import re
import subprocess

BASE = '90ac0542d4570883a54789e914dd5ae9f85eea8f'
OUTPUT = Path('ios/build/candidate-review')
OUTPUT.mkdir(parents=True, exist_ok=True)
product_paths = ['ios/Harbor', 'ios/project.yml', 'ios/Info.plist', 'harbor-core', 'harbor-ios-bridge',
                 'scripts/ios/build-rust.sh', 'scripts/ios/resolve-packages.py',
                 'scripts/ios/fetch-interface-font.py', 'scripts/ios/fetch-manga-font.py', 'scripts/ios/package-ipa.py']
subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', BASE], check=True)
changed = subprocess.check_output(['git', 'diff', '--name-only', BASE, 'HEAD', '--', *product_paths], text=True).splitlines()
assert not changed, 'A changed product requires a new IPA: ' + ', '.join(changed)

batches = {
    'trakt-date': ('phone', [
        'TraktHomeTests/testLateReplyCannotPublishAfterDisconnectProfileDepartureOrAReplacementAccount',
        'TraktHomeTests/testTraktRowsParticipateInExistingHomeLayoutWithoutExposingCredentialOrLosingOtherRows',
        'TraktHomeMountTests/testActualPersonalizedRailsViewAllAndExistingCustomizationMountDecodedCoversInBothSizes']),
    'bookmark-seed': ('phone', ['ReaderBookmarkInterfaceSeedTests/testPrepareOwnedBookAndTwoBookmarkRoutesInOneFreshGuest']),
    'identity-seed': ('phone', ['HarborIdentityInterfaceSeedTests/testPrepareAnOwnedGuestWithoutAnIdentitySession']),
    'bulk-reading-seed': ('phone', ['HarborReadingPluginInterfaceSeedTests/testPrepareOwnedBulkRepositoryWithoutInstallingItsEntries']),
    'combined-reading-seed': ('phone', ['HarborReadingPluginInterfaceSeedTests/testPrepareOwnedCombinedBookCatalogInTheOrdinaryLocalInstallation']),
    'manual-reading-seed': ('phone', ['HarborReadingPluginInterfaceSeedTests/testPrepareOwnedReadingSourcesInTheOrdinaryLocalInstallation']),
    'ipad-focus': ('tablet', ['PosterBehaviorMountTests/testActualNativeFocusLoadsWidePixelsReservesWidthRevealsTheCardAndCollapsesForPointerWithoutActivatingIt']),
}
requested = os.environ.get('HARBOR_NATIVE_SELECTION', '').strip()
selected = requested.split(',') if requested else list(batches)
assert selected and len(set(selected)) == len(selected) and set(selected) <= set(batches), 'Unknown or duplicate review batch'
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True))
tablet = next(d['udid'] for runtime, values in devices['devices'].items() if 'iOS' in runtime
              for d in values if d['name'].startswith('iPad'))
destinations = {'phone': os.environ['IOS_SIMULATOR'], 'tablet': tablet}
report = dict(packaged_source=BASE, review_source=os.environ['GITHUB_SHA'], product_sources_unchanged=True,
              selected_batches=selected, results=[], complete=False, physical_device_verified=False,
              full_desktop_parity_complete=False, ipa_created=False)

def save():
    (OUTPUT / 'review.json').write_text(json.dumps(report, indent=2) + '\n', 'utf-8')

save()
for name in selected:
    kind, cases = batches[name]
    device = destinations[kind]
    # These devices belong to the disposable GitHub Actions host, not a user device.
    subprocess.run(['xcrun', 'simctl', 'shutdown', device], check=False, capture_output=True)
    subprocess.run(['xcrun', 'simctl', 'erase', device], check=True)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True)
    result = OUTPUT / (name + '.xcresult')
    command = ['xcodebuild', '-project', 'ios/Harbor.xcodeproj', '-scheme', 'Harbor', '-configuration', 'Debug',
               '-destination', f"platform=iOS Simulator,id={device},arch={os.environ['IOS_SIMULATOR_ARCH']}",
               '-derivedDataPath', 'ios/build/DerivedData', '-clonedSourcePackagesDirPath', 'ios/build/SourcePackages',
               '-resultBundlePath', str(result), *['-only-testing:HarborTests/' + case for case in cases],
               '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'test']
    with (OUTPUT / (name + '.log')).open('w', encoding='utf-8') as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors='replace')
        for line in process.stdout:
            log.write(line)
            print(line, end='', flush=True)
        status = process.wait()
    text = (OUTPUT / (name + '.log')).read_text('utf-8')
    rows = [dict(case=m[1] + '/' + m[2], result=m[3]) for m in
            re.finditer(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped)", text)]
    expected = {'HarborTests.' + case for case in cases}
    passed = status == 0 and len(rows) == len(expected) and {r['case'] for r in rows} == expected and all(r['result'] == 'passed' for r in rows)
    passed = passed and not any(s in text for s in ['Restarting after unexpected exit', 'freed pointer', 'Fatal error:'])
    entry = dict(batch=name, device=kind, status=status, cases=rows, passed=passed)
    report['results'].append(entry)
    save()
    attachments = OUTPUT / 'attachments' / name
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(attachments)], check=True)
    entry['original_png_count'] = len(list(attachments.rglob('*.png')))
    if name in ['trakt-date', 'ipad-focus'] and entry['original_png_count'] == 0:
        entry['passed'] = passed = False
    save()
    subprocess.run(['xcrun', 'simctl', 'shutdown', device], check=False, capture_output=True)
    assert passed, 'Unresolved candidate review: ' + name

report['complete'] = True
save()
print('Candidate review complete; no approved unrelated test was selected and no IPA was rebuilt.')
