#!/bin/bash
set -e

APP_DIR="$HOME/.rep2-allinone"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="com.github.fukumen.rep2-allinone.plist"

echo "Installing rep2-allinone to $APP_DIR..."

mkdir -p "$APP_DIR"
cp -r bin conf p2-php rep2-allinone "$APP_DIR/"
chmod +x "$APP_DIR/rep2-allinone" "$APP_DIR/bin/"*

sed -i '' "s|HOME_DIR|$HOME|g" "$APP_DIR/conf/Caddyfile"

mkdir -p "$PLIST_DIR"
sed "s|HOME_DIR|$HOME|g" com.github.fukumen.rep2-allinone.plist.template > "$PLIST_DIR/$PLIST_FILE"

echo "Loading launch agent..."
launchctl unload "$PLIST_DIR/$PLIST_FILE" 2>/dev/null || true
launchctl load "$PLIST_DIR/$PLIST_FILE"

echo "Installation complete!"
echo "rep2-allinone is now running on http://localhost:10088/"
