#!/bin/sh

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_VM_HOST="${1:-mac-vm}"
JFC_TIMESTAMP=$(/bin/date -u '+%Y%m%dT%H%M%SZ')
JFC_ARTIFACT_DIR="${JFC_E2E_ARTIFACTS_DIR:-$JFC_REPOSITORY_ROOT/E2E/Artifacts/matrix-$JFC_TIMESTAMP}"
JFC_STATE_PATH="$JFC_REPOSITORY_ROOT/.build/e2e-vm/current.json"
JFC_AFTER_ALL_REQUIRED=false

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

JFC_E2E_ARTIFACTS_DIR="$JFC_ARTIFACT_DIR" \
  "$JFC_REPOSITORY_ROOT/scripts/run-e2e-matrix.sh" "$JFC_VM_HOST"

for JFC_LIFECYCLE_ACTION in stop start recover; do
  ssh "$JFC_VM_HOST" \
    "cd ~/jfc-e2e/repo && exec /opt/homebrew/bin/node E2E/InstallJFC/agent-lifecycle.mjs '$JFC_LIFECYCLE_ACTION'"
done

JFC_E2E_CONTROL_ARTIFACTS_DIR="$JFC_ARTIFACT_DIR/jfc-off" \
  "$JFC_REPOSITORY_ROOT/scripts/verify-e2e-jfc-off.sh" "$JFC_VM_HOST"

ssh "$JFC_VM_HOST" \
  'cd ~/jfc-e2e/repo && exec /opt/homebrew/bin/node E2E/InstallJFC/agent-lifecycle.mjs status'
