#!/bin/bash
set -e

APP_DIR="$HOME/.rep2-allinone"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="com.github.fukumen.rep2-allinone.plist"

echo "Stopping rep2-allinone..."
launchctl unload "$PLIST_DIR/$PLIST_FILE" 2>/dev/null || true
rm -f "$PLIST_DIR/$PLIST_FILE"

echo "Removing app files..."
rm -rf "$APP_DIR"

echo "Uninstallation complete."
