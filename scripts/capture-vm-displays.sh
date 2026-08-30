#!/bin/sh

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_VM_HOST="${1:-mac-vm}"
JFC_TIMESTAMP=$(/bin/date -u '+%Y%m%dT%H%M%SZ')
JFC_OUTPUT_DIR="${2:-$JFC_REPOSITORY_ROOT/E2E/Artifacts/display-dump-$JFC_TIMESTAMP}"
JFC_METADATA_SOURCE="$JFC_REPOSITORY_ROOT/E2E/DisplayDump/main.swift"

/bin/mkdir -p "$JFC_OUTPUT_DIR"

ssh "$JFC_VM_HOST" 'xcrun swift -' \
  < "$JFC_METADATA_SOURCE" \
  > "$JFC_OUTPUT_DIR/displays.json"

JFC_SCREEN_CAPTURE_ALLOWED=$(
  /usr/bin/plutil -extract screenCaptureAllowed raw -o - \
    "$JFC_OUTPUT_DIR/displays.json"
)
if [ "$JFC_SCREEN_CAPTURE_ALLOWED" != "true" ]; then
  echo "screen capture is not authorized for the VM SSH process" >&2
  echo "enable Screen Recording for sshd-keygen-wrapper in the guest" >&2
  exit 1
fi

JFC_DISPLAY_COUNT=$(
  /usr/bin/plutil -extract displayCount raw -o - "$JFC_OUTPUT_DIR/displays.json"
)
case "$JFC_DISPLAY_COUNT" in
  ''|*[!0-9]*)
    echo "invalid display count: $JFC_DISPLAY_COUNT" >&2
    exit 1
    ;;
esac
if [ "$JFC_DISPLAY_COUNT" -lt 1 ]; then
  echo "the VM reported no displays" >&2
  exit 1
fi

JFC_REMOTE_DIR=$(ssh "$JFC_VM_HOST" \
  '/usr/bin/mktemp -d /tmp/jfc-display-dump.XXXXXX')
case "$JFC_REMOTE_DIR" in
  /tmp/jfc-display-dump.*) ;;
  *)
    echo "refusing unexpected remote temporary path: $JFC_REMOTE_DIR" >&2
    exit 1
    ;;
esac

jfc_cleanup() {
  ssh "$JFC_VM_HOST" \
    "/bin/rm -f '$JFC_REMOTE_DIR'/display-*.png; /bin/rmdir '$JFC_REMOTE_DIR'" \
    >/dev/null 2>&1 || true
}
trap jfc_cleanup EXIT HUP INT TERM

JFC_INDEX=1
while [ "$JFC_INDEX" -le "$JFC_DISPLAY_COUNT" ]; do
  JFC_NAME="display-$JFC_INDEX.png"
  JFC_REMOTE_FILE="$JFC_REMOTE_DIR/$JFC_NAME"

  echo "Capturing display $JFC_INDEX of $JFC_DISPLAY_COUNT..."
  ssh "$JFC_VM_HOST" \
    "/usr/sbin/screencapture -x -D '$JFC_INDEX' '$JFC_REMOTE_FILE'"
  scp "$JFC_VM_HOST:$JFC_REMOTE_FILE" "$JFC_OUTPUT_DIR/$JFC_NAME"
  ssh "$JFC_VM_HOST" "/bin/rm -f '$JFC_REMOTE_FILE'"

  JFC_INDEX=$((JFC_INDEX + 1))
done

ssh "$JFC_VM_HOST" "/bin/rmdir '$JFC_REMOTE_DIR'"
JFC_REMOTE_DIR=''
trap - EXIT HUP INT TERM

echo
echo "Captured $JFC_DISPLAY_COUNT displays:"
echo "$JFC_OUTPUT_DIR"
