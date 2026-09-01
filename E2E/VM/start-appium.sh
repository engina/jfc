#!/bin/sh

set -eu

JFC_APPIUM_URL="http://127.0.0.1:4723/status"
JFC_RUN_DIR="$HOME/jfc-e2e/run"
JFC_LOG_DIR="$HOME/jfc-e2e/logs"
JFC_TIMESTAMP=$(/bin/date -u '+%Y%m%dT%H%M%SZ')
JFC_LOG="$JFC_LOG_DIR/appium-$JFC_TIMESTAMP.log"
JFC_PID_FILE="$JFC_RUN_DIR/appium.pid"
PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

if /usr/bin/curl --silent --fail --max-time 2 "$JFC_APPIUM_URL" >/dev/null 2>&1; then
  echo "Appium is already ready"
  exit 0
fi

/usr/bin/pkill -f \
  '/WebDriverAgentRunner-Runner.app/Contents/MacOS/WebDriverAgentRunner-Runner' \
  >/dev/null 2>&1 || true
/usr/bin/pkill -f '/WebDriverAgentMac.xcodeproj' >/dev/null 2>&1 || true
/bin/mkdir -p "$JFC_RUN_DIR" "$JFC_LOG_DIR"

/usr/bin/nohup /opt/homebrew/bin/appium --log-level info \
  --allow-insecure=mac2:apple_script \
  >"$JFC_LOG" 2>&1 </dev/null &
JFC_PID=$!
printf '%s\n' "$JFC_PID" >"$JFC_PID_FILE"

JFC_ATTEMPT=0
while ! /usr/bin/curl --silent --fail --max-time 2 "$JFC_APPIUM_URL" \
  >/dev/null 2>&1
do
  JFC_ATTEMPT=$((JFC_ATTEMPT + 1))
  if [ "$JFC_ATTEMPT" -ge 60 ]; then
    echo "Appium did not become ready; log: $JFC_LOG" >&2
    /usr/bin/tail -n 40 "$JFC_LOG" >&2 || true
    exit 1
  fi
  /bin/sleep 1
done

echo "Appium ready pid=$JFC_PID log=$JFC_LOG"
