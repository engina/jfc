#!/bin/sh

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_VM_HOST="${1:-mac-vm}"
JFC_STATE_PATH="${2:-$JFC_REPOSITORY_ROOT/.build/e2e-vm/current.json}"
JFC_LOCAL_ENV="$JFC_REPOSITORY_ROOT/.env.local"
JFC_UTMCTL="/Applications/UTM.app/Contents/MacOS/utmctl"

if [ -f "$JFC_LOCAL_ENV" ]; then
  set -a
  . "$JFC_LOCAL_ENV"
  set +a
fi

if [ -z "${JFC_E2E_VM_PASSWORD:-}" ]; then
  if [ ! -t 0 ]; then
    echo "JFC_E2E_VM_PASSWORD is required when stdin is not a terminal." >&2
    exit 1
  fi
  printf 'VM password: ' >&2
  /bin/stty -echo
  trap '/bin/stty echo' EXIT HUP INT TERM
  IFS= read -r JFC_E2E_VM_PASSWORD
  /bin/stty echo
  trap - EXIT HUP INT TERM
  printf '\n' >&2
fi
case "$JFC_E2E_VM_PASSWORD" in
  ''|*'
'*)
    echo "JFC_E2E_VM_PASSWORD must contain one non-empty line." >&2
    exit 1
    ;;
esac

if [ ! -f "$JFC_STATE_PATH" ]; then
  "$JFC_REPOSITORY_ROOT/scripts/create-e2e-vm.mjs" "$JFC_STATE_PATH"
fi

JFC_CLONE_UUID=$(
  /usr/bin/plutil -extract clone.uuid raw -o - "$JFC_STATE_PATH"
)
JFC_BASELINE_UUID=$(
  /usr/bin/plutil -extract baseline.uuid raw -o - "$JFC_STATE_PATH"
)
if [ "$JFC_CLONE_UUID" = "$JFC_BASELINE_UUID" ]; then
  echo "refusing to run beforeAll against the immutable baseline" >&2
  exit 1
fi
if [ "$("$JFC_UTMCTL" status "$JFC_CLONE_UUID")" != "started" ]; then
  echo "disposable VM is not started: $JFC_CLONE_UUID" >&2
  exit 1
fi
if [ "$("$JFC_UTMCTL" status "$JFC_BASELINE_UUID")" != "stopped" ]; then
  echo "immutable baseline is not stopped: $JFC_BASELINE_UUID" >&2
  exit 1
fi

"$JFC_REPOSITORY_ROOT/scripts/wait-for-e2e-displays.mjs" "$JFC_VM_HOST" 120
"$JFC_REPOSITORY_ROOT/scripts/stage-e2e-tools.sh" "$JFC_VM_HOST"
ssh "$JFC_VM_HOST" \
  'exec /bin/sh ~/jfc-e2e/repo/E2E/VM/start-appium.sh'

"$JFC_REPOSITORY_ROOT/scripts/install-e2e-jfc.sh" "$JFC_VM_HOST"
ssh "$JFC_VM_HOST" \
  'cd ~/jfc-e2e/repo && exec /opt/homebrew/bin/node E2E/InstallJFC/onboarding.mjs untrusted'

printf '%s\n' "$JFC_E2E_VM_PASSWORD" | ssh "$JFC_VM_HOST" \
  'IFS= read -r JFC_E2E_VM_PASSWORD; export JFC_E2E_VM_PASSWORD; cd ~/jfc-e2e/repo; exec /opt/homebrew/bin/node E2E/InstallJFC/accessibility-permission.mjs grant'
unset JFC_E2E_VM_PASSWORD

echo "beforeAll passed for disposable VM $JFC_CLONE_UUID"
