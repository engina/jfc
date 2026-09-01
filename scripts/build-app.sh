#!/bin/sh

set -eu

JFC_CONFIGURATION="${1:-debug}"
case "$JFC_CONFIGURATION" in
  debug|release) ;;
  *)
    echo "usage: scripts/build-app.sh [debug|release]" >&2
    exit 2
    ;;
esac

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_APP_BUNDLE="$JFC_REPOSITORY_ROOT/.build/JFC.app"
JFC_LOGIN_ITEM_BUNDLE="$JFC_APP_BUNDLE/Contents/Library/LoginItems/JFC Login Item.app"
JFC_CLICK_AGENT_BUNDLE="$JFC_APP_BUNDLE/Contents/Helpers/JFC Click Agent.app"
JFC_SIGNING_IDENTITY="${JFC_CODE_SIGN_IDENTITY:--}"
JFC_ARCHITECTURE_LIST="${JFC_ARCHITECTURES:-}"
JFC_MARKETING_VERSION="${JFC_VERSION:-}"
JFC_BUILD_NUMBER="${JFC_BUILD_NUMBER:-}"
JFC_ICON="$JFC_REPOSITORY_ROOT/.build/GeneratedResources/JFC.icns"

if [ -n "$JFC_MARKETING_VERSION" ] && ! printf '%s\n' "$JFC_MARKETING_VERSION" \
  | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "JFC_VERSION must use MAJOR.MINOR.PATCH format." >&2
  exit 2
fi
if [ -n "$JFC_BUILD_NUMBER" ] && ! printf '%s\n' "$JFC_BUILD_NUMBER" \
  | /usr/bin/grep -Eq '^[1-9][0-9]*$'; then
  echo "JFC_BUILD_NUMBER must be a positive integer." >&2
  exit 2
fi

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
JFC_CLICK_AGENT_EXECUTABLE="$JFC_BIN_PATH/JFCClickAgent"

swift build "$@" --product JFCApp
swift build "$@" --product JFCLoginItem
swift build "$@" --product JFCClickAgent
"$JFC_REPOSITORY_ROOT/scripts/build-icon.sh" \
  "$JFC_REPOSITORY_ROOT/Resources/JFC-AppIcon.png" "$JFC_ICON"

rm -rf "$JFC_APP_BUNDLE"
mkdir -p "$JFC_APP_BUNDLE/Contents/MacOS"
mkdir -p "$JFC_APP_BUNDLE/Contents/Resources"
mkdir -p "$JFC_LOGIN_ITEM_BUNDLE/Contents/MacOS"
mkdir -p "$JFC_CLICK_AGENT_BUNDLE/Contents/MacOS"
mkdir -p "$JFC_CLICK_AGENT_BUNDLE/Contents/Resources"
cp "$JFC_EXECUTABLE" "$JFC_APP_BUNDLE/Contents/MacOS/JFC"
cp "$JFC_REPOSITORY_ROOT/Resources/JFC-Info.plist" "$JFC_APP_BUNDLE/Contents/Info.plist"
cp "$JFC_ICON" "$JFC_APP_BUNDLE/Contents/Resources/JFC.icns"
cp "$JFC_REPOSITORY_ROOT/Resources/GitHub-Invertocat-Black.pdf" \
  "$JFC_APP_BUNDLE/Contents/Resources/GitHub-Invertocat-Black.pdf"
cp "$JFC_REPOSITORY_ROOT/Resources/GitHub-Invertocat-White.pdf" \
  "$JFC_APP_BUNDLE/Contents/Resources/GitHub-Invertocat-White.pdf"
cp "$JFC_LOGIN_ITEM_EXECUTABLE" "$JFC_LOGIN_ITEM_BUNDLE/Contents/MacOS/JFCLoginItem"
cp "$JFC_REPOSITORY_ROOT/Resources/JFCLoginItem-Info.plist" "$JFC_LOGIN_ITEM_BUNDLE/Contents/Info.plist"
cp "$JFC_CLICK_AGENT_EXECUTABLE" "$JFC_CLICK_AGENT_BUNDLE/Contents/MacOS/JFCClickAgent"
cp "$JFC_REPOSITORY_ROOT/Resources/JFCClickAgent-Info.plist" \
  "$JFC_CLICK_AGENT_BUNDLE/Contents/Info.plist"
cp "$JFC_ICON" "$JFC_CLICK_AGENT_BUNDLE/Contents/Resources/JFC.icns"

for JFC_INFO_PLIST in \
  "$JFC_APP_BUNDLE/Contents/Info.plist" \
  "$JFC_LOGIN_ITEM_BUNDLE/Contents/Info.plist" \
  "$JFC_CLICK_AGENT_BUNDLE/Contents/Info.plist"; do
  if [ -n "$JFC_MARKETING_VERSION" ]; then
    /usr/libexec/PlistBuddy -c \
      "Set :CFBundleShortVersionString $JFC_MARKETING_VERSION" "$JFC_INFO_PLIST"
  fi
  if [ -n "$JFC_BUILD_NUMBER" ]; then
    /usr/libexec/PlistBuddy -c \
      "Set :CFBundleVersion $JFC_BUILD_NUMBER" "$JFC_INFO_PLIST"
  fi
done

if [ "$JFC_SIGNING_IDENTITY" = "-" ]; then
  # Give local ad-hoc builds stable designated requirements. Without these,
  # every rebuild is identified only by a new code hash and macOS can leave an
  # apparently enabled Accessibility entry attached to the previous build.
  /usr/bin/codesign --force --sign - --options runtime \
    --requirements '=designated => identifier "io.e10n.jfc.login-item"' \
    "$JFC_LOGIN_ITEM_BUNDLE"
  /usr/bin/codesign --force --sign - --options runtime \
    --requirements '=designated => identifier "io.e10n.jfc.click-agent"' \
    "$JFC_CLICK_AGENT_BUNDLE"
  /usr/bin/codesign --force --sign - --options runtime \
    --requirements '=designated => identifier "io.e10n.jfc"' \
    "$JFC_APP_BUNDLE"
else
  /usr/bin/codesign --force --sign "$JFC_SIGNING_IDENTITY" --options runtime --timestamp \
    "$JFC_LOGIN_ITEM_BUNDLE"
  /usr/bin/codesign --force --sign "$JFC_SIGNING_IDENTITY" --options runtime --timestamp \
    "$JFC_CLICK_AGENT_BUNDLE"
  /usr/bin/codesign --force --sign "$JFC_SIGNING_IDENTITY" --options runtime --timestamp \
    "$JFC_APP_BUNDLE"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$JFC_APP_BUNDLE"

echo "$JFC_APP_BUNDLE"
