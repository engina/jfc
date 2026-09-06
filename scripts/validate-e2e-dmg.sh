#!/bin/sh

set -eu

JFC_DMG_PATH="${1:-${JFC_E2E_DMG_PATH:-}}"

if [ -z "$JFC_DMG_PATH" ]; then
  echo "JFC_E2E_DMG_PATH is required; clean E2E runs install only a notarized DMG." >&2
  exit 2
fi
if [ ! -f "$JFC_DMG_PATH" ]; then
  echo "notarized E2E DMG not found: $JFC_DMG_PATH" >&2
  exit 2
fi

JFC_DMG_PATH=$(
  CDPATH='' cd -- "$(dirname -- "$JFC_DMG_PATH")" \
    && printf '%s/%s\n' "$PWD" "$(basename -- "$JFC_DMG_PATH")"
)

/usr/bin/xcrun stapler validate "$JFC_DMG_PATH" >&2
/usr/sbin/spctl --assess --type open --context context:primary-signature \
  "$JFC_DMG_PATH"
/usr/bin/hdiutil verify "$JFC_DMG_PATH" >/dev/null

printf '%s\n' "$JFC_DMG_PATH"
