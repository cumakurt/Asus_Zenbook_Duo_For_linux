#!/bin/bash
# ASUS Zenbook Duo UX8406CA helper entry point.
# Author: Cuma KURT — https://github.com/cumakurt/Asus_Zenbook_Duo_For_linux
# License: GPL-3.0-or-later
# Detects the active desktop/session and loads the matching display backend.

set -o pipefail

SCRIPT_PATH=$(readlink -f -- "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(cd -- "$(dirname -- "${SCRIPT_PATH}")" && pwd)
ZENBOOK_LIB_DIR="${SCRIPT_DIR}/lib"
ZENBOOK_PIDS=()

zenbook-cleanup() {
    local pid
    for pid in "${ZENBOOK_PIDS[@]:-}"; do
        kill "${pid}" 2>/dev/null || true
    done
    pkill -P $$ >/dev/null 2>&1 || true
}

trap 'echo "Exiting..."; zenbook-cleanup; exit 1' INT TERM
trap 'zenbook-cleanup' EXIT

# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/config.sh"
# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/detect/os.sh"
# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/detect/desktop.sh"

zenbook-detect-os >/dev/null 2>&1 || true
if ! zenbook-detect-desktop; then
    echo "$(date) - FATAL - Unsupported desktop/session for Zenbook Duo helper" >&2
    exit 1
fi

BACKEND_DIR="${ZENBOOK_LIB_DIR}/backend/${ZENBOOK_BACKEND}"
if [[ ! -d "${BACKEND_DIR}" ]]; then
    echo "$(date) - FATAL - Display backend not found: ${ZENBOOK_BACKEND}" >&2
    exit 1
fi

# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/status.sh"
# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/keyboard.sh"
# shellcheck source=/dev/null
. "${BACKEND_DIR}/windows.sh"
# shellcheck source=/dev/null
. "${BACKEND_DIR}/display.sh"
# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/profile.sh"
zenbook-load-profile
# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/touch.sh"
# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/brightness.sh"
# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/network.sh"
# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/monitor.sh"
# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/features.sh"
# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/rotate.sh"
# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/cli.sh"

if [[ -e "${RUNTIME_DIR}" && ! -d "${RUNTIME_DIR}" ]]; then
    echo "$(date) - FATAL - Runtime path exists and is not a directory: ${RUNTIME_DIR}" >&2
    exit 1
fi
mkdir -m 700 -p "${RUNTIME_DIR}"
chmod 700 "${RUNTIME_DIR}" 2>/dev/null || true

echo "$(date) - INIT - OS=${ZENBOOK_OS_ID} DE=${ZENBOOK_DE} session=${ZENBOOK_SESSION} compositor=${ZENBOOK_COMPOSITOR} backend=${ZENBOOK_BACKEND} profile=${ZENBOOK_PROFILE}"

function zenbook-init-session-state() {
    # Preserve remembered radio preferences across CLI invocations.
    if [[ -f "${STATUS_FILE}" ]]; then
        zenbook-load-status
    else
        WIFI_BEFORE=$(nmcli radio wifi 2>/dev/null || echo unknown)
        BLUETOOTH_BEFORE=$(rfkill -n -o SOFT list bluetooth 2>/dev/null | head -n1 || echo unknown)
    fi

    KEYBOARD_ATTACHED=false
    if zenbook-keyboard-attached; then
        KEYBOARD_ATTACHED=true
    fi
    MONITOR_COUNT=$(zenbook-monitor-count)
    zenbook-set-status
}

function main() {
    local tool
    tool=$(zenbook-backend-tool)
    if ! zenbook-backend-ready; then
        echo "$(date) - FATAL - Required display tool '${tool}' is missing for backend=${ZENBOOK_BACKEND}" >&2
        exit 1
    fi
    if [[ "${ZENBOOK_BACKEND}" == x11 ]] && ! command -v wmctrl >/dev/null 2>&1; then
        echo "$(date) - WINDOW - wmctrl not found; install it for deterministic bottom->top window relocation"
    fi
    if [[ "${ZENBOOK_BACKEND}" == x11 ]] && ! command -v xinput >/dev/null 2>&1; then
        echo "$(date) - TOUCH - xinput not found; install it for dual-panel touch mapping"
    fi

    # Fresh radio snapshot only when starting the long-running daemon.
    WIFI_BEFORE=$(nmcli radio wifi 2>/dev/null || echo unknown)
    BLUETOOTH_BEFORE=$(rfkill -n -o SOFT list bluetooth 2>/dev/null | head -n1 || echo unknown)
    KEYBOARD_ATTACHED=false
    if zenbook-keyboard-attached; then
        KEYBOARD_ATTACHED=true
    fi
    MONITOR_COUNT=$(zenbook-monitor-count)
    zenbook-set-status

    zenbook-set-kb-backlight "${DEFAULT_BACKLIGHT}" || true
    # Force apply on startup so a docked keyboard disables eDP-2 immediately.
    zenbook-check-monitor 1
    zenbook-map-touch-inputs || true

    zenbook-watch-monitor &
    ZENBOOK_PIDS+=("$!")
    zenbook-watch-rotate &
    ZENBOOK_PIDS+=("$!")
    zenbook-watch-display-backlight &
    ZENBOOK_PIDS+=("$!")
    zenbook-watch-wifi &
    ZENBOOK_PIDS+=("$!")
    zenbook-watch-bluetooth &
    ZENBOOK_PIDS+=("$!")

    wait
}

if [ -z "${1:-}" ]; then
    main > >(tee -a "${LOG_FILE}") 2>&1
else
    zenbook-init-session-state
    zenbook-cli "$@" > >(tee -a "${LOG_FILE}") 2>&1
fi
