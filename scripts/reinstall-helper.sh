#!/bin/bash
# Resets the SMAppService-registered privileged helper so the next VPNGuard
# launch can register it again.
set -euo pipefail

LABEL="by.home.VPNGuard.helper"

echo "Booting out $LABEL..."
sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
sudo rm -f "/Library/LaunchDaemons/$LABEL.plist"

echo "Done."
echo "SMAppService keeps its own registration database. If registration still"
echo "reports it as already registered, open System Settings → General → Login"
echo "Items, remove VPNGuard, then rebuild and run VPNGuard from Xcode (⌘R)."
