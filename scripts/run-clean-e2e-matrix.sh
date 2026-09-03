#!/bin/sh
# shellcheck disable=SC2029

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_VM_HOST='mac-vm'
JFC_VM_HOST_SET=false
JFC_SCENARIO_FILTER=''
JFC_TIMESTAMP=$(/bin/date -u '+%Y%m%dT%H%M%SZ')
JFC_ARTIFACT_DIR="${JFC_E2E_ARTIFACTS_DIR:-$JFC_REPOSITORY_ROOT/E2E/Artifacts/matrix-$JFC_TIMESTAMP}"
JFC_STATE_PATH="$JFC_REPOSITORY_ROOT/.build/e2e-vm/current.json"
JFC_AFTER_ALL_REQUIRED=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --filter)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        echo "--filter requires a non-empty substring" >&2
        exit 2
      fi
      JFC_SCENARIO_FILTER=$2
      shift 2
      ;;
    -*)
      echo "unknown option: $1" >&2
      exit 2
      ;;
    *)
      if [ "$JFC_VM_HOST_SET" = true ]; then
        echo "unexpected argument: $1" >&2
        exit 2
      fi
      JFC_VM_HOST=$1
      JFC_VM_HOST_SET=true
      shift
      ;;
  esac
done

jfc_after_all() {
  JFC_STATUS=$?
  trap - EXIT HUP INT TERM
  if [ "$JFC_AFTER_ALL_REQUIRED" = true ] && [ -f "$JFC_STATE_PATH" ]; then
    if ! "$JFC_REPOSITORY_ROOT/scripts/e2e-after-all.sh" \
      "$JFC_VM_HOST" "$JFC_STATE_PATH" "$JFC_ARTIFACT_DIR"
    then
      echo "afterAll failed; disposable VM state retained: $JFC_STATE_PATH" >&2
      if [ "$JFC_STATUS" -eq 0 ]; then JFC_STATUS=1; fi
    fi
  fi
  exit "$JFC_STATUS"
}
trap jfc_after_all EXIT HUP INT TERM

JFC_AFTER_ALL_REQUIRED=true
if ! "$JFC_REPOSITORY_ROOT/scripts/e2e-before-all.sh" \
  "$JFC_VM_HOST" "$JFC_STATE_PATH"
then
  exit 1
fi

if [ -n "$JFC_SCENARIO_FILTER" ]; then
  JFC_E2E_ARTIFACTS_DIR="$JFC_ARTIFACT_DIR" \
    "$JFC_REPOSITORY_ROOT/scripts/run-e2e-matrix.sh" \
      "$JFC_VM_HOST" --filter "$JFC_SCENARIO_FILTER"
  exit 0
fi

JFC_E2E_ARTIFACTS_DIR="$JFC_ARTIFACT_DIR" \
  "$JFC_REPOSITORY_ROOT/scripts/run-e2e-matrix.sh" "$JFC_VM_HOST"

for JFC_LIFECYCLE_ACTION in stop start recover; do
  ssh "$JFC_VM_HOST" \
    "cd ~/jfc-e2e/repo && exec /opt/homebrew/bin/node E2E/InstallJFC/agent-lifecycle.mjs '$JFC_LIFECYCLE_ACTION'"
done

"$JFC_REPOSITORY_ROOT/scripts/verify-e2e-start-at-login.sh" \
  "$JFC_VM_HOST" "$JFC_STATE_PATH" "$JFC_ARTIFACT_DIR/start-at-login"

JFC_E2E_CONTROL_ARTIFACTS_DIR="$JFC_ARTIFACT_DIR/jfc-off" \
  "$JFC_REPOSITORY_ROOT/scripts/verify-e2e-jfc-off.sh" "$JFC_VM_HOST"

ssh "$JFC_VM_HOST" \
  'exec /bin/sh ~/jfc-e2e/repo/E2E/VM/start-appium.sh'
ssh "$JFC_VM_HOST" \
  'cd ~/jfc-e2e/repo && exec /opt/homebrew/bin/node E2E/InstallJFC/agent-lifecycle.mjs status'
