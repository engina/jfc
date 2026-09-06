#!/bin/sh
# shellcheck disable=SC2016,SC2029

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_SCENARIO="${1:-$JFC_REPOSITORY_ROOT/E2E/Scenarios/setup-smoke.json}"
JFC_VM_HOST="${2:-mac-vm}"
JFC_TIMESTAMP=$(/bin/date -u '+%Y%m%dT%H%M%SZ')
JFC_ARTIFACT_ROOT="${JFC_E2E_ARTIFACTS_DIR:-$JFC_REPOSITORY_ROOT/E2E/Artifacts}"
JFC_ARTIFACT_DIR="$JFC_ARTIFACT_ROOT/scenario-$JFC_TIMESTAMP"
JFC_GUEST_ROOT="jfc-e2e/repo"
JFC_SCENARIO_NAME=$(/usr/bin/basename "$JFC_SCENARIO")
JFC_GUEST_RECORDINGS="jfc-e2e/recordings/scenario-$JFC_TIMESTAMP"
JFC_STARTED_APPIUM_PID=''
JFC_SCENARIO_STATUS='passed'
JFC_STARTED_AT_MS=$(/opt/homebrew/bin/node -e 'process.stdout.write(String(Date.now()))')
JFC_DIAGNOSTICS_INTERVAL_SECONDS="${JFC_E2E_DIAGNOSTICS_INTERVAL_SECONDS:-2}"
JFC_RECORDING_FPS="${JFC_E2E_RECORDING_FPS:-10}"
JFC_HOST_CONDITIONS_PID=''
JFC_GUEST_CONDITIONS_PID=''
JFC_GUEST_ARTIFACTS_COLLECTED=false

if [ ! -f "$JFC_SCENARIO" ]; then
  echo "scenario not found: $JFC_SCENARIO" >&2
  exit 2
fi

jfc_stop_condition_capture() {
  JFC_CAPTURE_STATUS=0
  if [ -n "$JFC_HOST_CONDITIONS_PID" ]; then
    if /bin/kill -0 "$JFC_HOST_CONDITIONS_PID" 2>/dev/null; then
      /bin/kill -TERM "$JFC_HOST_CONDITIONS_PID" 2>/dev/null || true
    fi
    if ! wait "$JFC_HOST_CONDITIONS_PID"; then
      echo "host condition capture did not exit cleanly" >&2
      JFC_CAPTURE_STATUS=1
    fi
    JFC_HOST_CONDITIONS_PID=''
  fi

  if [ -n "$JFC_GUEST_CONDITIONS_PID" ]; then
    if ! ssh "$JFC_VM_HOST" "
      if /bin/kill -0 '$JFC_GUEST_CONDITIONS_PID' 2>/dev/null; then
        /bin/kill -TERM '$JFC_GUEST_CONDITIONS_PID' 2>/dev/null || true
        JFC_ATTEMPT=0
        while /bin/kill -0 '$JFC_GUEST_CONDITIONS_PID' 2>/dev/null; do
          JFC_ATTEMPT=\$((JFC_ATTEMPT + 1))
          if [ \"\$JFC_ATTEMPT\" -ge 50 ]; then break; fi
          /bin/sleep 0.1
        done
      fi
      if /bin/kill -0 '$JFC_GUEST_CONDITIONS_PID' 2>/dev/null; then
        /bin/kill -KILL '$JFC_GUEST_CONDITIONS_PID'
        exit 1
      fi
    "; then
      echo "guest condition capture did not exit cleanly" >&2
      JFC_CAPTURE_STATUS=1
    fi
    JFC_GUEST_CONDITIONS_PID=''
  fi
  return "$JFC_CAPTURE_STATUS"
}

jfc_collect_guest_artifacts() {
  if [ "$JFC_GUEST_ARTIFACTS_COLLECTED" = true ]; then return 0; fi
  scp "$JFC_VM_HOST:$JFC_GUEST_RECORDINGS/"'*' "$JFC_ARTIFACT_DIR/"
  JFC_GUEST_ARTIFACTS_COLLECTED=true
}

jfc_cleanup() {
  jfc_stop_condition_capture || true
  jfc_collect_guest_artifacts >/dev/null 2>&1 || true
  ssh "$JFC_VM_HOST" \
    '/usr/bin/sudo -n /bin/launchctl kill SIGTERM system/io.e10n.jfc.e2e.virtual-hid' \
    >/dev/null 2>&1 || true
  if [ -n "$JFC_STARTED_APPIUM_PID" ]; then
    ssh "$JFC_VM_HOST" "/bin/kill '$JFC_STARTED_APPIUM_PID'" >/dev/null 2>&1 || true
  fi
  ssh "$JFC_VM_HOST" "/bin/rm -rf '$JFC_GUEST_RECORDINGS'" >/dev/null 2>&1 || true
}
trap jfc_cleanup EXIT HUP INT TERM

/bin/mkdir -p "$JFC_ARTIFACT_DIR"
/opt/homebrew/bin/node -e '
  const value = Number(process.argv[1]);
  if (!Number.isFinite(value) || value < 0.5 || value > 3600) process.exit(1);
' "$JFC_DIAGNOSTICS_INTERVAL_SECONDS" || {
  echo "JFC_E2E_DIAGNOSTICS_INTERVAL_SECONDS must be between 0.5 and 3600" >&2
  exit 2
}
/opt/homebrew/bin/node -e '
  const value = Number(process.argv[1]);
  if (!Number.isInteger(value) || value < 1 || value > 240) process.exit(1);
' "$JFC_RECORDING_FPS" || {
  echo "JFC_E2E_RECORDING_FPS must be an integer from 1 through 240" >&2
  exit 2
}
ssh "$JFC_VM_HOST" \
  "/bin/mkdir -p '$JFC_GUEST_ROOT/E2E/ScenarioExecutor' '$JFC_GUEST_ROOT/E2E/Scenarios' '$JFC_GUEST_ROOT/E2E/Fixture' '$JFC_GUEST_ROOT/E2E/Diagnostics' '$JFC_GUEST_RECORDINGS'"
scp "$JFC_REPOSITORY_ROOT"/E2E/ScenarioExecutor/* \
  "$JFC_VM_HOST:$JFC_GUEST_ROOT/E2E/ScenarioExecutor/"
scp "$JFC_REPOSITORY_ROOT/E2E/Diagnostics/conditions.mjs" \
  "$JFC_VM_HOST:$JFC_GUEST_ROOT/E2E/Diagnostics/conditions.mjs"
scp "$JFC_REPOSITORY_ROOT/E2E/Fixture/index.html" \
  "$JFC_VM_HOST:$JFC_GUEST_ROOT/E2E/Fixture/index.html"
scp "$JFC_SCENARIO" \
  "$JFC_VM_HOST:$JFC_GUEST_ROOT/E2E/Scenarios/$JFC_SCENARIO_NAME"

/opt/homebrew/bin/node "$JFC_REPOSITORY_ROOT/E2E/Diagnostics/conditions.mjs" \
  --role host \
  --output "$JFC_ARTIFACT_DIR/host-conditions.jsonl" \
  --interval "$JFC_DIAGNOSTICS_INTERVAL_SECONDS" \
  > "$JFC_ARTIFACT_DIR/host-conditions.stderr.log" 2>&1 &
JFC_HOST_CONDITIONS_PID=$!
/bin/sleep 0.1
if ! /bin/kill -0 "$JFC_HOST_CONDITIONS_PID" 2>/dev/null; then
  wait "$JFC_HOST_CONDITIONS_PID" || true
  echo "host condition capture failed to start" >&2
  exit 1
fi

JFC_GUEST_CONDITIONS_PID=$(ssh "$JFC_VM_HOST" "
  /usr/bin/nohup /opt/homebrew/bin/node \
    '$JFC_GUEST_ROOT/E2E/Diagnostics/conditions.mjs' \
    --role guest \
    --output '$JFC_GUEST_RECORDINGS/guest-conditions.jsonl' \
    --interval '$JFC_DIAGNOSTICS_INTERVAL_SECONDS' \
    > '$JFC_GUEST_RECORDINGS/guest-conditions.stderr.log' 2>&1 < /dev/null &
  echo \$!
")
case "$JFC_GUEST_CONDITIONS_PID" in
  ''|*[!0-9]*)
    echo "guest condition capture returned an invalid PID" >&2
    exit 1
    ;;
esac
/bin/sleep 0.1
if ! ssh "$JFC_VM_HOST" "/bin/kill -0 '$JFC_GUEST_CONDITIONS_PID'"; then
  echo "guest condition capture failed to start" >&2
  exit 1
fi

/opt/homebrew/bin/node \
  "$JFC_REPOSITORY_ROOT/E2E/Diagnostics/clock-alignment.mjs" \
  "$JFC_VM_HOST" "$JFC_ARTIFACT_DIR/clock-alignment.json"

if ! ssh "$JFC_VM_HOST" \
  '/usr/bin/curl -fsS http://127.0.0.1:4723/status >/dev/null 2>&1'; then
  JFC_STARTED_APPIUM_PID=$(ssh "$JFC_VM_HOST" '
    export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
    /bin/mkdir -p "$HOME/jfc-e2e"
    /usr/bin/nohup appium --address 127.0.0.1 --port 4723 \
      --allow-insecure=mac2:apple_script \
      > "$HOME/jfc-e2e/appium.log" 2>&1 < /dev/null &
    echo $!
  ')
  case "$JFC_STARTED_APPIUM_PID" in
    ''|*[!0-9]*)
      echo "could not start Appium" >&2
      exit 1
      ;;
  esac
  JFC_ATTEMPT=0
  while ! ssh "$JFC_VM_HOST" \
    '/usr/bin/curl -fsS http://127.0.0.1:4723/status >/dev/null 2>&1'; do
    JFC_ATTEMPT=$((JFC_ATTEMPT + 1))
    if [ "$JFC_ATTEMPT" -ge 40 ]; then
      echo "Appium did not become ready" >&2
      exit 1
    fi
    /bin/sleep 0.25
  done
fi

if ! ssh "$JFC_VM_HOST" \
  "/opt/homebrew/bin/node '$JFC_GUEST_ROOT/E2E/ScenarioExecutor/executor.mjs' \
    '$JFC_GUEST_ROOT/E2E/Scenarios/$JFC_SCENARIO_NAME' \
    --fixture '$JFC_GUEST_ROOT/E2E/Fixture/index.html' \
    --recordings '$JFC_GUEST_RECORDINGS' \
    --recording-fps '$JFC_RECORDING_FPS' \
    --timings '$JFC_GUEST_RECORDINGS/action-timings.jsonl'" \
  > "$JFC_ARTIFACT_DIR/result.json"; then
  if [ -s "$JFC_ARTIFACT_DIR/result.json" ] && /opt/homebrew/bin/node -e '
    const result = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
    if (result.status !== "failed") process.exit(1);
  ' "$JFC_ARTIFACT_DIR/result.json"; then
    JFC_SCENARIO_STATUS='failed'
  else
    echo "scenario executor failed before producing a test result" >&2
    exit 1
  fi
fi

jfc_stop_condition_capture
jfc_collect_guest_artifacts
/opt/homebrew/bin/node "$JFC_REPOSITORY_ROOT/E2E/Diagnostics/validate.mjs" \
  "$JFC_ARTIFACT_DIR" "$JFC_SCENARIO"

/opt/homebrew/bin/ffmpeg -hide_banner -loglevel warning -y \
  -i "$JFC_ARTIFACT_DIR/display-1.mp4" \
  -i "$JFC_ARTIFACT_DIR/display-2.mp4" \
  -i "$JFC_ARTIFACT_DIR/display-3.mp4" \
  -filter_complex \
  '[0:v]scale=-2:720,setsar=1[v0];[1:v]scale=-2:720,setsar=1[v1];[2:v]scale=-2:720,setsar=1[v2];[v0][v1][v2]hstack=inputs=3:shortest=1[v]' \
  -map '[v]' -an -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  "$JFC_ARTIFACT_DIR/mosaic.mp4"

"$JFC_REPOSITORY_ROOT/scripts/capture-vm-displays.sh" \
  "$JFC_VM_HOST" "$JFC_ARTIFACT_DIR/displays"

JFC_FINISHED_AT_MS=$(/opt/homebrew/bin/node -e 'process.stdout.write(String(Date.now()))')
JFC_DURATION_MS=$((JFC_FINISHED_AT_MS - JFC_STARTED_AT_MS))
/opt/homebrew/bin/node -e '
  const fs = require("node:fs");
  const filename = process.argv[1];
  const result = JSON.parse(fs.readFileSync(filename, "utf8"));
  result.durationMs = Number(process.argv[2]);
  fs.writeFileSync(filename, `${JSON.stringify(result, null, 2)}\n`);
' "$JFC_ARTIFACT_DIR/result.json" "$JFC_DURATION_MS"

/opt/homebrew/bin/node "$JFC_REPOSITORY_ROOT/scripts/generate-e2e-report.mjs" \
  "$JFC_ARTIFACT_ROOT" \
  "$JFC_ARTIFACT_ROOT/report.html"

echo
echo "Scenario $JFC_SCENARIO_STATUS with multi-display recording:"
echo "$JFC_ARTIFACT_DIR"
echo "Report:"
echo "$JFC_ARTIFACT_ROOT/report.html"

if [ "$JFC_SCENARIO_STATUS" = 'failed' ]; then
  exit 1
fi
