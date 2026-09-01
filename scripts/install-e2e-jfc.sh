#!/bin/sh

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_VM_HOST="${1:-mac-vm}"
JFC_LOCAL_ENV="$JFC_REPOSITORY_ROOT/.env.local"
JFC_INSTALL_WORK=$(/usr/bin/mktemp -d /tmp/jfc-e2e-install.XXXXXX)
JFC_ARCHIVE="$JFC_INSTALL_WORK/JFC.zip"
JFC_GUEST_ROOT="jfc-e2e/install"

jfc_cleanup() {
  case "$JFC_INSTALL_WORK" in
    /tmp/jfc-e2e-install.*) /bin/rm -rf -- "$JFC_INSTALL_WORK" ;;
  esac
}
trap jfc_cleanup EXIT HUP INT TERM

if [ -f "$JFC_LOCAL_ENV" ]; then
  set -a
  . "$JFC_LOCAL_ENV"
  set +a
fi

if [ -z "${JFC_CODE_SIGN_IDENTITY:-}" ]; then
  echo "JFC_CODE_SIGN_IDENTITY is required for VM installation." >&2
  exit 1
fi
if [ -z "${JFC_DEVELOPER_TEAM_ID:-}" ]; then
  echo "JFC_DEVELOPER_TEAM_ID is required for VM installation." >&2
  exit 1
fi
if [ "$JFC_DEVELOPER_TEAM_ID" != "84TYRM74QA" ]; then
  echo "JFC_DEVELOPER_TEAM_ID does not match the VM install policy." >&2
  exit 1
fi

JFC_CODE_SIGN_IDENTITY="$JFC_CODE_SIGN_IDENTITY" \
JFC_ARCHITECTURES=arm64 \
  "$JFC_REPOSITORY_ROOT/scripts/build-app.sh" release >/dev/null

JFC_APP="$JFC_REPOSITORY_ROOT/.build/JFC.app"
JFC_AGENT="$JFC_APP/Contents/Helpers/JFC Click Agent.app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$JFC_APP"
JFC_HOST_CDHASH=$(
  /usr/bin/codesign -d --verbose=4 "$JFC_APP" 2>&1 \
    | /usr/bin/sed -n 's/^CDHash=//p'
)
JFC_HOST_AGENT_CDHASH=$(
  /usr/bin/codesign -d --verbose=4 "$JFC_AGENT" 2>&1 \
    | /usr/bin/sed -n 's/^CDHash=//p'
)
/usr/bin/ditto -c -k --keepParent "$JFC_APP" "$JFC_ARCHIVE"

ssh "$JFC_VM_HOST" "/bin/rm -rf '$JFC_GUEST_ROOT' && /bin/mkdir -p '$JFC_GUEST_ROOT'"
scp "$JFC_ARCHIVE" "$JFC_VM_HOST:$JFC_GUEST_ROOT/JFC.zip"
ssh "$JFC_VM_HOST" \
  "/usr/bin/ditto -x -k '$JFC_GUEST_ROOT/JFC.zip' '$JFC_GUEST_ROOT' && /bin/rm '$JFC_GUEST_ROOT/JFC.zip'"

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
