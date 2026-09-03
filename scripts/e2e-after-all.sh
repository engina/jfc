#!/bin/sh

set -eu

JFC_REPOSITORY_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
JFC_VM_HOST="${1:-mac-vm}"
JFC_STATE_PATH="${2:-$JFC_REPOSITORY_ROOT/.build/e2e-vm/current.json}"
JFC_TIMESTAMP=$(/bin/date -u '+%Y%m%dT%H%M%SZ')
JFC_ARTIFACT_DIR="${3:-$JFC_REPOSITORY_ROOT/E2E/Artifacts/lifecycle-$JFC_TIMESTAMP}"

if [ ! -f "$JFC_STATE_PATH" ]; then
  echo "VM state not found: $JFC_STATE_PATH" >&2
  exit 1
fi

/bin/mkdir -p "$JFC_ARTIFACT_DIR/logs"
/bin/cp "$JFC_STATE_PATH" "$JFC_ARTIFACT_DIR/vm-state.json"
"$JFC_REPOSITORY_ROOT/scripts/capture-vm-displays.sh" \
  "$JFC_VM_HOST" "$JFC_ARTIFACT_DIR/final-displays"
JFC_PRODUCT_INSTALLED=false
if ssh "$JFC_VM_HOST" '/bin/test -d /Applications/JFC.app'; then
  JFC_PRODUCT_INSTALLED=true
  ssh "$JFC_VM_HOST" '
    /usr/bin/sw_vers
    /usr/bin/codesign -d --verbose=4 /Applications/JFC.app 2>&1
  ' > "$JFC_ARTIFACT_DIR/guest-installation.txt"
elif [ ! -s "$JFC_ARTIFACT_DIR/guest-installation.txt" ]; then
  echo "JFC was not installed before setup failed" \
    > "$JFC_ARTIFACT_DIR/guest-installation.txt"
fi

JFC_APPIUM_LOG=$(ssh "$JFC_VM_HOST" \
  '/bin/ls -1t "$HOME"/jfc-e2e/logs/appium-*.log 2>/dev/null | /usr/bin/head -n 1')
case "$JFC_APPIUM_LOG" in
  /Users/test-user/jfc-e2e/logs/appium-*.log)
    scp "$JFC_VM_HOST:$JFC_APPIUM_LOG" "$JFC_ARTIFACT_DIR/logs/"
    ;;
  '') ;;
  *)
    echo "refusing unexpected guest log path: $JFC_APPIUM_LOG" >&2
    exit 1
    ;;
esac

ssh "$JFC_VM_HOST" \
  '/usr/bin/log show --last 1h --style compact --predicate '\''subsystem == "io.e10n.jfc"'\''' \
  > "$JFC_ARTIFACT_DIR/logs/jfc-unified.log"

if [ "$JFC_PRODUCT_INSTALLED" = true ]; then
  ssh "$JFC_VM_HOST" \
    'cd ~/jfc-e2e/repo && exec /bin/sh E2E/InstallJFC/reset-product-state.sh --confirm' \
    > "$JFC_ARTIFACT_DIR/product-cleanup.txt"
else
  echo "JFC was never installed; no product cleanup was required" \
    > "$JFC_ARTIFACT_DIR/product-cleanup.txt"
fi

"$JFC_REPOSITORY_ROOT/scripts/destroy-e2e-vm.mjs" \
  "$JFC_STATE_PATH" "$JFC_VM_HOST" \
  > "$JFC_ARTIFACT_DIR/vm-destruction.json"

echo "afterAll captured artifacts, verified product cleanup, and deleted the disposable VM"
echo "$JFC_ARTIFACT_DIR"
