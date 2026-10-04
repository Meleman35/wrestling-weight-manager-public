#!/usr/bin/env python3
"""Create a temporary simulator test app using Xcode's normal signing pipeline."""
from pathlib import Path
import hashlib
import json
import plistlib
import sys

root = Path(__file__).resolve().parent.parent
out = Path(sys.argv[1]).resolve()
project = out / 'LaunchCaptureHost.xcodeproj'
project.mkdir(parents=True, exist_ok=True)
objects = []

def ident(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24].upper()

def add(name, fields):
    key = ident(name)
    objects.append(f'{key} = {{ {fields} }};')
    return key

def array(values):
    return '(' + ','.join(values) + ',)'

files = sorted((root / 'native-candidate').glob('WrestlingManagerRemote*.swift'))
files.append(root / 'tests/launch-capture-host-ui.swift')
refs, builds = [], []
for source in files:
    ref = add('ref:' + source.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {json.dumps(str(source))}; sourceTree = "<absolute>";')
    refs.append(ref)
    builds.append(add('build:' + source.name, f'isa = PBXBuildFile; fileRef = {ref};'))
product = add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = RemoteSessionUITests.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('products', f'isa = PBXGroup; children = {array([product])}; name = Products; sourceTree = "<group>";')
main = add('main', f'isa = PBXGroup; children = {array(refs + [products])}; sourceTree = "<group>";')
sources = add('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(builds)}; runOnlyForDeploymentPostprocessing = 0;')
frameworks = add('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
settings = '''CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = RGB5BL98V8;
 PRODUCT_BUNDLE_IDENTIFIER = app.launch-capture-host.ui-tests; PRODUCT_NAME = RemoteSessionUITests;
 GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES;
 INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
 INFOPLIST_KEY_NSCameraUsageDescription = "Simulated capture regression only.";
 CODE_SIGN_ENTITLEMENTS = Test.entitlements; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0;
 SDKROOT = iphonesimulator; SUPPORTED_PLATFORMS = iphonesimulator; IPHONEOS_DEPLOYMENT_TARGET = 17.6;
 TARGETED_DEVICE_FAMILY = "1,2"; SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = "-Onone";
 SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG REMOTE_SCALE_UI_TESTS";
 LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks"; ONLY_ACTIVE_ARCH = YES;'''
config = add('config', f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = Debug;')
project_config = add('project-config', 'isa = XCBuildConfiguration; buildSettings = { CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; }; name = Debug;')
configs = add('configs', f'isa = XCConfigurationList; buildConfigurations = {array([config])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
project_configs = add('project-configs', f'isa = XCConfigurationList; buildConfigurations = {array([project_config])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
target = add('target', f'isa = PBXNativeTarget; buildConfigurationList = {configs}; buildPhases = {array([sources,frameworks])}; buildRules = (); dependencies = (); name = RemoteSessionUITests; productName = RemoteSessionUITests; productReference = {product}; productType = "com.apple.product-type.application";')
project_id = add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2630; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en,Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([target])};')
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + '\n}; rootObject = ' + project_id + ';}\n')
(out / 'Test.entitlements').write_bytes(plistlib.dumps({'keychain-access-groups': ['$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)']}))
print(project)
