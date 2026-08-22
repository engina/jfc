#!/bin/sh

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_APP_BUNDLE="${1:-$JFC_REPOSITORY_ROOT/.build/JFC.app}"
JFC_SIGNING_IDENTITY="${JFC_CODE_SIGN_IDENTITY:--}"
JFC_DMG_BACKGROUND="${JFC_DMG_BACKGROUND:-$JFC_REPOSITORY_ROOT/Resources/DMG/background.png}"
JFC_DMG_STYLE="${JFC_DMG_STYLE:-1}"

if [ ! -d "$JFC_APP_BUNDLE" ]; then
  echo "app bundle not found: $JFC_APP_BUNDLE" >&2
  exit 1
fi

JFC_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$JFC_APP_BUNDLE/Contents/Info.plist")
JFC_DMG_PATH="${2:-$JFC_REPOSITORY_ROOT/dist/JFC-$JFC_VERSION.dmg}"
JFC_DMG_DIRECTORY=$(dirname -- "$JFC_DMG_PATH")
JFC_DMG_WORK=$(/usr/bin/mktemp -d /tmp/jfc-dmg.XXXXXX)
JFC_DMG_ROOT="$JFC_DMG_WORK/root"
JFC_DMG_READ_WRITE="$JFC_DMG_WORK/JFC-read-write.dmg"
JFC_DMG_MOUNT="$JFC_DMG_WORK/mount"
JFC_DMG_BUILD_SUFFIX=${JFC_DMG_WORK##*.}
JFC_DMG_BUILD_VOLUME="JFC-$JFC_DMG_BUILD_SUFFIX"
JFC_DMG_ATTACHED=0

cleanup() {
  if [ "$JFC_DMG_ATTACHED" = "1" ]; then
    /usr/bin/hdiutil detach -quiet -force "$JFC_DMG_MOUNT" || true
  fi
  case "$JFC_DMG_WORK" in
    /tmp/jfc-dmg.*) /bin/rm -rf -- "$JFC_DMG_WORK" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

/bin/mkdir -p "$JFC_DMG_ROOT" "$JFC_DMG_DIRECTORY"
/usr/bin/ditto "$JFC_APP_BUNDLE" "$JFC_DMG_ROOT/JFC.app"
/bin/ln -s /Applications "$JFC_DMG_ROOT/Applications"

if [ "$JFC_DMG_STYLE" = "1" ] && [ -f "$JFC_DMG_BACKGROUND" ]; then
  JFC_BACKGROUND_WIDTH=$(/usr/bin/sips -g pixelWidth "$JFC_DMG_BACKGROUND" \
    | /usr/bin/awk '/pixelWidth/ { print $2 }')
  JFC_BACKGROUND_HEIGHT=$(/usr/bin/sips -g pixelHeight "$JFC_DMG_BACKGROUND" \
    | /usr/bin/awk '/pixelHeight/ { print $2 }')
  if [ "$JFC_BACKGROUND_WIDTH" != "660" ] || [ "$JFC_BACKGROUND_HEIGHT" != "400" ]; then
    echo "DMG background must be a 660x400 PNG: $JFC_DMG_BACKGROUND" >&2
    exit 1
  fi

  /bin/mkdir -p "$JFC_DMG_ROOT/.background" "$JFC_DMG_MOUNT"
  /usr/bin/ditto "$JFC_DMG_BACKGROUND" "$JFC_DMG_ROOT/.background/background.png"
  /usr/bin/hdiutil create \
    -quiet \
    -ov \
    -format UDRW \
    -volname "$JFC_DMG_BUILD_VOLUME" \
    -srcfolder "$JFC_DMG_ROOT" \
    "$JFC_DMG_READ_WRITE"
  /usr/bin/hdiutil attach \
    -quiet \
    -readwrite \
    -noautoopen \
    -noverify \
    -mountpoint "$JFC_DMG_MOUNT" \
    "$JFC_DMG_READ_WRITE"
  JFC_DMG_ATTACHED=1

  /usr/bin/osascript "$JFC_REPOSITORY_ROOT/scripts/style-dmg.applescript" \
    "$JFC_DMG_MOUNT" background.png
  JFC_DMG_METADATA_ATTEMPTS=0
  while [ ! -s "$JFC_DMG_MOUNT/.DS_Store" ] && [ "$JFC_DMG_METADATA_ATTEMPTS" -lt 10 ]; do
    /bin/sleep 1
    JFC_DMG_METADATA_ATTEMPTS=$((JFC_DMG_METADATA_ATTEMPTS + 1))
  done
  if [ ! -s "$JFC_DMG_MOUNT/.DS_Store" ]; then
    echo "Finder did not persist the DMG layout metadata" >&2
    exit 1
  fi
  /usr/sbin/diskutil rename "$JFC_DMG_MOUNT" JFC >/dev/null
  /bin/sync
  /usr/bin/hdiutil detach -quiet "$JFC_DMG_MOUNT"
  JFC_DMG_ATTACHED=0

  /usr/bin/hdiutil convert \
    -quiet \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$JFC_DMG_PATH" \
    "$JFC_DMG_READ_WRITE"
else
  /usr/bin/hdiutil create \
    -quiet \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    -volname JFC \
    -srcfolder "$JFC_DMG_ROOT" \
    "$JFC_DMG_PATH"
fi

if [ "$JFC_SIGNING_IDENTITY" != "-" ]; then
  /usr/bin/codesign --force --sign "$JFC_SIGNING_IDENTITY" --timestamp "$JFC_DMG_PATH"
  /usr/bin/codesign --verify --strict --verbose=2 "$JFC_DMG_PATH"
fi

/usr/bin/hdiutil verify "$JFC_DMG_PATH"
echo "$JFC_DMG_PATH"
