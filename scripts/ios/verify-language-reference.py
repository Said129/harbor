"""Limit the next increment to actual 0.9.132 locale resources and their UI."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
previous = '7c904bac067752f5ce16ad22e4b4f75b47c71859'
subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', previous], check=True)
codes = ['en', 'ar', 'zh', 'fr', 'de', 'hi', 'id', 'it', 'ja', 'ko', 'pl', 'pt', 'ru', 'es', 'tr', 'vi']
allowed = {'ios/Harbor/DesktopLanguages.json', 'ios/Harbor/NativeInterfaceTranslations.json', 'ios/project.yml'}
allowed.update(f'ios/Harbor/{code}.lproj/Localizable.strings' for code in codes)
roots = ['ios/Harbor', 'ios/project.yml', 'harbor-core', 'harbor-ios-bridge']
changed = set(subprocess.check_output(['git', 'diff', '--name-only', previous, 'HEAD', '--', *roots], text=True).splitlines())
assert changed == allowed, 'Changes beyond language resources require affected validation'

def blob(ref, name): return subprocess.check_output(['git', 'show', ref + ':' + name])

assert [x['code'] for x in json.loads(blob('HEAD', 'ios/Harbor/DesktopLanguages.json'))] == codes
for code in codes:
    data = blob('HEAD', f'ios/Harbor/{code}.lproj/Localizable.strings')
    assert len(data) > 10_000 and b'"Settings" =' in data
before, after = (blob(ref, 'ios/project.yml') for ref in [previous, 'HEAD'])
pattern = rb'        CFBundleLocalizations:.*?(?=        CFBundleDocumentTypes:)'
old_locales = re.search(pattern, before, flags=re.S).group()
new_locales = re.search(pattern, after, flags=re.S).group()
assert re.fullmatch(rb'[\s\[\],a-z]+', new_locales.split(b':', 1)[1])
assert re.findall(rb'\b[a-z]{2}\b', new_locales) == [x.encode() for x in codes]
assert after == before.replace(b'CFBundleVersion: "92"', b'CFBundleVersion: "93"', 1).replace(old_locales, new_locales, 1)
test = 'ios/HarborTests/StableMobileTests.swift'
old_test, new_test = (blob(ref, test).decode() for ref in [previous, 'HEAD'])
old_inventory = 'XCTAssertEqual(Set(InterfaceLanguage.all.map(\\.code)), ["en", "es", "ar", "pt", "ru"])'
new_inventory = 'XCTAssertEqual(Set(InterfaceLanguage.all.map(\\.code)), [' + ', '.join(json.dumps(code) for code in codes) + '])'
old_expected = 'let expected = ["en": "Settings", "es": "Configuración", "pt": "Configurações", "ru": "Настройки", "ar": "الإعدادات"]'
labels = ['Settings', 'الإعدادات', '设置', 'Paramètres', 'Einstellungen', 'सेटिंग्स', 'Pengaturan', 'Impostazioni', '設定', '설정', 'Ustawienia', 'Configurações', 'Настройки', 'Configuración', 'Ayarlar', 'Cài đặt']
new_expected = 'let expected = [' + ', '.join(json.dumps(code) + ': ' + json.dumps(label, ensure_ascii=False) for code, label in zip(codes, labels)) + ']'
assert old_test.count(old_inventory) == old_test.count(old_expected) == 1
assert new_test == old_test.replace(old_inventory, new_inventory, 1).replace(old_expected, new_expected, 1)
tests_changed = set(subprocess.check_output(['git', 'diff', '--name-only', previous, 'HEAD', '--', 'ios/HarborTests', 'ios/HarborIntegrationTests', 'ios/HarborUITests'], text=True).splitlines())
assert tests_changed == {test, 'ios/HarborUITests/LanguageReferenceNavigationTests.swift'}
guards = {}
for entry in subprocess.check_output(['git', 'ls-tree', '-r', 'HEAD', '--', *roots], text=True).splitlines():
    identity, name = entry.split('\t', 1)
    if name not in allowed: guards[name] = identity
api = 'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY']
headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-reference-languages'}
with urllib.request.urlopen(urllib.request.Request(api + '/actions/runs/39026561340', headers=headers), timeout=45) as response:
    run = json.load(response)
assert run['head_sha'] == previous and run['status'] == 'completed' and run['conclusion'] == 'success'
proof = dict(source=os.environ['GITHUB_SHA'], previous_source=previous, previous_run=39026561340,
             preserved_continuity_test_run=39023116051, unchanged_git_blobs=guards,
             language_inventory=codes, actual_affected_selection=['StableMobileTests/testDesktopLanguagesAndNativeFeedbackUseTheSelectedCatalog', 'LanguageReferenceNavigationTests/testReferenceLanguagesSwitchInTheOrdinaryIPhoneSettings', 'LanguageReferenceNavigationTests/testReferenceLanguagesSwitchInTheOrdinaryIPadSettings'],
             scope='Only locale resources, bundle language declarations and two expectations in the existing language method change. Run the expanded language case and ordinary language switching on iPhone/iPad; preserve approved unchanged playback, sources, continuity, reading, account and UI implementations.',
             full_desktop_parity_complete=False, physical_device_validation=False)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print('Verified the exact language-only scope and previous corrected build. Only expanded language validation executes.')
