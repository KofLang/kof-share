#!/bin/sh
# Removes exactly what install-desktop.sh wrote (daemon stopped first via the
# product's own --stop law; no other files touched).
BIN=$HOME/.local/bin; SHARE=$HOME/.local/share/kofshare
"$BIN/kofshare-desktop" --stop >/dev/null 2>&1 || true
rm -f "$BIN/kofshare-desktop" "$HOME/.local/share/applications/kofshare.desktop"
rm -rf "$SHARE"
echo "UNINSTALL-OK"
