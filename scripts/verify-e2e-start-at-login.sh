#!/bin/sh
# shellcheck disable=SC2029

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_VM_HOST="${1:-mac-vm}"
JFC_STATE_PATH="${2:-$JFC_REPOSITORY_ROOT/.build/e2e-vm/current.json}"
JFC_TIMESTAMP=$(/bin/date -u '+%Y%m%dT%H%M%SZ')
JFC_ARTIFACT_DIR="${3:-$JFC_REPOSITORY_ROOT/E2E/Artifacts/start-at-login-$JFC_TIMESTAMP}"
JFC_REGISTRATION_ENABLED=0

if [ ! -f "$JFC_STATE_PATH" ]; then
  echo "VM state not found: $JFC_STATE_PATH" >&2
  exit 1
fi

/bin/mkdir -p "$JFC_ARTIFACT_DIR"

jfc_cleanup() {
  JFC_STATUS=$?
  trap - EXIT HUP INT TERM
  if [ "$JFC_REGISTRATION_ENABLED" = "1" ] \
    && ssh -o BatchMode=yes -o ConnectTimeout=3 "$JFC_VM_HOST" /usr/bin/true \
      >/dev/null 2>&1; then
    ssh "$JFC_VM_HOST" \
      'exec /bin/sh ~/jfc-e2e/repo/E2E/VM/start-appium.sh' \
      >/dev/null 2>&1 || true
    ssh "$JFC_VM_HOST" \
      'cd ~/jfc-e2e/repo && exec /opt/homebrew/bin/node E2E/InstallJFC/start-at-login.mjs disable' \
      >/dev/null 2>&1 || true
  fi
  exit "$JFC_STATUS"
}
trap jfc_cleanup EXIT HUP INT TERM

jfc_wait_for_ssh_down() {
  JFC_ATTEMPT=0
  while ssh -o BatchMode=yes -o ConnectTimeout=2 "$JFC_VM_HOST" /usr/bin/true \
    >/dev/null 2>&1
  do
    JFC_ATTEMPT=$((JFC_ATTEMPT + 1))
    if [ "$JFC_ATTEMPT" -ge 60 ]; then
      echo "VM did not go offline for reboot" >&2
      return 1
    fi
    /bin/sleep 1
  done
}

jfc_wait_for_ssh_up() {
  JFC_ATTEMPT=0
  until ssh -o BatchMode=yes -o ConnectTimeout=3 "$JFC_VM_HOST" /usr/bin/true \
    >/dev/null 2>&1
  do
    JFC_ATTEMPT=$((JFC_ATTEMPT + 1))
    if [ "$JFC_ATTEMPT" -ge 180 ]; then
      echo "VM did not return after reboot" >&2
      return 1
    fi
    /bin/sleep 1
  done
}

jfc_reboot() {
  ssh "$JFC_VM_HOST" \
    '/usr/bin/osascript -e '\''tell application "System Events" to restart'\''' \
    >/dev/null 2>&1 || true
  jfc_wait_for_ssh_down
  jfc_wait_for_ssh_up
  "$JFC_REPOSITORY_ROOT/scripts/wait-for-e2e-displays.mjs" "$JFC_VM_HOST" 180
  "$JFC_REPOSITORY_ROOT/scripts/stage-e2e-tools.sh" "$JFC_VM_HOST"
}

jfc_start_appium() {
  ssh "$JFC_VM_HOST" \
    'exec /bin/sh ~/jfc-e2e/repo/E2E/VM/start-appium.sh'
}

jfc_quit_before_reboot() {
  ssh "$JFC_VM_HOST" \
    '/usr/bin/osascript -e '\''tell application id "io.e10n.jfc" to quit'\'''
  JFC_ATTEMPT=0
  while ssh "$JFC_VM_HOST" '
    /usr/bin/pgrep -x JFC >/dev/null 2>&1 \
      || /usr/bin/pgrep -x JFCClickAgent >/dev/null 2>&1 \
      || /usr/bin/pgrep -x JFCLoginItem >/dev/null 2>&1
  '
  do
    JFC_ATTEMPT=$((JFC_ATTEMPT + 1))
    if [ "$JFC_ATTEMPT" -ge 40 ]; then
      echo "JFC processes did not stop before reboot" >&2
      return 1
    fi
    /bin/sleep 0.25
  done
}

jfc_guest_assertion() {
  JFC_ACTION="$1"
  JFC_OUTPUT="$2"
  ssh "$JFC_VM_HOST" \
    "cd ~/jfc-e2e/repo && exec /opt/homebrew/bin/node E2E/InstallJFC/start-at-login.mjs '$JFC_ACTION'" \
    > "$JFC_OUTPUT"
  /bin/cat "$JFC_OUTPUT"
}

jfc_guest_assertion enable "$JFC_ARTIFACT_DIR/enabled.json"
JFC_REGISTRATION_ENABLED=1
jfc_quit_before_reboot
jfc_reboot
jfc_start_appium
jfc_guest_assertion hidden-running "$JFC_ARTIFACT_DIR/enabled-after-reboot.json"

JFC_ENABLED_CLICK_ARTIFACTS="$JFC_ARTIFACT_DIR/enabled-click"
JFC_E2E_ARTIFACTS_DIR="$JFC_ENABLED_CLICK_ARTIFACTS" \
  "$JFC_REPOSITORY_ROOT/scripts/setup-e2e-scenario.sh" \
    "$JFC_REPOSITORY_ROOT/E2E/Scenarios/setup-smoke.json" "$JFC_VM_HOST"

jfc_guest_assertion disable "$JFC_ARTIFACT_DIR/disabled.json"
JFC_REGISTRATION_ENABLED=0
jfc_quit_before_reboot
jfc_reboot
jfc_guest_assertion stopped "$JFC_ARTIFACT_DIR/disabled-after-reboot.json"

JFC_DISABLED_CLICK_ARTIFACTS="$JFC_ARTIFACT_DIR/disabled-click"
if JFC_E2E_ARTIFACTS_DIR="$JFC_DISABLED_CLICK_ARTIFACTS" \
  "$JFC_REPOSITORY_ROOT/scripts/setup-e2e-scenario.sh" \
    "$JFC_REPOSITORY_ROOT/E2E/Scenarios/setup-smoke.json" "$JFC_VM_HOST"
then
  echo "Start-at-Login-disabled control unexpectedly passed" >&2
  exit 1
fi
/opt/homebrew/bin/node \
  "$JFC_REPOSITORY_ROOT/scripts/check-e2e-jfc-off-result.mjs" \
  "$JFC_DISABLED_CLICK_ARTIFACTS" \
  "$JFC_REPOSITORY_ROOT/E2E/Scenarios/setup-smoke.json"

if ssh "$JFC_VM_HOST" \
  '/usr/bin/pgrep -x JFC >/dev/null 2>&1 || /usr/bin/pgrep -x JFCClickAgent >/dev/null 2>&1'
then
  echo "JFC started during the disabled control" >&2
  exit 1
fi

echo "Start at Login enable/reboot/disable/reboot lifecycle passed."
echo "$JFC_ARTIFACT_DIR"
