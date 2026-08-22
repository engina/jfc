#!/bin/sh

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_ICON_SOURCE="${1:-$JFC_REPOSITORY_ROOT/Resources/JFC-AppIcon.png}"
JFC_ICON_OUTPUT="${2:-$JFC_REPOSITORY_ROOT/.build/GeneratedResources/JFC.icns}"
JFC_ICON_WORK=$(/usr/bin/mktemp -d /tmp/jfc-icon.XXXXXX)
JFC_ICONSET="$JFC_ICON_WORK/JFC.iconset"

cleanup() {
  case "$JFC_ICON_WORK" in
    /tmp/jfc-icon.*) /bin/rm -rf -- "$JFC_ICON_WORK" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

if [ ! -f "$JFC_ICON_SOURCE" ]; then
  echo "icon source not found: $JFC_ICON_SOURCE" >&2
  exit 1
fi

JFC_ICON_WIDTH=$(/usr/bin/sips -g pixelWidth "$JFC_ICON_SOURCE" \
  | /usr/bin/awk '/pixelWidth/ { print $2 }')
JFC_ICON_HEIGHT=$(/usr/bin/sips -g pixelHeight "$JFC_ICON_SOURCE" \
  | /usr/bin/awk '/pixelHeight/ { print $2 }')
if [ "$JFC_ICON_WIDTH" != "1024" ] || [ "$JFC_ICON_HEIGHT" != "1024" ]; then
  echo "icon source must be a 1024x1024 PNG: $JFC_ICON_SOURCE" >&2
  exit 1
fi

/bin/mkdir -p "$JFC_ICONSET" "$(dirname -- "$JFC_ICON_OUTPUT")"

render_icon() {
  JFC_ICON_SIZE="$1"
  JFC_ICON_FILENAME="$2"
  /usr/bin/sips -z "$JFC_ICON_SIZE" "$JFC_ICON_SIZE" "$JFC_ICON_SOURCE" \
    --out "$JFC_ICONSET/$JFC_ICON_FILENAME" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

/usr/bin/iconutil --convert icns --output "$JFC_ICON_OUTPUT" "$JFC_ICONSET"
echo "$JFC_ICON_OUTPUT"
