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
declare -A ZENBOOK_WATCHER_FUNCS=()
ZENBOOK_STOP=0

zenbook-cleanup() {
    local pid
    ZENBOOK_STOP=1
    zenbook-cancel-detach-backlight 2>/dev/null || true
    for pid in "${ZENBOOK_PIDS[@]:-}"; do
        if [[ -n "${pid}" ]]; then
            pkill -P "${pid}" >/dev/null 2>&1 || true
            kill "${pid}" 2>/dev/null || true
        fi
    done
    pkill -P $$ >/dev/null 2>&1 || true
}

trap 'echo "Exiting..."; trap - EXIT; zenbook-cleanup; exit 1' INT TERM
trap 'zenbook-cleanup' EXIT

# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/config.sh"
# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/detect/os.sh"
# shellcheck source=/dev/null
. "${ZENBOOK_LIB_DIR}/detect/desktop.sh"

zenbook-detect-os >/dev/null 2>&1 || true
zenbook-detect-desktop || true

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

if ! zenbook-ensure-runtime-dir; then
    exit 1
fi

echo "$(date) - INIT - OS=${ZENBOOK_OS_ID} DE=${ZENBOOK_DE} session=${ZENBOOK_SESSION} compositor=${ZENBOOK_COMPOSITOR} backend=${ZENBOOK_BACKEND} profile=${ZENBOOK_PROFILE}"

function zenbook-acquire-daemon-lock() {
    local lock_fd
    if ! exec {lock_fd}>"${DAEMON_LOCK}"; then
        echo "$(date) - FATAL - cannot open daemon lock ${DAEMON_LOCK}" >&2
        return 1
    fi
    if ! flock -n "${lock_fd}"; then
        echo "$(date) - FATAL - another zenbook daemon is already running" >&2
        return 1
    fi
    # Keep lock_fd open for the lifetime of this process.
    ZENBOOK_DAEMON_LOCK_FD=${lock_fd}
    return 0
}

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
    if ! zenbook-acquire-daemon-lock; then
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

    if zenbook-keyboard-attached; then
        zenbook-apply-docked-backlight "${DEFAULT_BACKLIGHT}" || true
    else
        zenbook-set-kb-backlight "${DETACH_BACKLIGHT}" "bt" || true
    fi
    # Force apply on startup so a docked keyboard disables eDP-2 immediately.
    zenbook-check-monitor 1
    zenbook-map-touch-inputs || true

    zenbook-start-watcher zenbook-watch-monitor
    zenbook-start-watcher zenbook-watch-rotate
    zenbook-start-watcher zenbook-watch-display-backlight
    zenbook-start-watcher zenbook-watch-wifi
    zenbook-start-watcher zenbook-watch-bluetooth

    zenbook-supervise-watchers
}

function zenbook-start-watcher() {
    local func="${1}"
    local pid
    "${func}" &
    pid=$!
    ZENBOOK_PIDS+=("${pid}")
    ZENBOOK_WATCHER_FUNCS["${pid}"]="${func}"
}

function zenbook-supervise-watchers() {
    local pid func restarted
    local -a alive_pids
    while [[ "${ZENBOOK_STOP}" -eq 0 ]]; do
        wait -n || true
        [[ "${ZENBOOK_STOP}" -eq 0 ]] || break

        alive_pids=()
        restarted=0
        for pid in "${ZENBOOK_PIDS[@]:-}"; do
            [[ -n "${pid}" ]] || continue
            if kill -0 "${pid}" 2>/dev/null; then
                alive_pids+=("${pid}")
                continue
            fi
            func="${ZENBOOK_WATCHER_FUNCS[${pid}]:-}"
            unset "ZENBOOK_WATCHER_FUNCS[${pid}]"
            if [[ -z "${func}" ]]; then
                continue
            fi
            echo "$(date) - INIT - watcher ${func} (pid ${pid}) exited; restarting" >&2
            "${func}" &
            pid=$!
            alive_pids+=("${pid}")
            ZENBOOK_WATCHER_FUNCS["${pid}"]="${func}"
            restarted=1
        done
        ZENBOOK_PIDS=("${alive_pids[@]}")

        # If wait -n returned for a non-watcher child (e.g. log tee), keep supervising.
        if [[ "${restarted}" -eq 0 && ${#ZENBOOK_PIDS[@]} -eq 0 ]]; then
            echo "$(date) - INIT - all watchers gone; exiting" >&2
            break
        fi
    done
}

if [ -z "${1:-}" ]; then
    main > >(tee -a "${LOG_FILE}") 2>&1
else
    zenbook-init-session-state
    zenbook-cli "$@" > >(tee -a "${LOG_FILE}") 2>&1
fi
