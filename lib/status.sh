#!/bin/bash
# Runtime status file helpers with flock-safe updates.

function zenbook-load-status() {
    if [[ -f "${STATUS_FILE}" ]]; then
        # shellcheck disable=SC1090
        . "${STATUS_FILE}"
    fi
    ROTATE_LOCK=${ROTATE_LOCK:-false}
    SHARE_MODE=${SHARE_MODE:-extend}
}

function zenbook-set-status() {
    local lock_fd
    mkdir -p "${RUNTIME_DIR}"
    ROTATE_LOCK=${ROTATE_LOCK:-false}
    SHARE_MODE=${SHARE_MODE:-extend}
    exec {lock_fd}>"${STATUS_LOCK}"
    flock -x "${lock_fd}"
    {
        printf 'BLUETOOTH_BEFORE=%q\n' "${BLUETOOTH_BEFORE}"
        printf 'WIFI_BEFORE=%q\n' "${WIFI_BEFORE}"
        printf 'KEYBOARD_ATTACHED=%q\n' "${KEYBOARD_ATTACHED}"
        printf 'MONITOR_COUNT=%q\n' "${MONITOR_COUNT}"
        printf 'ROTATE_LOCK=%q\n' "${ROTATE_LOCK}"
        printf 'SHARE_MODE=%q\n' "${SHARE_MODE}"
    } > "${STATUS_FILE}"
    chmod 600 "${STATUS_FILE}" 2>/dev/null || true
    flock -u "${lock_fd}"
    exec {lock_fd}>&-
}
