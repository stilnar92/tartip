#!/bin/zsh
# Builds build/Tartip.dmg: a universal Tartip.app next to a link to Applications.
# The installed copy in /Applications isn't touched.
set -e
cd "${0:A:h}/.."
STAGE=build/dmg
DMG=build/Tartip.dmg

rm -rf "$STAGE"
mkdir -p "$STAGE"
APP="$STAGE/Tartip.app" UNIVERSAL=1 scripts/build.sh
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname Tartip -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Built: $DMG ($(lipo -archs build/Tartip-universal))"
