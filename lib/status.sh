#!/bin/bash
# Runtime status file helpers — safe parse + atomic write (no shell source).

function zenbook-ensure-runtime-dir() {
    local owner mode

    if [[ -e "${RUNTIME_DIR}" && ! -d "${RUNTIME_DIR}" ]]; then
        echo "$(date) - FATAL - Runtime path exists and is not a directory: ${RUNTIME_DIR}" >&2
        return 1
    fi
    mkdir -m 700 -p "${RUNTIME_DIR}" 2>/dev/null || true
    chmod 700 "${RUNTIME_DIR}" 2>/dev/null || true

    # Refuse a world-writable or foreign-owned runtime dir (especially /tmp fallback).
    if [[ -d "${RUNTIME_DIR}" ]]; then
        owner=$(stat -c '%u' "${RUNTIME_DIR}" 2>/dev/null || true)
        mode=$(stat -c '%a' "${RUNTIME_DIR}" 2>/dev/null || true)
        if [[ -n "${owner}" && "${owner}" != "$(id -u)" ]]; then
            echo "$(date) - FATAL - Runtime dir not owned by current user: ${RUNTIME_DIR}" >&2
            return 1
        fi
        if [[ -n "${mode}" && "${mode}" != "700" ]]; then
            chmod 700 "${RUNTIME_DIR}" 2>/dev/null || true
        fi
    fi
    return 0
}

function zenbook-load-status() {
    local key value line
    local lock_fd

    ROTATE_LOCK=${ROTATE_LOCK:-false}
    SHARE_MODE=${SHARE_MODE:-extend}

    [[ -f "${STATUS_FILE}" ]] || return 0

    # Shared lock so we never read a truncated mid-write file.
    : >> "${STATUS_LOCK}" 2>/dev/null || true
    if exec {lock_fd}<"${STATUS_LOCK}" 2>/dev/null; then
        flock -s "${lock_fd}" 2>/dev/null || true
    else
        lock_fd=""
    fi

    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
        key=${line%%=*}
        value=${line#*=}
        # Strip one layer of shell quoting produced by printf %q.
        if [[ "${value}" =~ ^\'.*\'$ ]]; then
            value=${value:1:${#value}-2}
            value=${value//\'\\\'\'/\'}
        elif [[ "${value}" =~ ^\".*\"$ ]]; then
            value=${value:1:${#value}-2}
        fi
        case "${key}" in
            BLUETOOTH_BEFORE) BLUETOOTH_BEFORE=${value} ;;
            WIFI_BEFORE) WIFI_BEFORE=${value} ;;
            KEYBOARD_ATTACHED) KEYBOARD_ATTACHED=${value} ;;
            MONITOR_COUNT) MONITOR_COUNT=${value} ;;
            ROTATE_LOCK) ROTATE_LOCK=${value} ;;
            SHARE_MODE) SHARE_MODE=${value} ;;
        esac
    done < "${STATUS_FILE}"

    if [[ -n "${lock_fd}" ]]; then
        flock -u "${lock_fd}" 2>/dev/null || true
        exec {lock_fd}<&- 2>/dev/null || true
    fi

    ROTATE_LOCK=${ROTATE_LOCK:-false}
    SHARE_MODE=${SHARE_MODE:-extend}
}

function zenbook-set-status() {
    local lock_fd tmp

    zenbook-ensure-runtime-dir || return 1
    ROTATE_LOCK=${ROTATE_LOCK:-false}
    SHARE_MODE=${SHARE_MODE:-extend}

    if ! exec {lock_fd}>"${STATUS_LOCK}"; then
        echo "$(date) - STATUS - WARNING: cannot open status lock" >&2
        return 1
    fi
    if ! flock -x "${lock_fd}"; then
        echo "$(date) - STATUS - WARNING: cannot lock status file" >&2
        exec {lock_fd}>&-
        return 1
    fi

    tmp=$(mktemp "${RUNTIME_DIR}/status.XXXXXX") || {
        flock -u "${lock_fd}"
        exec {lock_fd}>&-
        return 1
    }
    {
        printf 'BLUETOOTH_BEFORE=%q\n' "${BLUETOOTH_BEFORE}"
        printf 'WIFI_BEFORE=%q\n' "${WIFI_BEFORE}"
        printf 'KEYBOARD_ATTACHED=%q\n' "${KEYBOARD_ATTACHED}"
        printf 'MONITOR_COUNT=%q\n' "${MONITOR_COUNT}"
        printf 'ROTATE_LOCK=%q\n' "${ROTATE_LOCK}"
        printf 'SHARE_MODE=%q\n' "${SHARE_MODE}"
    } > "${tmp}"
    chmod 600 "${tmp}" 2>/dev/null || true
    mv -f "${tmp}" "${STATUS_FILE}"

    flock -u "${lock_fd}"
    exec {lock_fd}>&-
}
