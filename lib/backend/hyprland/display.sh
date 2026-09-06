#!/bin/bash
# Hyprland Wayland backend via hyprctl.

function zenbook-hypr-transform() {
    case "${1}" in
        left|left-up) printf '1\n' ;;
        right|right-up) printf '3\n' ;;
        inverted|bottom-up) printf '2\n' ;;
        *) printf '0\n' ;;
    esac
}

function zenbook-monitor-count() {
    local json count
    json=$(hyprctl -j monitors 2>/dev/null || true)
    if [[ -n "${json}" ]]; then
        count=$(printf '%s\n' "${json}" | awk '
            /"disabled"[[:space:]]*:[[:space:]]*false/ { enabled++ }
            END { print enabled+0 }
        ')
        if [[ "${count}" =~ ^[0-9]+$ && "${count}" -gt 0 ]]; then
            printf '%s\n' "${count}"
            return 0
        fi
    fi
    hyprctl monitors 2>/dev/null | awk '
        /^Monitor / { count++ }
        END { print count+0 }
    ' || printf '0\n'
}

function zenbook-output-active() {
    local output="${1}"
    # Prefer JSON: active if listed and not disabled.
    if hyprctl -j monitors 2>/dev/null | awk -v output="${output}" '
        BEGIN { RS="{"; FS="\n" }
        {
            name=""; disabled=0
            for (i = 1; i <= NF; i++) {
                if ($i ~ /"name"/ && index($i, "\"" output "\"")) name=1
                if ($i ~ /"disabled"[[:space:]]*:[[:space:]]*true/) disabled=1
            }
            if (name && !disabled) found=1
        }
        END { exit(found ? 0 : 1) }
    '; then
        return 0
    fi
    hyprctl monitors 2>/dev/null | awk -v output="${output}" '
        $1 == "Monitor" && $2 == output { found=1 }
        END { exit(found ? 0 : 1) }
    '
}

function zenbook-output-connected() {
    local output="${1}"
    # Connected if the connector appears at all (enabled or disabled).
    if hyprctl -j monitors all 2>/dev/null | awk -v output="${output}" '
        index($0, "\"name\": \"" output "\"") || index($0, "\"name\":\"" output "\"") { found=1 }
        END { exit(found ? 0 : 1) }
    '; then
        return 0
    fi
    if hyprctl -j monitors 2>/dev/null | awk -v output="${output}" '
        index($0, "\"name\": \"" output "\"") || index($0, "\"name\":\"" output "\"") { found=1 }
        END { exit(found ? 0 : 1) }
    '; then
        return 0
    fi
    hyprctl monitors 2>/dev/null | awk -v output="${output}" '
        $1 == "Monitor" && $2 == output { found=1 }
        END { exit(found ? 0 : 1) }
    '
}

function zenbook-output-geometry() {
    local output="${1}"
    hyprctl monitors 2>/dev/null | awk -v output="${output}" '
        $1 == "Monitor" && $2 == output { cur=1; next }
        /^Monitor / { cur=0 }
        cur && /[0-9]+x[0-9]+@[0-9.]+ at [0-9]+x[0-9]+/ {
            split($1, a, "@")
            mode=a[1]
            split($3, b, "x")
            print mode "+" b[1] "+" b[2]
            exit
        }
    '
}

function zenbook-output-rotation() {
    local output="${1}"
    hyprctl monitors -j 2>/dev/null | jq -r --arg o "${output}" '
        .[]? | select(.name == $o) | (.transform // empty)
    '
}

function zenbook-disable-bottom-monitor() {
    local lock_fd rc=0
    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    if ! flock -x "${lock_fd}"; then
        echo "$(date) - DISPLAY - ERROR: cannot acquire display lock" >&2
        exec {lock_fd}>&-
        return 1
    fi

    zenbook-save-bottom-windows
    hyprctl keyword monitor "${TOP_OUTPUT},${TOP_MODE}@${TOP_RATE},0x0,1,transform,0" >/dev/null || rc=$?
    hyprctl keyword monitor "${BOTTOM_OUTPUT},disable" >/dev/null || rc=$?

    if (( rc == 0 )); then
        zenbook-move-saved-windows-to-top
    else
        rm -f "${BOTTOM_WINDOWS_STATE}"
    fi

    flock -u "${lock_fd}"
    exec {lock_fd}>&-
    return ${rc}
}

function zenbook-enable-bottom-monitor() {
    local lock_fd rc=0 top_h
    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    if ! flock -x "${lock_fd}"; then
        echo "$(date) - DISPLAY - ERROR: cannot acquire display lock" >&2
        exec {lock_fd}>&-
        return 1
    fi

    top_h=${TOP_MODE#*x}
    hyprctl keyword monitor "${TOP_OUTPUT},${TOP_MODE}@${TOP_RATE},0x0,1" >/dev/null || rc=$?
    hyprctl keyword monitor "${BOTTOM_OUTPUT},${BOTTOM_MODE}@${BOTTOM_RATE},0x${top_h},1" >/dev/null || rc=$?

    flock -u "${lock_fd}"
    exec {lock_fd}>&-

    if (( rc == 0 )); then
        sleep 0.15
        zenbook-sync-display-backlight
    fi
    return ${rc}
}

function zenbook-mirror-displays() {
    local lock_fd rc=0
    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    if ! flock -x "${lock_fd}"; then
        echo "$(date) - DISPLAY - ERROR: cannot acquire display lock" >&2
        exec {lock_fd}>&-
        return 1
    fi

    hyprctl keyword monitor "${TOP_OUTPUT},${TOP_MODE}@${TOP_RATE},0x0,1" >/dev/null || rc=$?
    hyprctl keyword monitor "${BOTTOM_OUTPUT},${BOTTOM_MODE}@${BOTTOM_RATE},0x0,1,mirror,${TOP_OUTPUT}" >/dev/null || rc=$?

    flock -u "${lock_fd}"
    exec {lock_fd}>&-
    return ${rc}
}

function zenbook-facing-displays() {
    local lock_fd rc=0 top_h
    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    if ! flock -x "${lock_fd}"; then
        echo "$(date) - DISPLAY - ERROR: cannot acquire display lock" >&2
        exec {lock_fd}>&-
        return 1
    fi

    top_h=${TOP_MODE#*x}
    hyprctl keyword monitor "${TOP_OUTPUT},${TOP_MODE}@${TOP_RATE},0x0,1,transform,0" >/dev/null || rc=$?
    hyprctl keyword monitor "${BOTTOM_OUTPUT},${BOTTOM_MODE}@${BOTTOM_RATE},0x${top_h},1,transform,2" >/dev/null || rc=$?

    flock -u "${lock_fd}"
    exec {lock_fd}>&-
    return ${rc}
}

function zenbook-rotate-displays() {
    local orientation="${1}"
    local lock_fd rc=0
    local transform top_h bottom_h
    local top_spec bottom_spec

    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    if ! flock -x "${lock_fd}"; then
        echo "$(date) - DISPLAY - ERROR: cannot acquire display lock" >&2
        exec {lock_fd}>&-
        return 1
    fi

    transform=$(zenbook-hypr-transform "${orientation}")
    top_h=${TOP_MODE#*x}
    bottom_h=${BOTTOM_MODE#*x}

    if [ "${KEYBOARD_ATTACHED}" = true ]; then
        hyprctl keyword monitor "${TOP_OUTPUT},${TOP_MODE}@${TOP_RATE},0x0,1,transform,${transform}" >/dev/null || rc=$?
        hyprctl keyword monitor "${BOTTOM_OUTPUT},disable" >/dev/null || rc=$?
    else
        case "${orientation}" in
            left-up)
                top_spec="${TOP_OUTPUT},${TOP_MODE}@${TOP_RATE},${bottom_h}x0,1,transform,${transform}"
                bottom_spec="${BOTTOM_OUTPUT},${BOTTOM_MODE}@${BOTTOM_RATE},0x0,1,transform,${transform}"
                ;;
            right-up)
                top_spec="${TOP_OUTPUT},${TOP_MODE}@${TOP_RATE},0x0,1,transform,${transform}"
                bottom_spec="${BOTTOM_OUTPUT},${BOTTOM_MODE}@${BOTTOM_RATE},${top_h}x0,1,transform,${transform}"
                ;;
            bottom-up)
                top_spec="${TOP_OUTPUT},${TOP_MODE}@${TOP_RATE},0x${bottom_h},1,transform,${transform}"
                bottom_spec="${BOTTOM_OUTPUT},${BOTTOM_MODE}@${BOTTOM_RATE},0x0,1,transform,${transform}"
                ;;
            *)
                top_spec="${TOP_OUTPUT},${TOP_MODE}@${TOP_RATE},0x0,1,transform,${transform}"
                bottom_spec="${BOTTOM_OUTPUT},${BOTTOM_MODE}@${BOTTOM_RATE},0x${top_h},1,transform,${transform}"
                ;;
        esac
        hyprctl keyword monitor "${top_spec}" >/dev/null || rc=$?
        hyprctl keyword monitor "${bottom_spec}" >/dev/null || rc=$?
    fi

    flock -u "${lock_fd}"
    exec {lock_fd}>&-
    return ${rc}
}
