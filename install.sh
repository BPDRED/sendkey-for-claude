#!/bin/bash
# Builds the app, copies it to ~/Applications, makes it start at login, and starts it.
# It changes only these things on this Mac:
#   ~/Applications/SendKey for Claude.app
#   ~/Library/LaunchAgents/local.sendkeyforclaude.plist   (the "start at login" file)
# If the older version (called ClaudeCmdEnter) is installed, it is removed first,
# and your send-key choice is carried over.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SendKey for Claude"
EXEC="SendKeyForClaude"
LABEL="local.sendkeyforclaude"
APP="$HOME/Applications/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# The older version, before the rename.
OLD_EXEC="ClaudeCmdEnter"
OLD_LABEL="local.claudecmdenter"
OLD_APP="$HOME/Applications/$OLD_EXEC.app"
OLD_PLIST="$HOME/Library/LaunchAgents/$OLD_LABEL.plist"

./build.sh

# Stop a running copy (old or new name), and wait until it is really gone.
# Two copies at once would change the same key twice.
for L in "$OLD_LABEL" "$LABEL"; do
    launchctl bootout "gui/$UID/$L" 2>/dev/null || true
done
pkill -x "$OLD_EXEC" 2>/dev/null || true
pkill -x "$EXEC" 2>/dev/null || true
while launchctl print "gui/$UID/$OLD_LABEL" >/dev/null 2>&1 \
   || launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1 \
   || pgrep -x "$OLD_EXEC" >/dev/null || pgrep -x "$EXEC" >/dev/null; do
    sleep 0.2
done

# Remove the older version, keeping your send-key choice.
if [ -e "$OLD_APP" ] || [ -e "$OLD_PLIST" ]; then
    for KEY in swapEnabled sendShortcut; do
        if VALUE=$(defaults read "$OLD_LABEL" "$KEY" 2>/dev/null); then
            if [ "$KEY" = swapEnabled ]; then
                if [ "$VALUE" = 1 ]; then VALUE=true; else VALUE=false; fi
                defaults write "$LABEL" "$KEY" -bool "$VALUE"
            else
                defaults write "$LABEL" "$KEY" -string "$VALUE"
            fi
        fi
    done
    rm -rf "$OLD_APP"
    rm -f "$OLD_PLIST"
    echo "Removed the older version (ClaudeCmdEnter). Your send-key choice was kept."
fi

# Copy the app.
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$APP"
cp -R "build/$APP_NAME.app" "$APP"
# Tell macOS about the new copy, so Finder and System Settings show the new
# icon instead of an old cached one.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true

# Start-at-login file. RunAtLoad = start at login. There is no KeepAlive,
# so "Quit" in the menu really quits (until the next login).
# ProcessType Interactive = macOS must not slow the helper down (keys stay instant).
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/$EXEC</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>$LABEL</string>
    </array>
</dict>
</plist>
EOF

# Start it now (and at every login from now on).
launchctl bootstrap "gui/$UID" "$PLIST"

echo
echo "Installed: $APP"
echo "Starts at login: $PLIST"
echo
echo "LAST STEP (only you can do it):"
echo "  System Settings > Privacy & Security > Accessibility > turn ON 'SendKey for Claude'."
echo "  Open that page with:"
echo "  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
