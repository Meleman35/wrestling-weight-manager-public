#!/usr/bin/env python3
"""Reject stale duplicate sources and accidental changes to app identity."""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parent.parent
app = root / 'native-app'
sources = app / 'Wrestling Manager'
for folder, pattern in [('billing-candidate', 'WrestlingManager*.swift'),
                        ('native-candidate', 'WrestlingManagerRemote*.swift')]:
    for source in (root / folder).glob(pattern):
        assert (sources / source.name).read_bytes() == source.read_bytes(), f'Stale native source: {source.name}'
for source in (root / 'native-device-check/AmericanScaleKit').rglob('*.swift'):
    if '.build' not in source.parts:
        target = app / 'WrestlingManagerNative' / source.relative_to(root / 'native-device-check/AmericanScaleKit')
        assert target.read_bytes() == source.read_bytes(), f'Stale scale source: {source.name}'
project = (app / 'Wrestling Manager Xcode App.xcodeproj/project.pbxproj').read_text()
assert project.count('PRODUCT_BUNDLE_IDENTIFIER = com.damonmele.wrestlingmanager;') == 2
assert project.count('DEVELOPMENT_TEAM = RGB5BL98V8;') == 2
assert project.count('CURRENT_PROJECT_VERSION = 9;') == 2
assert project.count('productName = AmericanScaleKit;') == 1
scheme = (app / 'Wrestling Manager Xcode App.xcodeproj/xcshareddata/xcschemes/Wrestling Manager.xcscheme').read_text()
assert 'StoreKitConfigurationFileReference' not in scheme, 'Normal Run must use Apple sandbox, not local StoreKit simulation'
privacy = plistlib.loads((sources / 'PrivacyInfo.xcprivacy').read_bytes())
reasons = {entry['NSPrivacyAccessedAPIType']: entry['NSPrivacyAccessedAPITypeReasons']
           for entry in privacy['NSPrivacyAccessedAPITypes']}
assert 'C617.1' in reasons.get('NSPrivacyAccessedAPICategoryFileTimestamp', []), 'App-container file metadata needs its declared API reason'
for source in app.rglob('*'):
    assert 'xcuserdata' not in source.parts and '.build' not in source.parts
    if source.suffix in {'.swift', '.plist', '.xcprivacy', '.entitlements'}:
        if source.suffix != '.swift':
            plistlib.loads(source.read_bytes())
        assert not re.search(r'-----BEGIN (?:EC |RSA )?PRIVATE KEY-----|sb_secret_|sk_live_', source.read_text()), f'Secret marker: {source.name}'
print('PASS: current candidates, tested scale implementation, main app identity, project configuration and resource parsing')
