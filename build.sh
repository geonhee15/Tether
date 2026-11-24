#!/bin/zsh
# Builds Tether.app into ./build with swiftc directly (Command Line Tools are enough, no Xcode),
# then installs the release build into /Applications.
#   ./build.sh            # release build + install
#   ./build.sh debug      # debug build (not installed)
#   ./build.sh --run      # build, then (re)launch the app
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
RUN=0
for arg in "$@"; do
  case "$arg" in
    debug) CONFIG=debug ;;
    --run) RUN=1 ;;
  esac
done

APP_NAME=Tether
VERSION=$(sed -n 's/^version: *//p' VERSION 2>/dev/null || echo 0.1.0)
BUILD_NUMBER=$(date +%Y%m%d%H%M)
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos14.0"

OPT=(-O -wmo -Xlinker -dead_strip)
[[ "$CONFIG" == "debug" ]] && OPT=(-Onone -g)
mkdir -p build

echo "▶ swiftc ($CONFIG, $ARCH) — Tether $VERSION"
swiftc "${OPT[@]}" -parse-as-library -swift-version 5 \
  -target "$TARGET" -sdk "$SDK" -module-cache-path build/ModuleCache \
  $(find Sources/Tether -name '*.swift' | sort) \
  -o "build/$APP_NAME"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "build/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ ! -f build/AppIcon.icns || Scripts/make-icon.swift -nt build/AppIcon.icns ]]; then
  echo "▶ generating app icon"
  swiftc -O -target "$TARGET" -sdk "$SDK" -module-cache-path build/ModuleCache Scripts/make-icon.swift -o build/make-icon
  ./build/make-icon build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# A stable signing identity keeps the app's identity across rebuilds; falls back to ad-hoc.
SIGN_IDENTITY="${TETHER_SIGN_IDENTITY:-Omni Dev Signing}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
  SIGN_WITH="$SIGN_IDENTITY"
else
  SIGN_WITH="-"
fi
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign "$SIGN_WITH" "$APP" 2>/dev/null || codesign --force --sign - "$APP"
codesign --verify "$APP"
echo "✔ built $APP"

INSTALL_APP="${TETHER_INSTALL_DIR:-/Applications}/$APP_NAME.app"
if [[ "$CONFIG" != "debug" ]]; then
  WAS_RUNNING=0
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then WAS_RUNNING=1; pkill -x "$APP_NAME" 2>/dev/null || true; sleep 0.6; fi
  rm -rf "$INSTALL_APP"
  ditto --noextattr --noqtn "$APP" "$INSTALL_APP"
  codesign --verify "$INSTALL_APP"
  echo "✔ installed $INSTALL_APP"
  [[ $WAS_RUNNING -eq 1 ]] && RUN=1
fi

if [[ $RUN -eq 1 ]]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.4
  if [[ "$CONFIG" != "debug" && -d "$INSTALL_APP" ]]; then open "$INSTALL_APP"; else open "$APP"; fi
fi
