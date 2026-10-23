#!/usr/bin/env python3
"""Audit resource parity, format arguments, and literal UI localization coverage."""
from pathlib import Path
import json
import re
import plistlib

root = Path(__file__).resolve().parents[1]
quoted = r'"(?:[^"\\]|\\.)*"'
entry = re.compile(r'(' + quoted + r')\s*=\s*(' + quoted + r')\s*;')

def catalog(path):
    pairs = [(json.loads(a), json.loads(b)) for a, b in entry.findall(path.read_text())]
    assert len(dict(pairs)) == len(pairs), f'Duplicate keys in {path}'
    return dict(pairs)

base = root / 'Sources/MenuBarCore/Resources'
en = catalog(base / 'en.lproj/Localizable.strings')
zh = catalog(base / 'zh-Hans.lproj/Localizable.strings')
assert en and set(en) == set(zh), 'Language catalog keys differ'
placeholder = re.compile(r'%(?:\d+\$)?(?:ld|@|d|f)')
for key in en:
    assert placeholder.findall(key) == placeholder.findall(en[key]) == placeholder.findall(zh[key]), key
    assert not re.search(r'[\u3400-\u9fff]', en[key]), f'Untranslated English: {key}'
    assert en[key] and zh[key], f'Empty translation: {key}'

for folder in ['MenuBarStudio', 'MenuBarCore']:
    for path in (root / 'Sources' / folder).glob('*.swift'):
        if path.name == 'Localization.swift':
            continue
        for match in re.finditer(quoted, path.read_text()):
            text = match.group()[1:-1]
            if re.search(r'[\u3400-\u9fff]', text):
                assert path.read_text()[max(0, match.start()-2):match.start()] == 'L(', f'Unlocalized literal: {path.name}: {text}'
                assert json.loads(match.group()) in en, f'Missing resource: {text}'
info = plistlib.loads((root / 'Info.plist').read_bytes())
assert set(info['CFBundleLocalizations']) == {'en', 'zh-Hans'}
for language, name in [('en', 'DrawerBar'), ('zh-Hans', '小屉')]:
    metadata = catalog(root / 'Resources' / (language + '.lproj') / 'InfoPlist.strings')
    assert metadata['CFBundleDisplayName'] == name
    assert metadata['NSScreenCaptureUsageDescription']
print(f'PASS {len(en)} bilingual strings, format arguments, Swift coverage, app names and permission metadata')
