#!/bin/sh

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_VM_HOST="${1:-mac-vm}"
JFC_DURATION="${2:-5}"
JFC_TIMESTAMP=$(/bin/date -u '+%Y%m%dT%H%M%SZ')
JFC_ARTIFACT_DIR="$JFC_REPOSITORY_ROOT/E2E/Artifacts/recording-$JFC_TIMESTAMP"
JFC_GUEST_ROOT="jfc-e2e/repo"
JFC_GUEST_OUTPUT="jfc-e2e/recordings/$JFC_TIMESTAMP"

case "$JFC_DURATION" in
  ''|*[!0-9]*|0)
    echo "duration must be a positive integer" >&2
    exit 2
    ;;
esac

jfc_cleanup() {
  ssh "$JFC_VM_HOST" "/bin/rm -rf '$JFC_GUEST_OUTPUT'" >/dev/null 2>&1 || true
}
trap jfc_cleanup EXIT HUP INT TERM

/bin/mkdir -p "$JFC_ARTIFACT_DIR"
ssh "$JFC_VM_HOST" \
  "/bin/mkdir -p '$JFC_GUEST_ROOT/E2E/ScenarioExecutor' '$JFC_GUEST_OUTPUT'"
scp "$JFC_REPOSITORY_ROOT/E2E/ScenarioExecutor/recording.mjs" \
  "$JFC_REPOSITORY_ROOT/E2E/ScenarioExecutor/record-displays.mjs" \
  "$JFC_VM_HOST:$JFC_GUEST_ROOT/E2E/ScenarioExecutor/"

ssh "$JFC_VM_HOST" \
  "export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin; \
    /opt/homebrew/bin/node '$JFC_GUEST_ROOT/E2E/ScenarioExecutor/record-displays.mjs' \
      --output '$JFC_GUEST_OUTPUT' --duration '$JFC_DURATION'"

scp "$JFC_VM_HOST:$JFC_GUEST_OUTPUT/"'*' "$JFC_ARTIFACT_DIR/"

/opt/homebrew/bin/ffmpeg -hide_banner -loglevel warning -y \
  -i "$JFC_ARTIFACT_DIR/display-1.mp4" \
  -i "$JFC_ARTIFACT_DIR/display-2.mp4" \
  -i "$JFC_ARTIFACT_DIR/display-3.mp4" \
  -filter_complex \
  '[0:v]scale=-2:720,setsar=1[v0];[1:v]scale=-2:720,setsar=1[v1];[2:v]scale=-2:720,setsar=1[v2];[v0][v1][v2]hstack=inputs=3:shortest=1[v]' \
  -map '[v]' -an -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
  "$JFC_ARTIFACT_DIR/mosaic.mp4"

echo
echo "Captured and mosaiced all VM displays:"
echo "$JFC_ARTIFACT_DIR"
