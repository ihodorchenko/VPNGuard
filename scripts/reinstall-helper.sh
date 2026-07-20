#!/bin/bash
# Removes the installed privileged helper so the next VPNGuard launch
# can install a fresh copy via SMJobBless.
set -euo pipefail

LABEL="by.home.VPNGuard.helper"

echo "Removing $LABEL..."
sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
sudo rm -f "/Library/PrivilegedHelperTools/$LABEL"
sudo rm -f "/Library/LaunchDaemons/$LABEL.plist"

echo "Done. Now rebuild and run VPNGuard from Xcode (⌘R),"
echo "enter the admin password when prompted, then verify:"
echo "  sudo launchctl list | grep VPNGuard"
