#!/bin/bash
# Remove obsolete system hooks and unsafe sudoers entries from earlier installs.

zenbook-cleanup-obsolete-hooks() {
    local target_user="${1:-${USER}}"
    local backup

    systemctl --user disable --now zenbook-user.service >/dev/null 2>&1 || true
    sudo systemctl --global disable zenbook-user.service >/dev/null 2>&1 || true
    sudo systemctl disable --now zenbook.service >/dev/null 2>&1 || true
    sudo rm -f /etc/systemd/user/zenbook-user.service
    sudo rm -f /etc/systemd/system/zenbook.service
    sudo systemctl daemon-reload
    systemctl --user daemon-reload >/dev/null 2>&1 || true

    if sudo grep -Eq "^${target_user}[[:space:]]+ALL=NOPASSWD:.*(/tmp/zenbook/backlight\.py|/sys/class/backlight/card.*-eDP-2-backlight/brightness)" /etc/sudoers; then
        backup="/etc/sudoers.zenbook.$(date +%Y%m%d%H%M%S).bak"
        sudo cp -a /etc/sudoers "${backup}"
        sudo env ZENBOOK_USER="${target_user}" python3 - <<'PY_SUDOERS'
from pathlib import Path
import os
import re

path = Path("/etc/sudoers")
user = re.escape(os.environ["ZENBOOK_USER"])
text = path.read_text()
patterns = [
    re.compile(rf"^{user}\s+ALL=NOPASSWD:.*?/tmp/zenbook/backlight\.py\s+\*\s*$"),
    re.compile(rf"^{user}\s+ALL=NOPASSWD:/usr/bin/tee\s+/sys/class/backlight/card.*-eDP-2-backlight/brightness\s*$"),
]
lines = [line for line in text.splitlines() if not any(p.match(line) for p in patterns)]
path.write_text("\n".join(lines) + "\n")
PY_SUDOERS
        if ! sudo visudo -cf /etc/sudoers >/dev/null; then
            sudo cp -a "${backup}" /etc/sudoers
            printf 'ERROR: Could not safely clean obsolete sudoers rules; restored %s\n' "${backup}" >&2
            return 1
        fi
    fi
    sudo rm -f /etc/sudoers.d/zenbook /etc/sudoers.d/zenbook-* 2>/dev/null || true
}