#!/bin/sh

set -eu

JFC_CONFIGURATION="${1:-debug}"
case "$JFC_CONFIGURATION" in
  debug|release) ;;
  *)
    echo "usage: Scripts/build-app.sh [debug|release]" >&2
    exit 2
    ;;
esac

JFC_REPOSITORY_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
JFC_APP_BUNDLE="$JFC_REPOSITORY_ROOT/.build/JFC.app"
JFC_EXECUTABLE="$JFC_REPOSITORY_ROOT/.build/$JFC_CONFIGURATION/JFCApp"
JFC_LOGIN_ITEM_BUNDLE="$JFC_APP_BUNDLE/Contents/Library/LoginItems/JFC Login Item.app"
JFC_LOGIN_ITEM_EXECUTABLE="$JFC_REPOSITORY_ROOT/.build/$JFC_CONFIGURATION/JFCLoginItem"
JFC_SIGNING_IDENTITY="${JFC_CODE_SIGN_IDENTITY:--}"

cd "$JFC_REPOSITORY_ROOT"
swift build --disable-sandbox -c "$JFC_CONFIGURATION" --product JFCApp
swift build --disable-sandbox -c "$JFC_CONFIGURATION" --product JFCLoginItem

rm -rf "$JFC_APP_BUNDLE"
mkdir -p "$JFC_APP_BUNDLE/Contents/MacOS"
mkdir -p "$JFC_APP_BUNDLE/Contents/Resources"
mkdir -p "$JFC_LOGIN_ITEM_BUNDLE/Contents/MacOS"
cp "$JFC_EXECUTABLE" "$JFC_APP_BUNDLE/Contents/MacOS/JFC"
cp "$JFC_REPOSITORY_ROOT/Resources/JFC-Info.plist" "$JFC_APP_BUNDLE/Contents/Info.plist"
cp "$JFC_LOGIN_ITEM_EXECUTABLE" "$JFC_LOGIN_ITEM_BUNDLE/Contents/MacOS/JFCLoginItem"
cp "$JFC_REPOSITORY_ROOT/Resources/JFCLoginItem-Info.plist" "$JFC_LOGIN_ITEM_BUNDLE/Contents/Info.plist"

if [ "$JFC_SIGNING_IDENTITY" = "-" ]; then
  # Give local ad-hoc builds stable designated requirements. Without these,
  # every rebuild is identified only by a new code hash and macOS can leave an
  # apparently enabled Accessibility entry attached to the previous build.
  /usr/bin/codesign --force --sign - \
    --requirements '=designated => identifier "com.justfuckingclick.JFC.LoginItem"' \
    "$JFC_LOGIN_ITEM_BUNDLE"
  /usr/bin/codesign --force --sign - \
    --requirements '=designated => identifier "com.justfuckingclick.JFC"' \
    "$JFC_APP_BUNDLE"
else
  /usr/bin/codesign --force --sign "$JFC_SIGNING_IDENTITY" "$JFC_LOGIN_ITEM_BUNDLE"
  /usr/bin/codesign --force --sign "$JFC_SIGNING_IDENTITY" "$JFC_APP_BUNDLE"
fi

echo "$JFC_APP_BUNDLE"
