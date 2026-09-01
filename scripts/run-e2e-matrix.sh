#!/bin/sh

set -u

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_VM_HOST="${1:-mac-vm}"
JFC_FAILURES=''
JFC_COUNT=0

for JFC_SCENARIO_NAME in \
  setup-smoke.json \
  vscode-d2-c1-d2-c2-d2.json \
  vscode-d2-c1-d1-c2-d3.json \
  vscode-d2-c1-d1-c2-d1.json \
  vscode-d2-c1-d2-c2-d1.json \
  vscode-d2-c1-d3-c2-d1.json \
  c1-active-d2-c2-d3.json \
  jfc-window-open.json \
  repeat-c2-three-clicks.json \
  alternate-brave-windows.json \
  repeat-vscode-c2-transitions.json \
  repeat-vscode-d1-d3-transitions.json
do
  JFC_COUNT=$((JFC_COUNT + 1))
  echo "[$JFC_COUNT/12] $JFC_SCENARIO_NAME"
  if ! "$JFC_REPOSITORY_ROOT/scripts/setup-e2e-scenario.sh" \
    "$JFC_REPOSITORY_ROOT/E2E/Scenarios/$JFC_SCENARIO_NAME" \
    "$JFC_VM_HOST"
  then
    JFC_FAILURES="$JFC_FAILURES $JFC_SCENARIO_NAME"
  fi
done

if [ -n "$JFC_FAILURES" ]; then
  echo "E2E matrix failures:$JFC_FAILURES" >&2
  exit 1
fi

echo "All $JFC_COUNT E2E scenarios passed."
