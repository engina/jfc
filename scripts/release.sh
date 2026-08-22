#!/bin/sh

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_LOCAL_ENV="$JFC_REPOSITORY_ROOT/.env.local"
if [ -f "$JFC_LOCAL_ENV" ]; then
  set -a
  . "$JFC_LOCAL_ENV"
  set +a
fi

JFC_SIGNING_IDENTITY="${JFC_CODE_SIGN_IDENTITY:-}"
JFC_EXPECTED_TEAM_ID="${JFC_DEVELOPER_TEAM_ID:-}"
JFC_NOTARY_KEYCHAIN_PROFILE="${JFC_NOTARY_PROFILE:-JFC-notary}"
JFC_RELEASE_ARCHITECTURES="${JFC_ARCHITECTURES:-arm64 x86_64}"
JFC_ALLOW_DIRTY_WORKTREE="${JFC_ALLOW_DIRTY:-0}"
JFC_NOTARY_RESULT=""

cleanup() {
  case "$JFC_NOTARY_RESULT" in
    /tmp/jfc-notary.*) /bin/rm -f -- "$JFC_NOTARY_RESULT" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

if [ -z "$JFC_SIGNING_IDENTITY" ]; then
  echo "JFC_CODE_SIGN_IDENTITY is required." >&2
  echo "Use the full Developer ID Application identity shown by:" >&2
  echo "  security find-identity -v -p codesigning" >&2
  exit 1
fi

JFC_MATCHING_IDENTITY=$(
  /usr/bin/security find-identity -v -p codesigning \
    | /usr/bin/grep -F "$JFC_SIGNING_IDENTITY" \
    | /usr/bin/grep 'Developer ID Application:' \
    | /usr/bin/head -n 1 \
    || true
)
if [ -z "$JFC_MATCHING_IDENTITY" ]; then
  echo "No valid Developer ID Application identity matches:" >&2
  echo "  $JFC_SIGNING_IDENTITY" >&2
  exit 1
fi

cd "$JFC_REPOSITORY_ROOT"
if [ "$JFC_ALLOW_DIRTY_WORKTREE" != "1" ] && [ -n "$(git status --porcelain)" ]; then
  echo "Refusing to release from a dirty worktree." >&2
  echo "Commit the release inputs, or set JFC_ALLOW_DIRTY=1 for a test release." >&2
  exit 1
fi

JFC_CODE_SIGN_IDENTITY="$JFC_SIGNING_IDENTITY" \
JFC_ARCHITECTURES="$JFC_RELEASE_ARCHITECTURES" \
  "$JFC_REPOSITORY_ROOT/scripts/build-app.sh" release

JFC_APP_BUNDLE="$JFC_REPOSITORY_ROOT/.build/JFC.app"
JFC_LOGIN_ITEM_BUNDLE="$JFC_APP_BUNDLE/Contents/Library/LoginItems/JFC Login Item.app"
JFC_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$JFC_APP_BUNDLE/Contents/Info.plist")
JFC_DMG_PATH="$JFC_REPOSITORY_ROOT/dist/JFC-$JFC_VERSION.dmg"

/usr/bin/lipo -verify_arch arm64 x86_64 "$JFC_APP_BUNDLE/Contents/MacOS/JFC"
/usr/bin/lipo -verify_arch arm64 x86_64 "$JFC_LOGIN_ITEM_BUNDLE/Contents/MacOS/JFCLoginItem"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$JFC_APP_BUNDLE"

if [ -n "$JFC_EXPECTED_TEAM_ID" ]; then
  JFC_SIGNED_TEAM_ID=$(
    /usr/bin/codesign -d --verbose=4 "$JFC_APP_BUNDLE" 2>&1 \
      | /usr/bin/sed -n 's/^TeamIdentifier=//p'
  )
  if [ "$JFC_SIGNED_TEAM_ID" != "$JFC_EXPECTED_TEAM_ID" ]; then
    echo "Signed app team ID does not match JFC_DEVELOPER_TEAM_ID." >&2
    exit 1
  fi
fi

JFC_CODE_SIGN_IDENTITY="$JFC_SIGNING_IDENTITY" \
  "$JFC_REPOSITORY_ROOT/scripts/package-dmg.sh" "$JFC_APP_BUNDLE" "$JFC_DMG_PATH"

JFC_NOTARY_RESULT=$(/usr/bin/mktemp /tmp/jfc-notary.XXXXXX)
if ! /usr/bin/xcrun notarytool submit "$JFC_DMG_PATH" \
  --keychain-profile "$JFC_NOTARY_KEYCHAIN_PROFILE" \
  --wait \
  --timeout 30m \
  --output-format plist >"$JFC_NOTARY_RESULT"; then
  /bin/cat "$JFC_NOTARY_RESULT" >&2
  echo "Notarization submission failed." >&2
  exit 1
fi

JFC_NOTARY_STATUS=$(/usr/bin/plutil -extract status raw "$JFC_NOTARY_RESULT")
JFC_NOTARY_ID=$(/usr/bin/plutil -extract id raw "$JFC_NOTARY_RESULT")
/bin/cat "$JFC_NOTARY_RESULT"

if [ "$JFC_NOTARY_STATUS" != "Accepted" ]; then
  /usr/bin/xcrun notarytool log "$JFC_NOTARY_ID" \
    --keychain-profile "$JFC_NOTARY_KEYCHAIN_PROFILE" >&2 || true
  echo "Notarization was not accepted." >&2
  exit 1
fi

/usr/bin/xcrun stapler staple -v "$JFC_DMG_PATH"
/usr/bin/xcrun stapler validate -v "$JFC_DMG_PATH"
/usr/sbin/spctl --assess --type open --context context:primary-signature \
  --verbose=4 "$JFC_DMG_PATH"
/usr/bin/shasum -a 256 "$JFC_DMG_PATH"

echo "Release ready: $JFC_DMG_PATH"
