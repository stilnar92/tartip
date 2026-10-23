#!/bin/zsh
# Builds /Applications/Focus Modes.app from Sources/ and (re)starts it under launchd.
# NO_START=1 builds without starting it.
set -e
cd "${0:A:h}/.."
mkdir -p build
APP="/Applications/Focus Modes.app"

AGENT="$HOME/Library/LaunchAgents/com.user.focusmodes.plist"
[ -f "$AGENT" ] || [ -n "$NO_START" ] || cp launchd/com.user.focusmodes.plist "$AGENT"

# Compile first, so a failed build leaves the running copy alone.
swift build -c release --product FocusModes
BIN="$(swift build -c release --show-bin-path)/FocusModes"

# Stop the running copy (and its auto-restart) while rebuilding.
launchctl bootout "gui/$UID/com.user.focusmodes" 2>/dev/null || true
pkill -x FocusModes 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/FocusModes"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Focus Modes</string>
  <key>CFBundleIdentifier</key><string>com.user.focusmodes</string>
  <key>CFBundleExecutable</key><string>FocusModes</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
EOF

# App icon: draw it once (make-icon.swift), then pack all sizes into AppIcon.icns.
[ -f build/icon.png ] || swift scripts/make-icon.swift build/icon.png
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
CERT="FocusModes Local"
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
echo "Built: $APP"

# Start it again under launchd: runs at login and restarts if quit.
if [ -n "$NO_START" ]; then
  echo "NO_START set, so the app was not started."
elif [ -f "$AGENT" ]; then
  launchctl bootstrap "gui/$UID" "$AGENT"
else
  echo "Auto-start is off (no $AGENT), so the app was not started."
fi
