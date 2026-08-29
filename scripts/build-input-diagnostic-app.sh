#!/bin/sh

set -eu

JFC_CONFIGURATION="${1:-release}"
case "$JFC_CONFIGURATION" in
  debug|release) ;;
  *)
    echo "usage: scripts/build-input-diagnostic-app.sh [debug|release]" >&2
    exit 2
    ;;
esac

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_APP_BUNDLE="$JFC_REPOSITORY_ROOT/.build/JFC Input Diagnostic.app"
JFC_SIGNING_IDENTITY="${JFC_CODE_SIGN_IDENTITY:--}"
JFC_CACHE_ROOT="$JFC_REPOSITORY_ROOT/.build/LocalCaches"

mkdir -p "$JFC_CACHE_ROOT/clang" "$JFC_CACHE_ROOT/swiftpm" \
  "$JFC_CACHE_ROOT/configuration" "$JFC_CACHE_ROOT/security"
export CLANG_MODULE_CACHE_PATH="$JFC_CACHE_ROOT/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$JFC_CACHE_ROOT/clang"

cd "$JFC_REPOSITORY_ROOT"

set -- --disable-sandbox -c "$JFC_CONFIGURATION" \
  --cache-path "$JFC_CACHE_ROOT/swiftpm" \
  --config-path "$JFC_CACHE_ROOT/configuration" \
  --security-path "$JFC_CACHE_ROOT/security"

JFC_BIN_PATH=$(swift build "$@" --show-bin-path)
swift build "$@" --product jfc-input-diagnostic

rm -rf "$JFC_APP_BUNDLE"
mkdir -p "$JFC_APP_BUNDLE/Contents/MacOS"
cp "$JFC_BIN_PATH/jfc-input-diagnostic" \
  "$JFC_APP_BUNDLE/Contents/MacOS/jfc-input-diagnostic"
cp "$JFC_REPOSITORY_ROOT/Resources/InputDiagnostic/Info.plist" \
  "$JFC_APP_BUNDLE/Contents/Info.plist"

if [ "$JFC_SIGNING_IDENTITY" = "-" ]; then
  /usr/bin/codesign --force --sign - --options runtime \
    --requirements '=designated => identifier "io.e10n.jfc.input-diagnostic"' \
    "$JFC_APP_BUNDLE"
else
  /usr/bin/codesign --force --sign "$JFC_SIGNING_IDENTITY" --options runtime --timestamp \
    "$JFC_APP_BUNDLE"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$JFC_APP_BUNDLE"

echo "$JFC_APP_BUNDLE"
