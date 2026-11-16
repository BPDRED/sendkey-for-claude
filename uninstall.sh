#!/bin/bash
# Removes the helper: stops it, deletes the start-at-login file and the app.
# Also removes the older version (called ClaudeCmdEnter) if it is still there.
# It touches nothing else. Claude itself is never changed.
set -euo pipefail

for PAIR in "SendKey for Claude|SendKeyForClaude|local.sendkeyforclaude" \
            "ClaudeCmdEnter|ClaudeCmdEnter|local.claudecmdenter"; do
    IFS="|" read -r APP_NAME EXEC LABEL <<< "$PAIR"
    APP="$HOME/Applications/$APP_NAME.app"
    PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

    launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
    pkill -x "$EXEC" 2>/dev/null || true

    if [ -e "$APP" ] || [ -e "$PLIST" ]; then
        rm -f "$PLIST"
        rm -rf "$APP"
        echo "Removed: $APP"
        echo "Removed: $PLIST"
    fi
done

echo
echo "Optional clean-up (see docs/INSTALL.md, 'Uninstall'):"
echo "  tccutil reset Accessibility local.sendkeyforclaude   # forget the permission"
echo "  defaults delete local.sendkeyforclaude               # forget your send-key choice"
