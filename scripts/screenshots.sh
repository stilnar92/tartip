#!/bin/zsh
# Captures Tartip's own windows (never the whole screen) for the README.
# The app must be running in screenshot mode (see WindowCoordinator.listenForScreenshots):
# touch ~/modes/.screenshots before it starts (or launch it with TARTIP_SCREENSHOTS=1), and
# use made-up data, not your own.
# Usage: scripts/screenshots.sh <out-dir> <name> <command>...
#   commands: panel | main:<tab> | close | phase:<picking|session:<activity>:<min>|review:<activity>|away-review|idle>
# Each command is sent, then every visible Tartip window is saved as <name>-<n>.png.
set -e
out=$1; name=$2; shift 2
mkdir -p "$out"
for c in "$@"; do
  swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(.init(\"com.user.tartip.screenshot\"), object: \"$c\", userInfo: nil, deliverImmediately: true)"
  sleep 1.5
done
pid=$(pgrep -f Tartip.app/Contents/MacOS/Tartip | head -1)
# By process, not by name: the owner name isn't always reported.
ids=$(swift -e "
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerPID as String] as? Int) == $pid {"'
    let b = w[kCGWindowBounds as String] as! [String: Double]
    if b["Height"]! > 60 { print(w[kCGWindowNumber as String] as! Int) }   // skip the menu bar item
}')
n=0
for id in ${(f)ids}; do
  n=$((n + 1))
  screencapture -o -x -l "$id" "$out/$name-$n.png"
  echo "$out/$name-$n.png"
done
