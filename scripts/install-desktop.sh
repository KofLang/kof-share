#!/bin/sh
# KofShare desktop installer (Linux x86_64, per-user, no root). F7 v1 story:
# copy pin jar + product src + launcher + .desktop entry into ~/.local,
# generate the icon. Re-run = upgrade (files replaced). uninstall-desktop.sh
# removes exactly what this writes.
set -e
SRC=${1:?usage: install-desktop.sh <path-to-kof-cli.jar> [repo-src-dir]}
REPO=${2:-$(dirname "$0")/..}
BIN=$HOME/.local/bin
SHARE=$HOME/.local/share/kofshare
mkdir -p "$BIN" "$SHARE" "$HOME/.local/share/applications"
cp "$SRC" "$SHARE/kof-cli.jar"
cp -r "$REPO/src" "$SHARE/"
install -m 755 "$REPO/scripts/kofshare-desktop.sh" "$BIN/kofshare-desktop"
install -m 644 "$REPO/scripts/kofshare-desktop.desktop" "$HOME/.local/share/applications/kofshare.desktop"
printf 'KofShare\n' > "$SHARE/kofshare.icon.txt" # icon asset lands with F7 proper
echo "INSTALL-OK bin=$BIN/kofshare-desktop"
