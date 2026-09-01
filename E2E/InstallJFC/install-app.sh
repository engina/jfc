#!/bin/sh

set -eu

JFC_ACTION="${1:-}"
JFC_EXPECTED_BUNDLE_ID="io.e10n.jfc"
JFC_EXPECTED_TEAM_ID="84TYRM74QA"
JFC_TARGET="/Applications/JFC.app"
JFC_INSTALLING="/Applications/.JFC.e2e.installing.app"
JFC_PREVIOUS="/Applications/.JFC.e2e.previous.app"

if [ "$(/usr/bin/id -u)" -ne 0 ]; then
  echo "run this helper through its configured sudo rule" >&2
  exit 1
fi

case "$JFC_ACTION" in
  install|uninstall) ;;
  *)
    echo "usage: jfc-e2e-install-app install|uninstall" >&2
    exit 2
    ;;
esac

jfc_remove_temporary_paths() {
  /bin/rm -rf -- "$JFC_INSTALLING"
}
trap jfc_remove_temporary_paths EXIT HUP INT TERM

if [ "$JFC_ACTION" = "uninstall" ]; then
  /bin/rm -rf -- "$JFC_TARGET" "$JFC_INSTALLING" "$JFC_PREVIOUS"
  echo "removed $JFC_TARGET"
  exit 0
fi

JFC_CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console)
case "$JFC_CONSOLE_USER" in
  ''|root|loginwindow|*[!A-Za-z0-9._-]*)
    echo "could not determine a safe logged-in console user" >&2
    exit 1
    ;;
esac

JFC_SOURCE="/Users/$JFC_CONSOLE_USER/jfc-e2e/install/JFC.app"
if [ ! -d "$JFC_SOURCE" ] || [ -L "$JFC_SOURCE" ]; then
  echo "staged app not found: $JFC_SOURCE" >&2
  exit 1
fi
if [ -n "$(/usr/bin/find "$JFC_SOURCE" -type l -print -quit)" ]; then
  echo "staged app must not contain symbolic links" >&2
  exit 1
fi
if [ "$(/usr/bin/stat -f '%Su' "$JFC_SOURCE")" != "$JFC_CONSOLE_USER" ]; then
  echo "staged app is not owned by the console user" >&2
  exit 1
fi

jfc_verify_app() {
  JFC_APP="$1"
  if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$JFC_APP"; then
    echo "code-signature verification failed: $JFC_APP" >&2
    return 1
  fi

  JFC_BUNDLE_ID=$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
      "$JFC_APP/Contents/Info.plist"
  )
  JFC_EXECUTABLE=$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
      "$JFC_APP/Contents/Info.plist"
  )
  JFC_TEAM_ID=$(
    /usr/bin/codesign -d --verbose=4 "$JFC_APP" 2>&1 \
      | /usr/bin/sed -n 's/^TeamIdentifier=//p'
  )

  if [ "$JFC_BUNDLE_ID" != "$JFC_EXPECTED_BUNDLE_ID" ]; then
    echo "unexpected bundle identifier: $JFC_BUNDLE_ID" >&2
    return 1
  fi
  if [ "$JFC_EXECUTABLE" != "JFC" ]; then
    echo "unexpected bundle executable: $JFC_EXECUTABLE" >&2
    return 1
  fi
  if [ "$JFC_TEAM_ID" != "$JFC_EXPECTED_TEAM_ID" ]; then
    echo "unexpected signing team: $JFC_TEAM_ID" >&2
    return 1
  fi
}

jfc_verify_app "$JFC_SOURCE"
/bin/rm -rf -- "$JFC_INSTALLING" "$JFC_PREVIOUS"
/usr/bin/ditto "$JFC_SOURCE" "$JFC_INSTALLING"
/usr/sbin/chown -R root:wheel "$JFC_INSTALLING"
jfc_verify_app "$JFC_INSTALLING"

if [ -e "$JFC_TARGET" ]; then
  /bin/mv "$JFC_TARGET" "$JFC_PREVIOUS"
fi

if ! /bin/mv "$JFC_INSTALLING" "$JFC_TARGET"; then
  if [ -e "$JFC_PREVIOUS" ] && [ ! -e "$JFC_TARGET" ]; then
    /bin/mv "$JFC_PREVIOUS" "$JFC_TARGET"
  fi
  exit 1
fi

if ! jfc_verify_app "$JFC_TARGET"; then
  /bin/rm -rf -- "$JFC_TARGET"
  if [ -e "$JFC_PREVIOUS" ]; then
    /bin/mv "$JFC_PREVIOUS" "$JFC_TARGET"
  fi
  exit 1
fi

/bin/rm -rf -- "$JFC_PREVIOUS"
JFC_VERSION=$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$JFC_TARGET/Contents/Info.plist"
)
JFC_BUILD=$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "$JFC_TARGET/Contents/Info.plist"
)
JFC_CDHASH=$(
  /usr/bin/codesign -d --verbose=4 "$JFC_TARGET" 2>&1 \
    | /usr/bin/sed -n 's/^CDHash=//p'
)
echo "installed $JFC_TARGET version=$JFC_VERSION build=$JFC_BUILD cdhash=$JFC_CDHASH"
