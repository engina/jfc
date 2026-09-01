#!/bin/sh

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_VM_HOST="${1:-mac-vm}"
JFC_CONTROL_ARTIFACTS="${JFC_E2E_CONTROL_ARTIFACTS_DIR:-$JFC_REPOSITORY_ROOT/E2E/Artifacts/jfc-off}"
JFC_WAS_RUNNING='false'

jfc_is_running() {
  ssh "$JFC_VM_HOST" '/usr/bin/pgrep -x JFC >/dev/null 2>&1'
}

jfc_is_agent_running() {
  ssh "$JFC_VM_HOST" '/usr/bin/pgrep -x JFCClickAgent >/dev/null 2>&1'
}

jfc_start() {
  ssh "$JFC_VM_HOST" \
    "/usr/bin/open -gja '/Applications/JFC.app' --args --launch-at-login"
  JFC_ATTEMPT=0
  while ! jfc_is_running; do
    JFC_ATTEMPT=$((JFC_ATTEMPT + 1))
    if [ "$JFC_ATTEMPT" -ge 40 ]; then
      echo "JFC did not restart" >&2
      return 1
    fi
    /bin/sleep 0.25
  done
}

jfc_restore() {
  if [ "$JFC_WAS_RUNNING" = 'true' ] && ! jfc_is_running; then
    jfc_start
  fi
}
trap jfc_restore EXIT HUP INT TERM

if jfc_is_running; then
  JFC_WAS_RUNNING='true'
fi
ssh "$JFC_VM_HOST" '/usr/bin/pkill -x JFC >/dev/null 2>&1 || true'
JFC_ATTEMPT=0
while jfc_is_running || jfc_is_agent_running; do
  JFC_ATTEMPT=$((JFC_ATTEMPT + 1))
  if [ "$JFC_ATTEMPT" -ge 40 ]; then
    echo "JFC UI or click agent did not stop" >&2
    exit 1
  fi
  /bin/sleep 0.25
done

for JFC_SCENARIO_NAME in \
  setup-smoke.json \
  vscode-d2-c1-d2-c2-d2.json \
  vscode-d2-c1-d1-c2-d3.json \
  vscode-d2-c1-d1-c2-d1.json \
  vscode-d2-c1-d2-c2-d1.json \
  vscode-d2-c1-d3-c2-d1.json \
  c1-active-d2-c2-d3.json
do
  JFC_SCENARIO="$JFC_REPOSITORY_ROOT/E2E/Scenarios/$JFC_SCENARIO_NAME"
  if JFC_E2E_ARTIFACTS_DIR="$JFC_CONTROL_ARTIFACTS" \
    "$JFC_REPOSITORY_ROOT/scripts/setup-e2e-scenario.sh" \
      "$JFC_SCENARIO" "$JFC_VM_HOST"
  then
    echo "$JFC_SCENARIO_NAME unexpectedly passed with JFC stopped" >&2
    exit 1
  fi
  if jfc_is_running; then
    echo "JFC started unexpectedly during $JFC_SCENARIO_NAME" >&2
    exit 1
  fi
  /opt/homebrew/bin/node \
    "$JFC_REPOSITORY_ROOT/scripts/check-e2e-jfc-off-result.mjs" \
    "$JFC_CONTROL_ARTIFACTS" "$JFC_SCENARIO"
done

echo
echo "All seven JFC-off controls failed for the expected missing-click reason."
echo "Control report:"
echo "$JFC_CONTROL_ARTIFACTS/report.html"
