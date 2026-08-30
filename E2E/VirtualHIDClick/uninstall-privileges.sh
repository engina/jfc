#!/bin/sh

set -eu

if [ "$(/usr/bin/id -u)" -ne 0 ]; then
  echo "run this uninstaller with sudo" >&2
  exit 1
fi

JFC_JOB_LABEL="io.e10n.jfc.e2e.virtual-hid"
if /bin/launchctl print "system/$JFC_JOB_LABEL" >/dev/null 2>&1; then
  /bin/launchctl bootout "system/$JFC_JOB_LABEL"
fi

/bin/rm -f /etc/sudoers.d/jfc-e2e-virtual-hid
/bin/rm -f /usr/local/libexec/jfc-e2e-virtual-hid-click
/bin/rm -f /usr/local/libexec/jfc-e2e-virtual-hid-daemon
/bin/rm -f "/Library/LaunchDaemons/$JFC_JOB_LABEL.plist"
/usr/sbin/visudo -cf /etc/sudoers

echo "removed JFC E2E VirtualHID privileges and installed click client"
