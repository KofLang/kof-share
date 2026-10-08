#!/bin/sh
# kofshare-desktop launcher (F7 packaging, Linux x86_64).
# Starts the desktop daemon if absent (idempotent), then opens the shell
# page in the system webview/browser (xdg-open; kof.ui's webview route is
# documented in docs/desktop/discovery.md §5 — node/JS toolchain absent on
# this machine, recorded honestly in the phase0 matrix row 19).
# Usage: kofshare-desktop [--stop] [--status]
set -e
JAR=${KOFSHARE_JAR:-$HOME/.local/share/kofshare/kof-cli.jar}
ENTRY=${KOFSHARE_ENTRY:-$HOME/.local/share/kofshare/src/main/kof/kofshare/desktop/desktopd.kf}
JAVA=${JAVA:-java}
case "$1" in
  --stop)   exec "$JAVA" -jar "$JAR" run "$ENTRY" --stop ;;
  --status) exec "$JAVA" -jar "$JAR" run "$ENTRY" --status ;;
  *)
    "$JAVA" -jar "$JAR" run "$ENTRY" --start >/dev/null 2>&1 || true
    exec "$JAVA" -jar "$JAR" run "$ENTRY" --window
    ;;
esac
