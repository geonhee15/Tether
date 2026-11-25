#!/bin/zsh
# Regenerates docs/screenshots/*.png for the README.
# Uses the built-in demo mode: fictional sample Spaces in a scratch folder and a separate
# preferences suite, so real accounts, Spaces and settings are never read or touched.
#   ./build.sh debug && Scripts/screenshots.sh
set -u
cd "$(dirname "$0")/.."
APP="$PWD/build/Tether.app/Contents/MacOS/Tether"
OUT="$PWD/docs/screenshots"
mkdir -p "$OUT"

ONLY=("$@")   # optional: names to re-capture, e.g. Scripts/screenshots.sh home node

shot() {  # shot <name> <scene> [ENV=value ...]
  local name=$1 scene=$2; shift 2
  if (( ${#ONLY} > 0 )) && [[ ${ONLY[(Ie)$name]} -eq 0 ]]; then return; fi
  local data attempt size
  # The window server occasionally hands back an empty frame; such a capture is tiny, so retry it.
  for attempt in 1 2 3; do
    data="$(mktemp -d /tmp/tether-shots.XXXXXX)"
    env TETHER_DATA_DIR="$data" TETHER_DEMO=1 TETHER_SCENE="$scene" TETHER_WINDOW=1280x820 \
        TETHER_SNAPSHOT="$OUT/$name.png" "$@" "$APP" >/dev/null 2>&1
    rm -rf "$data"
    size=$(stat -f%z "$OUT/$name.png" 2>/dev/null || echo 0)
    (( size > 120000 )) && break
  done
  /usr/bin/sips -Z 1680 "$OUT/$name.png" >/dev/null 2>&1
  echo "  $name.png"
}

echo "▶ capturing"
shot login            login    TETHER_LANG=ko TETHER_APPEARANCE=dark
shot password-reset   reset    TETHER_LANG=ko TETHER_APPEARANCE=light
shot space-setup      setup    TETHER_LANG=ko TETHER_APPEARANCE=light
shot account          account  TETHER_LANG=ko TETHER_APPEARANCE=light
shot new-space        newspace TETHER_LANG=ko TETHER_APPEARANCE=dark
shot home             home     TETHER_LANG=ko TETHER_APPEARANCE=light
shot node             node0    TETHER_LANG=ko TETHER_APPEARANCE=light
shot insert-menu      insert   TETHER_LANG=ko TETHER_APPEARANCE=light
shot chart-pie        node0    TETHER_LANG=ko TETHER_APPEARANCE=light TETHER_SCROLL=520
shot analytics        node1    TETHER_LANG=ko TETHER_APPEARANCE=dark
shot analytics-actions node1   TETHER_LANG=ko TETHER_APPEARANCE=light TETHER_SCROLL=640
shot linked-chart     node2    TETHER_LANG=ko TETHER_APPEARANCE=dark
shot chart-line       node2    TETHER_LANG=en TETHER_APPEARANCE=light TETHER_SCROLL=600
shot file             file     TETHER_LANG=ko TETHER_APPEARANCE=light TETHER_SNAPSHOT_DELAY=4
shot assistant        assistant     TETHER_LANG=ko TETHER_APPEARANCE=light
shot assistant-approval assistant-ask TETHER_LANG=ko TETHER_APPEARANCE=dark
shot ai-settings      aisettings    TETHER_LANG=ko TETHER_APPEARANCE=light
shot keep-awake       awake    TETHER_LANG=ko TETHER_APPEARANCE=dark TETHER_SNAPSHOT_DELAY=3
shot settings         settings TETHER_LANG=ko TETHER_APPEARANCE=light TETHER_SETTINGS_TAB=appearance
shot about            settings TETHER_LANG=ko TETHER_APPEARANCE=dark TETHER_SETTINGS_TAB=about
shot theme-sunset     home     TETHER_LANG=en TETHER_APPEARANCE=dark TETHER_SKIN=sunset
shot theme-sage       node2    TETHER_LANG=en TETHER_APPEARANCE=light TETHER_SKIN=sage
echo "✔ wrote $OUT"
