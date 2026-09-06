#!/bin/sh
# shellcheck disable=SC2016,SC2029

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_VM_HOST="${1:-mac-vm}"
JFC_LOCAL_ENV="$JFC_REPOSITORY_ROOT/.env.local"
JFC_INSTALL_WORK=$(/usr/bin/mktemp -d /tmp/jfc-e2e-install.XXXXXX)
JFC_DMG_MOUNT="$JFC_INSTALL_WORK/dmg"
JFC_GUEST_ROOT="jfc-e2e/install"
JFC_DMG_ATTACHED=0

jfc_cleanup() {
  if [ "$JFC_DMG_ATTACHED" = "1" ]; then
    /usr/bin/hdiutil detach -quiet -force "$JFC_DMG_MOUNT" || true
  fi
  case "$JFC_INSTALL_WORK" in
    /tmp/jfc-e2e-install.*) /bin/rm -rf -- "$JFC_INSTALL_WORK" ;;
  esac
}
trap jfc_cleanup EXIT HUP INT TERM

if [ -f "$JFC_LOCAL_ENV" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$JFC_LOCAL_ENV"
  set +a
fi

if [ -z "${JFC_DEVELOPER_TEAM_ID:-}" ]; then
  echo "JFC_DEVELOPER_TEAM_ID is required for VM installation." >&2
  exit 1
fi
if [ "$JFC_DEVELOPER_TEAM_ID" != "84TYRM74QA" ]; then
  echo "JFC_DEVELOPER_TEAM_ID does not match the VM install policy." >&2
  exit 1
fi

JFC_RELEASE_DMG=$(
  "$JFC_REPOSITORY_ROOT/scripts/validate-e2e-dmg.sh" \
    "${JFC_E2E_DMG_PATH:-}"
)
JFC_HOST_DMG_SHA=$(
  /usr/bin/shasum -a 256 "$JFC_RELEASE_DMG" | /usr/bin/awk '{ print $1 }'
)
/bin/mkdir -p "$JFC_DMG_MOUNT"
/usr/bin/hdiutil attach -quiet -readonly -nobrowse \
  -mountpoint "$JFC_DMG_MOUNT" "$JFC_RELEASE_DMG"
JFC_DMG_ATTACHED=1
JFC_APP="$JFC_DMG_MOUNT/JFC.app"

JFC_AGENT="$JFC_APP/Contents/Helpers/JFC Click Agent.app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$JFC_APP"
JFC_HOST_TEAM_ID=$(
  /usr/bin/codesign -d --verbose=4 "$JFC_APP" 2>&1 \
    | /usr/bin/sed -n 's/^TeamIdentifier=//p'
)
if [ "$JFC_HOST_TEAM_ID" != "$JFC_DEVELOPER_TEAM_ID" ]; then
  echo "DMG app signing team does not match JFC_DEVELOPER_TEAM_ID." >&2
  exit 1
fi
JFC_HOST_CDHASH=$(
  /usr/bin/codesign -d --verbose=4 "$JFC_APP" 2>&1 \
    | /usr/bin/sed -n 's/^CDHash=//p'
)
JFC_HOST_AGENT_CDHASH=$(
  /usr/bin/codesign -d --verbose=4 "$JFC_AGENT" 2>&1 \
    | /usr/bin/sed -n 's/^CDHash=//p'
)

ssh "$JFC_VM_HOST" "/bin/rm -rf '$JFC_GUEST_ROOT' && /bin/mkdir -p '$JFC_GUEST_ROOT'"
scp "$JFC_RELEASE_DMG" "$JFC_VM_HOST:$JFC_GUEST_ROOT/JFC.dmg"
JFC_GUEST_DMG_SHA=$(ssh "$JFC_VM_HOST" \
  "/usr/bin/shasum -a 256 '$JFC_GUEST_ROOT/JFC.dmg' | /usr/bin/awk '{ print \$1 }'")
if [ "$JFC_GUEST_DMG_SHA" != "$JFC_HOST_DMG_SHA" ]; then
  echo "guest DMG SHA-256 does not match the notarized host artifact" >&2
  exit 1
fi
ssh "$JFC_VM_HOST" '
    set -eu
    JFC_DMG="$HOME/jfc-e2e/install/JFC.dmg"
    JFC_MOUNT="$HOME/jfc-e2e/install/mount"
    /usr/bin/xcrun stapler validate "$JFC_DMG"
    /usr/sbin/spctl --assess --type open --context context:primary-signature "$JFC_DMG"
    /usr/bin/hdiutil verify "$JFC_DMG" >/dev/null
    /bin/mkdir -p "$JFC_MOUNT"
    /usr/bin/hdiutil attach -quiet -readonly -nobrowse -mountpoint "$JFC_MOUNT" "$JFC_DMG"
    trap '\''/usr/bin/hdiutil detach -quiet -force "$JFC_MOUNT" >/dev/null 2>&1 || true'\'' EXIT HUP INT TERM
    /usr/bin/ditto "$JFC_MOUNT/JFC.app" "$HOME/jfc-e2e/install/JFC.app"
    /usr/bin/hdiutil detach -quiet "$JFC_MOUNT"
    trap - EXIT HUP INT TERM
    /bin/rmdir "$JFC_MOUNT"
  '

if [ "$JFC_DMG_ATTACHED" = "1" ]; then
  /usr/bin/hdiutil detach -quiet "$JFC_DMG_MOUNT"
  JFC_DMG_ATTACHED=0
fi

if ssh "$JFC_VM_HOST" '/usr/bin/pgrep -x JFC >/dev/null 2>&1'; then
  ssh "$JFC_VM_HOST" \
    "/usr/bin/osascript -e 'tell application id \"io.e10n.jfc\" to quit'"
  JFC_ATTEMPT=0
  while ssh "$JFC_VM_HOST" '/usr/bin/pgrep -x JFC >/dev/null 2>&1'; do
    JFC_ATTEMPT=$((JFC_ATTEMPT + 1))
    if [ "$JFC_ATTEMPT" -ge 40 ]; then
      echo "installed JFC did not quit" >&2
      exit 1
    fi
    /bin/sleep 0.25
  done
fi

JFC_INSTALL_RESULT=$(ssh "$JFC_VM_HOST" \
  '/usr/bin/sudo -n /usr/local/libexec/jfc-e2e-install-app install')
echo "$JFC_INSTALL_RESULT"

JFC_GUEST_CDHASH=$(ssh "$JFC_VM_HOST" \
  "/usr/bin/codesign -d --verbose=4 /Applications/JFC.app 2>&1 | /usr/bin/sed -n 's/^CDHash=//p'")
if [ "$JFC_GUEST_CDHASH" != "$JFC_HOST_CDHASH" ]; then
  echo "installed JFC CDHash does not match the host build" >&2
  exit 1
fi
JFC_GUEST_AGENT_CDHASH=$(ssh "$JFC_VM_HOST" \
  "/usr/bin/codesign -d --verbose=4 '/Applications/JFC.app/Contents/Helpers/JFC Click Agent.app' 2>&1 | /usr/bin/sed -n 's/^CDHash=//p'")
if [ "$JFC_GUEST_AGENT_CDHASH" != "$JFC_HOST_AGENT_CDHASH" ]; then
  echo "installed JFC click-agent CDHash does not match the host build" >&2
  exit 1
fi

/opt/homebrew/bin/node -e '
  const fs = require("node:fs");
  const [filename, artifact, sha256, teamID, appCDHash, agentCDHash] = process.argv.slice(1);
  fs.writeFileSync(filename, `${JSON.stringify({
    schemaVersion: 1,
    artifact,
    sha256,
    teamID,
    appCDHash,
    agentCDHash,
  }, null, 2)}\n`);
' "$JFC_INSTALL_WORK/installation-artifact.json" \
  "$(basename -- "$JFC_RELEASE_DMG")" "$JFC_HOST_DMG_SHA" \
  "$JFC_HOST_TEAM_ID" "$JFC_GUEST_CDHASH" "$JFC_GUEST_AGENT_CDHASH"
scp "$JFC_INSTALL_WORK/installation-artifact.json" \
  "$JFC_VM_HOST:$JFC_GUEST_ROOT/installation-artifact.json"

ssh "$JFC_VM_HOST" \
  '/usr/bin/defaults write io.e10n.jfc JFCEnabled -bool true; /usr/bin/open -na /Applications/JFC.app'
JFC_ATTEMPT=0
while ! ssh "$JFC_VM_HOST" '/usr/bin/pgrep -x JFC >/dev/null 2>&1'; do
  JFC_ATTEMPT=$((JFC_ATTEMPT + 1))
  if [ "$JFC_ATTEMPT" -ge 40 ]; then
    echo "freshly installed JFC did not launch" >&2
    exit 1
  fi
  /bin/sleep 0.25
done

JFC_ATTEMPT=0
while ! ssh "$JFC_VM_HOST" '/usr/bin/pgrep -x JFCClickAgent >/dev/null 2>&1'; do
  JFC_ATTEMPT=$((JFC_ATTEMPT + 1))
  if [ "$JFC_ATTEMPT" -ge 40 ]; then
    echo "freshly installed JFC click agent did not launch" >&2
    exit 1
  fi
  /bin/sleep 0.25
done

echo "launched exact VM build with click agent cdhash=$JFC_GUEST_AGENT_CDHASH"
echo "installed notarized DMG sha256=$JFC_HOST_DMG_SHA"
