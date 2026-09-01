#!/bin/sh

set -eu

if [ "$(/usr/bin/id -u)" -ne 0 ]; then
  echo "run this uninstaller with sudo" >&2
  exit 1
fi

/bin/rm -f /etc/sudoers.d/jfc-e2e-install-app
/bin/rm -f /usr/local/libexec/jfc-e2e-install-app
/usr/sbin/visudo -cf /etc/sudoers

echo "removed JFC E2E app-install privileges and helper"
