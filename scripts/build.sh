#!/bin/zsh
# Builds /Applications/Tartip.app from Sources/ and (re)starts it under launchd.
# NO_START=1 builds without starting it.
# APP=path/Tartip.app builds there instead and leaves the installed copy alone (make-dmg.sh).
# UNIVERSAL=1 builds for both Apple silicon and Intel.
set -e
cd "${0:A:h}/.."
mkdir -p build
INSTALLED="/Applications/Tartip.app"
APP="${APP:-$INSTALLED}"
[ "$APP" = "$INSTALLED" ] || NO_START=1

AGENT="$HOME/Library/LaunchAgents/com.user.tartip.plist"


# Compile first, so a failed build leaves the running copy alone.
if [ -n "$UNIVERSAL" ]; then
  for arch in arm64 x86_64; do
    swift build -c release --product Tartip --triple $arch-apple-macosx13.0
  done
  BIN=build/Tartip-universal
  lipo -create -output "$BIN" \
    "$(swift build -c release --triple arm64-apple-macosx13.0 --show-bin-path)/Tartip" \
    "$(swift build -c release --triple x86_64-apple-macosx13.0 --show-bin-path)/Tartip"
else
  swift build -c release --product Tartip
  BIN="$(swift build -c release --show-bin-path)/Tartip"
fi

# Stop the running copy (and its auto-restart) while rebuilding it.
if [ "$APP" = "$INSTALLED" ]; then
  launchctl bootout "gui/$UID/com.user.tartip" 2>/dev/null || true
  pkill -x Tartip 2>/dev/null || true
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Tartip"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Tartip</string>
  <key>CFBundleIdentifier</key><string>com.user.tartip</string>
  <key>CFBundleExecutable</key><string>Tartip</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.9</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSAppleEventsUsageDescription</key><string>Tartip opens your links in Chrome and sends blocked tabs to a "Not now" page.</string>
</dict>
</plist>
EOF

# App icon: the mark from Sources/Tartip/UI/Logo.swift, drawn by make-icon.swift (top-level code
# has to be main.swift when compiled with another file), then all sizes packed into AppIcon.icns.
mkdir -p build/icon-tool
cp scripts/make-icon.swift build/icon-tool/main.swift
swiftc -O Sources/Tartip/UI/Logo.swift build/icon-tool/main.swift -o build/icon-tool/make-icon
build/icon-tool/make-icon build/icon.png
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz build/icon.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) build/icon.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
mkdir -p "$APP/Contents/Resources"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "${ICONSET:h}"

# Sign with a stable local certificate so macOS keeps the Accessibility
# permission across rebuilds (ad-hoc signatures change every build).
CERT="Tartip Local"
if ! security find-certificate -c "$CERT" >/dev/null 2>&1; then
  TMP=$(mktemp -d)
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$CERT" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
  # macOS's keychain only reads the older PKCS#12 encryption (OpenSSL 3 defaults to AES).
  openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" -passout pass:focus \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null
  security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P focus -T /usr/bin/codesign >/dev/null \
    || echo "Note: couldn't import the signing certificate"
  rm -rf "$TMP"
fi
if ! codesign --force -s "$CERT" "$APP" 2>/dev/null; then
  echo "Note: signing with '$CERT' failed, using ad-hoc (Accessibility must be re-allowed after rebuilds)"
  codesign --force -s - "$APP"
fi
# Tell LaunchServices about this build, so the icon it hands to Notification Center and the
# Dock isn't the one cached from an older version.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true
echo "Built: $APP"

# Preserve an existing launch policy; new installations start normally.
if [ "$APP" != "$INSTALLED" ]; then
  :
elif [ -n "$NO_START" ]; then
  echo "NO_START set, so the app was not started."
elif [ -f "$AGENT" ]; then
  launchctl bootstrap "gui/$UID" "$AGENT"
else
  open "$APP"
fi
