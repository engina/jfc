#!/bin/sh

set -eu

if [ "${1:-}" != "--confirm" ]; then
  echo "usage: reset-product-state.sh --confirm" >&2
  echo "removes JFC product state from the isolated E2E VM" >&2
  exit 2
fi

JFC_BUNDLE_ID="io.e10n.jfc"
JFC_CLICK_AGENT_BUNDLE_ID="io.e10n.jfc.click-agent"
JFC_HOME="$HOME"

if /usr/bin/sfltool dumpbtm 2>/dev/null | /usr/bin/grep -qi "$JFC_BUNDLE_ID"; then
  echo "JFC remains registered as a background item; disable Start at Login first" >&2
  exit 1
fi

if /usr/bin/pgrep -x JFC >/dev/null 2>&1; then
  /usr/bin/osascript -e 'tell application id "io.e10n.jfc" to quit'
fi
JFC_ATTEMPT=0
while /usr/bin/pgrep -x JFC >/dev/null 2>&1 \
  || /usr/bin/pgrep -x JFCClickAgent >/dev/null 2>&1
do
  JFC_ATTEMPT=$((JFC_ATTEMPT + 1))
  if [ "$JFC_ATTEMPT" -ge 40 ]; then
    echo "JFC UI or click agent did not quit" >&2
    exit 1
  fi
  /bin/sleep 0.25
done

/usr/bin/tccutil reset Accessibility "$JFC_BUNDLE_ID"
/usr/bin/tccutil reset Accessibility "$JFC_CLICK_AGENT_BUNDLE_ID" 2>/dev/null || true
/usr/bin/sudo -n /usr/local/libexec/jfc-e2e-install-app uninstall
/usr/bin/defaults delete "$JFC_BUNDLE_ID" >/dev/null 2>&1 || true

/bin/rm -rf -- \
  "$JFC_HOME/Library/Application Support/$JFC_BUNDLE_ID" \
  "$JFC_HOME/Library/Caches/$JFC_BUNDLE_ID" \
  "$JFC_HOME/Library/HTTPStorages/$JFC_BUNDLE_ID" \
  "$JFC_HOME/Library/Preferences/$JFC_BUNDLE_ID.plist" \
  "$JFC_HOME/Library/Saved Application State/$JFC_BUNDLE_ID.savedState" \
  "$JFC_HOME/Library/WebKit/$JFC_BUNDLE_ID" \
  "$JFC_HOME/jfc-e2e/install" \
  "$JFC_HOME/jfc-e2e/JFC-simplified-signed.zip" \
  "$JFC_HOME/jfc-e2e/JFC-regular-baseline.app" \
  "$JFC_HOME/jfc-e2e/JFC-accessory.zip" \
  "$JFC_HOME/jfc-e2e/JFC-0.1.1-activation-strategies.dmg" \
  "$JFC_HOME/jfc-e2e/deploy-accessory" \
  "$JFC_HOME/jfc-e2e/apps/JFC Input Diagnostic.app" \
  "$JFC_HOME/jfc-e2e/backups/JFC-before-activation-strategies.app" \
  "$JFC_HOME/jfc-e2e/backups/JFC-activation-strategies.app" \
  "$JFC_HOME/jfc-e2e/bin/jfc-cli" \
  "$JFC_HOME/jfc-e2e/bin/jfc-input-diagnostic"

/usr/bin/find "$JFC_HOME/Downloads" -maxdepth 1 -type f \
  \( -name 'JFC-*.dmg' -o -name 'JFC-*.zip' \) -delete 2>/dev/null || true
if /usr/bin/pgrep -x JFC >/dev/null 2>&1; then
  echo "JFC process remains after reset" >&2
  exit 1
fi
if /usr/bin/pgrep -x JFCClickAgent >/dev/null 2>&1; then
  echo "JFC click-agent process remains after reset" >&2
  exit 1
fi
if [ -e /Applications/JFC.app ]; then
  echo "JFC.app remains after reset" >&2
  exit 1
fi
if /usr/bin/defaults read "$JFC_BUNDLE_ID" >/dev/null 2>&1; then
  echo "JFC preferences remain after reset" >&2
  exit 1
fi
if /usr/bin/sfltool dumpbtm 2>/dev/null | /usr/bin/grep -qi "$JFC_BUNDLE_ID"; then
  echo "JFC background-item registration remains after reset" >&2
  exit 1
fi

echo "JFC UI, click agent, bundle, preferences, staged product, and Accessibility decisions removed"
