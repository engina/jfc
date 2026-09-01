#!/bin/sh

set -eu

JFC_REQUESTED_VERSION=""
JFC_RUN_TESTS=1
for JFC_ARGUMENT in "$@"; do
  case "$JFC_ARGUMENT" in
    --no-test)
      JFC_RUN_TESTS=0
      ;;
    -*)
      echo "unknown option: $JFC_ARGUMENT" >&2
      echo "usage: scripts/release.sh [--no-test] [MAJOR.MINOR.PATCH]" >&2
      exit 2
      ;;
    *)
      if [ -n "$JFC_REQUESTED_VERSION" ]; then
        echo "usage: scripts/release.sh [--no-test] [MAJOR.MINOR.PATCH]" >&2
        exit 2
      fi
      JFC_REQUESTED_VERSION="$JFC_ARGUMENT"
      ;;
  esac
done

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_LOCAL_ENV="$JFC_REPOSITORY_ROOT/.env.local"
if [ -f "$JFC_LOCAL_ENV" ]; then
  set -a
  # The ignored file is resolved from the repository root.
  # shellcheck disable=SC1090
  . "$JFC_LOCAL_ENV"
  set +a
fi

JFC_SIGNING_IDENTITY="${JFC_CODE_SIGN_IDENTITY:-}"
JFC_EXPECTED_TEAM_ID="${JFC_DEVELOPER_TEAM_ID:-}"
JFC_NOTARY_KEYCHAIN_PROFILE="${JFC_NOTARY_PROFILE:-JFC-notary}"
JFC_RELEASE_ARCHITECTURES="${JFC_ARCHITECTURES:-arm64 x86_64}"
JFC_ALLOW_DIRTY_WORKTREE="${JFC_ALLOW_DIRTY:-0}"
JFC_NOTARY_RESULT=""
JFC_MANIFEST_TEMP=""

cleanup() {
  case "$JFC_NOTARY_RESULT" in
    /tmp/jfc-notary.*) /bin/rm -f -- "$JFC_NOTARY_RESULT" ;;
  esac
  case "$JFC_MANIFEST_TEMP" in
    "$JFC_REPOSITORY_ROOT"/dist/.jfc-release-manifest.*)
      /bin/rm -f -- "$JFC_MANIFEST_TEMP"
      ;;
  esac
}
trap cleanup EXIT HUP INT TERM

cd "$JFC_REPOSITORY_ROOT"
JFC_TEST_RELEASE=0
if [ -n "$(git status --porcelain)" ]; then
  if [ "$JFC_ALLOW_DIRTY_WORKTREE" != "1" ]; then
    echo "Refusing to release from a dirty worktree." >&2
    echo "Commit the release inputs, or set JFC_ALLOW_DIRTY=1 for a test release." >&2
    exit 1
  fi
  JFC_TEST_RELEASE=1
fi

JFC_VERSION=$(
  "$JFC_REPOSITORY_ROOT/scripts/release-version.sh" "$JFC_REQUESTED_VERSION"
)
JFC_BUILD_NUMBER="${JFC_BUILD_NUMBER:-$(git rev-list --count HEAD)}"
JFC_RELEASE_COMMIT=$(git rev-parse HEAD)
JFC_RELEASE_TAG="v$JFC_VERSION"
if ! printf '%s\n' "$JFC_BUILD_NUMBER" \
  | /usr/bin/grep -Eq '^[1-9][0-9]*$'; then
  echo "JFC_BUILD_NUMBER must be a positive integer." >&2
  exit 2
fi

JFC_DMG_PATH="$JFC_REPOSITORY_ROOT/dist/JFC-$JFC_VERSION.dmg"
JFC_MANIFEST_PATH="$JFC_REPOSITORY_ROOT/dist/JFC-$JFC_VERSION.release.json"
JFC_RELEASE_TAG_PRESENT=0
JFC_RELEASE_ARTIFACT_READY=0
JFC_RELEASE_CREATED_AT=""
JFC_SIGNED_TEAM_ID=""
JFC_NOTARY_ID=""
JFC_DMG_SHA256=""

if [ "$JFC_TEST_RELEASE" = "1" ]; then
  JFC_DMG_PATH="$JFC_REPOSITORY_ROOT/dist/JFC-$JFC_VERSION-test.dmg"
  JFC_MANIFEST_PATH=""
  echo "Dirty worktree: creating an untagged test release."
elif git show-ref --verify --quiet "refs/tags/$JFC_RELEASE_TAG"; then
  JFC_TAG_COMMIT=$(git rev-parse "$JFC_RELEASE_TAG^{commit}")
  if [ "$JFC_TAG_COMMIT" != "$JFC_RELEASE_COMMIT" ]; then
    echo "$JFC_RELEASE_TAG already identifies a different commit." >&2
    exit 1
  fi
  JFC_RELEASE_TAG_PRESENT=1
fi

manifest_value() {
  /usr/bin/plutil -extract "$1" raw "$JFC_MANIFEST_PATH" 2>/dev/null
}

verify_existing_release() {
  /usr/bin/plutil -convert xml1 -o /dev/null "$JFC_MANIFEST_PATH" \
    >/dev/null 2>&1 \
    && [ "$(manifest_value schemaVersion)" = "1" ] \
    && [ "$(manifest_value version)" = "$JFC_VERSION" ] \
    && [ "$(manifest_value build)" = "$JFC_BUILD_NUMBER" ] \
    && [ "$(manifest_value commit)" = "$JFC_RELEASE_COMMIT" ] \
    && [ "$(manifest_value tag)" = "$JFC_RELEASE_TAG" ] \
    && [ "$(manifest_value artifact)" = "$(basename -- "$JFC_DMG_PATH")" ] \
    && [ "$(manifest_value sha256)" = "$(/usr/bin/shasum -a 256 "$JFC_DMG_PATH" | /usr/bin/awk '{ print $1 }')" ] \
    && /usr/bin/xcrun stapler validate "$JFC_DMG_PATH" >/dev/null 2>&1 \
    && /usr/sbin/spctl --assess --type open --context context:primary-signature \
      "$JFC_DMG_PATH" >/dev/null 2>&1
}

create_release_tag() {
  if [ "$JFC_RELEASE_TAG_PRESENT" = "1" ]; then
    echo "Release tag already present: $JFC_RELEASE_TAG"
  else
    git tag -a "$JFC_RELEASE_TAG" -m "JFC $JFC_VERSION"
    JFC_RELEASE_TAG_PRESENT=1
    echo "Created release tag: $JFC_RELEASE_TAG"
  fi
}

write_release_manifest() {
  JFC_E2E_STATUS="$1"
  JFC_E2E_RUN="$2"
  JFC_E2E_COMPLETED_AT="$3"
  /bin/mkdir -p "$JFC_REPOSITORY_ROOT/dist"
  JFC_MANIFEST_TEMP=$(
    /usr/bin/mktemp "$JFC_REPOSITORY_ROOT/dist/.jfc-release-manifest.XXXXXX"
  )
  /usr/bin/plutil -create xml1 "$JFC_MANIFEST_TEMP"
  /usr/bin/plutil -insert schemaVersion -integer 1 "$JFC_MANIFEST_TEMP"
  /usr/bin/plutil -insert version -string "$JFC_VERSION" "$JFC_MANIFEST_TEMP"
  /usr/bin/plutil -insert build -string "$JFC_BUILD_NUMBER" "$JFC_MANIFEST_TEMP"
  /usr/bin/plutil -insert commit -string "$JFC_RELEASE_COMMIT" "$JFC_MANIFEST_TEMP"
  /usr/bin/plutil -insert tag -string "$JFC_RELEASE_TAG" "$JFC_MANIFEST_TEMP"
  /usr/bin/plutil -insert artifact -string "$(basename -- "$JFC_DMG_PATH")" \
    "$JFC_MANIFEST_TEMP"
  /usr/bin/plutil -insert sha256 -string "$JFC_DMG_SHA256" "$JFC_MANIFEST_TEMP"
  /usr/bin/plutil -insert notarizationID -string "$JFC_NOTARY_ID" \
    "$JFC_MANIFEST_TEMP"
  /usr/bin/plutil -insert teamIdentifier -string "$JFC_SIGNED_TEAM_ID" \
    "$JFC_MANIFEST_TEMP"
  /usr/bin/plutil -insert createdAt -string "$JFC_RELEASE_CREATED_AT" \
    "$JFC_MANIFEST_TEMP"
  /usr/bin/plutil -insert e2eStatus -string "$JFC_E2E_STATUS" \
    "$JFC_MANIFEST_TEMP"
  /usr/bin/plutil -insert e2eRun -string "$JFC_E2E_RUN" \
    "$JFC_MANIFEST_TEMP"
  /usr/bin/plutil -insert e2eCompletedAt -string "$JFC_E2E_COMPLETED_AT" \
    "$JFC_MANIFEST_TEMP"
  /usr/bin/plutil -convert json "$JFC_MANIFEST_TEMP"
  /bin/chmod 0644 "$JFC_MANIFEST_TEMP"
  /bin/mv -f -- "$JFC_MANIFEST_TEMP" "$JFC_MANIFEST_PATH"
  JFC_MANIFEST_TEMP=""
}

if [ "$JFC_TEST_RELEASE" = "0" ] \
  && [ -f "$JFC_DMG_PATH" ] \
  && [ -f "$JFC_MANIFEST_PATH" ]; then
  if ! verify_existing_release; then
    echo "Existing release artifact or manifest conflicts with $JFC_RELEASE_TAG." >&2
    echo "Refusing to overwrite an official release." >&2
    exit 1
  fi
  JFC_EXISTING_E2E_STATUS=$(manifest_value e2eStatus)
  case "$JFC_EXISTING_E2E_STATUS" in
    passed|pending|failed|skipped) ;;
    *)
      echo "Existing release manifest has invalid E2E status." >&2
      exit 1
      ;;
  esac
  JFC_DMG_SHA256=$(manifest_value sha256)
  JFC_NOTARY_ID=$(manifest_value notarizationID)
  JFC_SIGNED_TEAM_ID=$(manifest_value teamIdentifier)
  JFC_RELEASE_CREATED_AT=$(manifest_value createdAt)
  if [ -n "$JFC_EXPECTED_TEAM_ID" ] \
    && [ "$JFC_SIGNED_TEAM_ID" != "$JFC_EXPECTED_TEAM_ID" ]; then
    echo "Existing release manifest has an unexpected signing team." >&2
    exit 1
  fi
  JFC_RELEASE_ARTIFACT_READY=1

  if [ "$JFC_EXISTING_E2E_STATUS" = "passed" ] \
    || { [ "$JFC_RUN_TESTS" = "0" ] \
      && [ "$JFC_EXISTING_E2E_STATUS" = "skipped" ]; }; then
    create_release_tag
    echo "Release already complete: $JFC_DMG_PATH"
    exit 0
  fi
  echo "Reusing notarized artifact; E2E status is $JFC_EXISTING_E2E_STATUS."
fi

if [ "$JFC_TEST_RELEASE" = "0" ] \
  && [ "$JFC_RELEASE_ARTIFACT_READY" = "0" ] \
  && { [ -f "$JFC_DMG_PATH" ] || [ -f "$JFC_MANIFEST_PATH" ]; }; then
  echo "Incomplete prior release found; rebuilding $JFC_RELEASE_TAG."
fi

if [ "$JFC_RUN_TESTS" = "1" ]; then
  echo "Running source checks"
  /usr/bin/xcrun swift-format lint --recursive Sources Package.swift
  JFC_NODE_TESTS=$(/usr/bin/find E2E -name '*.test.mjs' -type f -print)
  if [ -z "$JFC_NODE_TESTS" ]; then
    echo "No E2E unit tests found." >&2
    exit 1
  fi
  printf '%s\n' "$JFC_NODE_TESTS" | /usr/bin/xargs /opt/homebrew/bin/node --test
fi

if [ "$JFC_RELEASE_ARTIFACT_READY" = "0" ]; then
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

  echo "Building JFC $JFC_VERSION ($JFC_BUILD_NUMBER)"
  JFC_CODE_SIGN_IDENTITY="$JFC_SIGNING_IDENTITY" \
  JFC_ARCHITECTURES="$JFC_RELEASE_ARCHITECTURES" \
  JFC_VERSION="$JFC_VERSION" \
  JFC_BUILD_NUMBER="$JFC_BUILD_NUMBER" \
    "$JFC_REPOSITORY_ROOT/scripts/build-app.sh" release

  JFC_APP_BUNDLE="$JFC_REPOSITORY_ROOT/.build/JFC.app"
  JFC_LOGIN_ITEM_BUNDLE="$JFC_APP_BUNDLE/Contents/Library/LoginItems/JFC Login Item.app"
  JFC_CLICK_AGENT_BUNDLE="$JFC_APP_BUNDLE/Contents/Helpers/JFC Click Agent.app"
  JFC_BUILT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$JFC_APP_BUNDLE/Contents/Info.plist")
  JFC_BUILT_BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "$JFC_APP_BUNDLE/Contents/Info.plist")
  if [ "$JFC_BUILT_VERSION" != "$JFC_VERSION" ] \
    || [ "$JFC_BUILT_BUILD_NUMBER" != "$JFC_BUILD_NUMBER" ]; then
    echo "Built app version does not match the requested release version." >&2
    exit 1
  fi

  /usr/bin/lipo "$JFC_APP_BUNDLE/Contents/MacOS/JFC" -verify_arch arm64 x86_64
  /usr/bin/lipo "$JFC_LOGIN_ITEM_BUNDLE/Contents/MacOS/JFCLoginItem" \
    -verify_arch arm64 x86_64
  /usr/bin/lipo "$JFC_CLICK_AGENT_BUNDLE/Contents/MacOS/JFCClickAgent" \
    -verify_arch arm64 x86_64
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$JFC_APP_BUNDLE"

  JFC_SIGNED_TEAM_ID=$(
    /usr/bin/codesign -d --verbose=4 "$JFC_APP_BUNDLE" 2>&1 \
      | /usr/bin/sed -n 's/^TeamIdentifier=//p'
  )
  if [ -n "$JFC_EXPECTED_TEAM_ID" ] \
    && [ "$JFC_SIGNED_TEAM_ID" != "$JFC_EXPECTED_TEAM_ID" ]; then
    echo "Signed app team ID does not match JFC_DEVELOPER_TEAM_ID." >&2
    exit 1
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
  JFC_DMG_SHA256=$(
    /usr/bin/shasum -a 256 "$JFC_DMG_PATH" | /usr/bin/awk '{ print $1 }'
  )
  JFC_RELEASE_CREATED_AT=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')
  printf '%s  %s\n' "$JFC_DMG_SHA256" "$JFC_DMG_PATH"
  JFC_RELEASE_ARTIFACT_READY=1

  if [ "$JFC_TEST_RELEASE" = "0" ]; then
    write_release_manifest pending "" ""
  fi
fi

JFC_E2E_STATUS=skipped
JFC_E2E_RUN=""
JFC_E2E_COMPLETED_AT=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')
if [ "$JFC_RUN_TESTS" = "1" ]; then
  JFC_E2E_TIMESTAMP=$(/bin/date -u '+%Y%m%dT%H%M%SZ')
  JFC_E2E_RUN="release-$JFC_VERSION-$(printf '%s' "$JFC_RELEASE_COMMIT" | /usr/bin/cut -c1-12)-$JFC_E2E_TIMESTAMP"
  JFC_E2E_RELEASE_ARTIFACTS="${JFC_E2E_ARTIFACTS_DIR:-$JFC_REPOSITORY_ROOT/E2E/Artifacts/$JFC_E2E_RUN}"
  echo "Qualifying the notarized DMG in a pristine VM"
  if ! JFC_E2E_DMG_PATH="$JFC_DMG_PATH" \
    JFC_E2E_ARTIFACTS_DIR="$JFC_E2E_RELEASE_ARTIFACTS" \
    "$JFC_REPOSITORY_ROOT/scripts/run-clean-e2e-matrix.sh" \
      "${JFC_E2E_VM_HOST:-mac-vm}"; then
    JFC_E2E_STATUS=failed
    JFC_E2E_COMPLETED_AT=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')
    if [ "$JFC_TEST_RELEASE" = "0" ]; then
      write_release_manifest "$JFC_E2E_STATUS" "$JFC_E2E_RUN" \
        "$JFC_E2E_COMPLETED_AT"
    fi
    echo "Release E2E qualification failed; no new tag was created." >&2
    exit 1
  fi
  JFC_E2E_STATUS=passed
  JFC_E2E_COMPLETED_AT=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')
else
  echo "Skipping release tests because --no-test was supplied."
fi

if [ "$JFC_TEST_RELEASE" = "0" ]; then
  write_release_manifest "$JFC_E2E_STATUS" "$JFC_E2E_RUN" \
    "$JFC_E2E_COMPLETED_AT"
  create_release_tag
  echo "Release manifest: $JFC_MANIFEST_PATH"
else
  echo "Test release complete; no manifest or Git tag was created."
fi

echo "Release ready: $JFC_DMG_PATH"
