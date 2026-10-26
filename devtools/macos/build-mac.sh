#!/bin/bash
# Commander macOS build: compiles the Cocoa version for one CPU and packs it into
# dist/Commander-<version>-macos-<arch>.dmg (based on .github/scripts/create_snapshot.sh).
# Usage: devtools/macos/build-mac.sh aarch64|x86_64
# Needs FPC + Lazarus (lazbuild on the PATH) and the third-party libraries in
# install/darwin/lib/<cpu> (https://github.com/doublecmd/external/raw/main/darwin.tar.gz).
set -e

export CPU_TARGET=${1:-aarch64}
export lcl=cocoa
export MACOSX_DEPLOYMENT_TARGET=11.0
case $CPU_TARGET in
  aarch64) ARCH=arm64 ;;
  x86_64)  ARCH=x86_64 ;;
  *) echo "Unknown CPU: $CPU_TARGET"; exit 1 ;;
esac

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

VER=$(grep -o "CommanderVersion = '[^']*'" src/platform/win/uselfupdate.pas | cut -d"'" -f2)
[ -n "$VER" ] || { echo "CommanderVersion not found"; exit 1; }
REVISION=$(git rev-list --count HEAD)
PACK_DIR=$ROOT/dist
DMG=$PACK_DIR/Commander-$VER-macos-$ARCH.dmg
BUILD_PACK_DIR=$(mktemp -d /tmp/commander-pack.XXXXXX)
echo "Commander $VER ($REVISION), $CPU_TARGET"

# Build components, plugins and the program
./build.sh components
./build.sh plugins
lazbuild src/doublecmd.lpi --bm=release --widgetset=$lcl --cpu=$CPU_TARGET

# The project target is "Commander" (the Windows exe name); the bundle and
# install/darwin/install.sh expect "doublecmd" inside Commander.app/Contents/MacOS
mv -f Commander doublecmd
if [ -d Commander.dSYM ]; then
  mv -f Commander.dSYM/Contents/Resources/DWARF/Commander doublecmd.dbg
  rm -rf Commander.dSYM
fi

# Debug line info (doublecmd.zdli), then strip
lazbuild tools/extractdwrflnfo.lpi
chmod a+x tools/extractdwrflnfo
if [ -f doublecmd.dbg ]; then
  tools/extractdwrflnfo doublecmd.dbg
fi
strip doublecmd

# Third-party libraries (libunrar etc.)
cp -a install/darwin/lib/$CPU_TARGET/*.dylib ./

# Application bundle
install/darwin/install.sh "$BUILD_PACK_DIR"
# Commander background image and install.txt
cp -R "$ROOT/devtools/macos/dmg/." "$BUILD_PACK_DIR/"
APP="$BUILD_PACK_DIR/Commander.app"
mv "$BUILD_PACK_DIR/doublecmd.app" "$APP"
# Commander icon (made from src/doublecmd.ico, CFBundleIconFile is "doublecmd")
cp -f "$ROOT/devtools/macos/Commander.icns" "$APP/Contents/Resources/doublecmd.icns"
PLIST="$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "Commander" "$PLIST"
plutil -replace CFBundleDisplayName -string "Commander" "$PLIST"
plutil -replace CFBundleIdentifier -string "com.tenax84.commander" "$PLIST"
plutil -replace CFBundleShortVersionString -string "$VER" "$PLIST"
plutil -replace CFBundleVersion -string "$REVISION" "$PLIST"
chmod 644 "$PLIST"
codesign --deep --force --verify --verbose --sign '-' "$APP"

# Disk image (hdiutil is flaky on the GitHub runners, so retry)
mkdir -p "$PACK_DIR"
rm -f "$DMG"
for TRY in 1 2 3 4 5; do
  echo "Creating the disk image, try $TRY ..."
  # Bug: https://github.com/actions/runner-images/issues/7522
  sudo pkill -9 XProtect >/dev/null 2>&1 || true
  while pgrep XProtect >/dev/null; do sleep 3; done
  if sudo install/darwin/create-dmg/create-dmg \
    --volname "Commander" \
    --volicon "$BUILD_PACK_DIR/.VolumeIcon.icns" \
    --background "$BUILD_PACK_DIR/.background/bg.jpg" \
    --window-pos 200 200 \
    --window-size 680 366 \
    --text-size 16 \
    --icon-size 128 \
    --icon "Commander.app" 110 120 \
    --app-drop-link 360 120 \
    --icon "install.txt" 566 123 \
    --icon ".background" 100 500 \
    "$DMG" "$BUILD_PACK_DIR/"; then
    break
  fi
  [ $TRY -lt 5 ] || { echo "create-dmg failed"; exit 1; }
  sleep 10
done
sudo chown "$(id -u)" "$DMG"

# Clean up for the next architecture
./clean.sh
rm -f *.dylib
sudo rm -rf "$BUILD_PACK_DIR"
ls -l "$DMG"
