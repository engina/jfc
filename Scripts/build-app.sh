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

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_APP_BUNDLE="$JFC_REPOSITORY_ROOT/.build/JFC.app"
JFC_LOGIN_ITEM_BUNDLE="$JFC_APP_BUNDLE/Contents/Library/LoginItems/JFC Login Item.app"
JFC_SIGNING_IDENTITY="${JFC_CODE_SIGN_IDENTITY:--}"
JFC_ARCHITECTURE_LIST="${JFC_ARCHITECTURES:-}"
JFC_ICON="$JFC_REPOSITORY_ROOT/.build/GeneratedResources/JFC.icns"

cd "$JFC_REPOSITORY_ROOT"

set -- --disable-sandbox -c "$JFC_CONFIGURATION"
for JFC_ARCHITECTURE in $JFC_ARCHITECTURE_LIST; do
  case "$JFC_ARCHITECTURE" in
    arm64|x86_64) ;;
    *)
      echo "unsupported architecture: $JFC_ARCHITECTURE" >&2
      exit 2
      ;;
  esac
  set -- "$@" --arch "$JFC_ARCHITECTURE"
done

JFC_BIN_PATH=$(swift build "$@" --show-bin-path)
JFC_EXECUTABLE="$JFC_BIN_PATH/JFCApp"
JFC_LOGIN_ITEM_EXECUTABLE="$JFC_BIN_PATH/JFCLoginItem"

swift build "$@" --product JFCApp
swift build "$@" --product JFCLoginItem
"$JFC_REPOSITORY_ROOT/Scripts/build-icon.sh" \
  "$JFC_REPOSITORY_ROOT/Resources/JFC-AppIcon.png" "$JFC_ICON"

rm -rf "$JFC_APP_BUNDLE"
mkdir -p "$JFC_APP_BUNDLE/Contents/MacOS"
mkdir -p "$JFC_APP_BUNDLE/Contents/Resources"
mkdir -p "$JFC_LOGIN_ITEM_BUNDLE/Contents/MacOS"
cp "$JFC_EXECUTABLE" "$JFC_APP_BUNDLE/Contents/MacOS/JFC"
cp "$JFC_REPOSITORY_ROOT/Resources/JFC-Info.plist" "$JFC_APP_BUNDLE/Contents/Info.plist"
cp "$JFC_ICON" "$JFC_APP_BUNDLE/Contents/Resources/JFC.icns"
cp "$JFC_REPOSITORY_ROOT/Resources/GitHub-Invertocat-Black.pdf" \
  "$JFC_APP_BUNDLE/Contents/Resources/GitHub-Invertocat-Black.pdf"
cp "$JFC_REPOSITORY_ROOT/Resources/GitHub-Invertocat-White.pdf" \
  "$JFC_APP_BUNDLE/Contents/Resources/GitHub-Invertocat-White.pdf"
cp "$JFC_LOGIN_ITEM_EXECUTABLE" "$JFC_LOGIN_ITEM_BUNDLE/Contents/MacOS/JFCLoginItem"
cp "$JFC_REPOSITORY_ROOT/Resources/JFCLoginItem-Info.plist" "$JFC_LOGIN_ITEM_BUNDLE/Contents/Info.plist"

if [ "$JFC_SIGNING_IDENTITY" = "-" ]; then
  # Give local ad-hoc builds stable designated requirements. Without these,
  # every rebuild is identified only by a new code hash and macOS can leave an
  # apparently enabled Accessibility entry attached to the previous build.
  /usr/bin/codesign --force --sign - --options runtime \
    --requirements '=designated => identifier "com.justfuckingclick.JFC.LoginItem"' \
    "$JFC_LOGIN_ITEM_BUNDLE"
  /usr/bin/codesign --force --sign - --options runtime \
    --requirements '=designated => identifier "com.justfuckingclick.JFC"' \
    "$JFC_APP_BUNDLE"
else
  /usr/bin/codesign --force --sign "$JFC_SIGNING_IDENTITY" --options runtime --timestamp \
    "$JFC_LOGIN_ITEM_BUNDLE"
  /usr/bin/codesign --force --sign "$JFC_SIGNING_IDENTITY" --options runtime --timestamp \
    "$JFC_APP_BUNDLE"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$JFC_APP_BUNDLE"

echo "$JFC_APP_BUNDLE"
