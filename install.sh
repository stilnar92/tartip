#!/bin/zsh
# Installs Tartip from this checkout: builds /Applications/Tartip.app, starts it at login.
#   ./install.sh              install or update
#   ./install.sh --uninstall  remove the app and its launch agent (keeps ~/modes)
set -e
cd "${0:A:h}"

LABEL="com.user.tartip"
APP="/Applications/Tartip.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

fail() { echo "Error: $1" >&2; exit 1; }

if [ "$1" = "--uninstall" ]; then
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  pkill -x Tartip 2>/dev/null || true
  rm -f "$AGENT"
  rm -rf "$APP"
  echo "Tartip is removed."
  echo "Kept: your settings, blocks and history in ~/modes (delete the folder to remove them),"
  echo "and the signing certificate \"Tartip Local\" in your login keychain (remove it in Keychain Access)."
  exit 0
fi

[ "$(uname)" = "Darwin" ] || fail "Tartip runs on macOS only."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 13 ] || fail "Tartip needs macOS 13 or later."

# Swift comes with Xcode or its Command Line Tools.
if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Swift isn't installed. Opening the installer for the Xcode Command Line Tools…"
  xcode-select --install 2>/dev/null || true
  echo "When it finishes, run ./install.sh again."
  exit 1
fi

# The agent is what keeps the app running: copy it fresh so an update gets any changes.
mkdir -p "${AGENT:h}"
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
cp launchd/$LABEL.plist "$AGENT"

scripts/build.sh

cat <<'EOF'

Tartip is installed and running: look for ◎ in the menu bar
(if it's hidden, ⌘-drag it next to the clock). Get started opens on first launch.

Allow once:
  • Accessibility: System Settings → Privacy & Security → Accessibility → Tartip
  • Chrome: click Allow when asked whether Tartip may control Google Chrome
EOF
