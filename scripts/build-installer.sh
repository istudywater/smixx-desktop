#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
./scripts/build-driver.sh
stage="$PWD/.build/installer-root"
# This is a disposable build staging directory, not an installed application.
rm -rf "$stage"
mkdir -p "$stage/Applications" "$stage/Library/Audio/Plug-Ins/HAL" "$stage/Library/Application Support/Smixx/Uninstall"
ditto 'dist/Smixx Desktop.app' "$stage/Applications/Smixx Desktop.app"
ditto dist/SmixxAudio.driver "$stage/Library/Audio/Plug-Ins/HAL/SmixxAudio.driver"
cp Driver/Packaging/uninstall-smixx.sh "$stage/Library/Application Support/Smixx/Uninstall/uninstall-smixx.sh"
chmod 755 "$stage/Library/Application Support/Smixx/Uninstall/uninstall-smixx.sh"
mkdir -p "$stage/Applications/Smixx Desktop.app/Contents/Resources/libASPL"
cp Driver/ThirdParty/libASPL/LICENSE* Driver/ThirdParty/libASPL/AUTHORS.md Driver/ThirdParty/libASPL/REVISION "$stage/Applications/Smixx Desktop.app/Contents/Resources/libASPL/"
if [[ -n "${SMIXX_SIGN_ID:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SMIXX_SIGN_ID" "$stage/Applications/Smixx Desktop.app"
else
  codesign --force --sign - "$stage/Applications/Smixx Desktop.app"
fi
pkgbuild --root "$stage" --identifier org.smixx.desktop.prototype --version 0.3.0 --install-location / --ownership recommended .build/Smixx-component.pkg
productbuild --synthesize --package .build/Smixx-component.pkg .build/Smixx-distribution.xml
python3 - <<'PY'
from pathlib import Path
import xml.etree.ElementTree as ET
import platform
p = Path('.build/Smixx-distribution.xml')
tree = ET.parse(p); root = tree.getroot()
title = ET.SubElement(root, 'title'); title.text = 'Smixx Desktop — Audio Driver Feasibility Build'
options = root.find('options')
if options is not None:
    options.set('require-scripts', 'false')
    options.set('hostArchitectures', platform.machine())
for ref in root.findall('pkg-ref'):
    if ref.text and '.pkg' in ref.text: ref.set('onConclusion', 'RequireRestart')
ET.SubElement(root, 'domains', {'enable_localSystem': 'true', 'enable_currentUserHome': 'false', 'enable_anywhere': 'false'})
tree.write(p, encoding='utf-8', xml_declaration=True)
PY
if [[ -n "${SMIXX_INSTALLER_SIGN_ID:-}" ]]; then
  productbuild --distribution .build/Smixx-distribution.xml --package-path .build --sign "$SMIXX_INSTALLER_SIGN_ID" dist/Smixx-Prototype.pkg
else
  productbuild --distribution .build/Smixx-distribution.xml --package-path .build dist/Smixx-Prototype.pkg
fi
echo 'Built dist/Smixx-Prototype.pkg. Administrator installation and a restart are required.'
echo 'This is a local feasibility installer; not notarized or approved for distribution.'
