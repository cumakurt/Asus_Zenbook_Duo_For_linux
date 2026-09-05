#!/bin/bash
# GNOME Wayland display backend via gdctl (Mutter DisplayConfig).

function zenbook-gnome-mode-spec() {
    local mode="${1}"
    local rate="${2}"
    printf '%s@%s\n' "${mode}" "${rate}"
}

function zenbook-gnome-transform() {
    case "${1}" in
        left|left-up) printf '90\n' ;;
        right|right-up) printf '270\n' ;;
        inverted|bottom-up) printf '180\n' ;;
        *) printf 'normal\n' ;;
    esac
}

function zenbook-monitor-count() {
    local show
    show=$(gdctl show 2>/dev/null) || { printf '0\n'; return 0; }
    printf '%s\n' "${show}" | awk '
        /^Logical monitors:/ { in_logical=1; next }
        /^Monitors:/ { in_logical=0 }
        in_logical && /^[[:space:]]*[0-9]+:/ { count++ }
        END { print count+0 }
    '
}

function zenbook-output-active() {
    local output="${1}"
    local show
    show=$(gdctl show 2>/dev/null) || return 1
    printf '%s\n' "${show}" | awk -v output="${output}" '
        /^Logical monitors:/ { in_logical=1; next }
        /^Monitors:/ { in_logical=0 }
        in_logical && index($0, output) { found=1 }
        END { exit(found ? 0 : 1) }
    '
}

function zenbook-output-connected() {
    local output="${1}"
    local show
    show=$(gdctl show 2>/dev/null) || return 1
    # Any mention under Monitors: means the connector is present.
    if printf '%s\n' "${show}" | awk -v output="${output}" '
        /^Monitors:/ { in_mon=1; next }
        /^Logical monitors:/ { in_mon=0 }
        in_mon && index($0, output) { found=1 }
        END { exit(found ? 0 : 1) }
    '; then
        return 0
    fi
    # Fallback if gdctl layout differs: treat active as connected.
    zenbook-output-active "${output}"
}

function zenbook-output-geometry() {
    local output="${1}"
    local show
    show=$(gdctl show 2>/dev/null) || return 0
    # Best-effort parse: "WxH@R +X+Y" style lines near the connector name.
    printf '%s\n' "${show}" | awk -v output="${output}" '
        index($0, output) {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9]+x[0-9]+/) {
                    mode=$i
                    gsub(/@.*$/, "", mode)
                }
                if ($i ~ /^\+[0-9]+\+[0-9]+$/ || $i ~ /^[+-][0-9]+[+-][0-9]+$/) {
                    pos=$i
                }
            }
            if (mode != "" && pos != "") {
                print mode pos
                exit
            }
            if (mode != "") {
                print mode "+0+0"
                exit
            }
        }
    '
}

function zenbook-disable-bottom-monitor() {
    local lock_fd mode_spec rc
    exec {lock_fd}>"${DISPLAY_LOCK}"
    flock -x "${lock_fd}"

    zenbook-save-bottom-windows
    mode_spec=$(zenbook-gnome-mode-spec "${TOP_MODE}" "${TOP_RATE}")
    gdctl set \
        --logical-monitor --primary \
        --monitor "${TOP_OUTPUT}" --mode "${mode_spec}"
    rc=$?

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
    local lock_fd top_mode bottom_mode rc
    exec {lock_fd}>"${DISPLAY_LOCK}"
    flock -x "${lock_fd}"

    top_mode=$(zenbook-gnome-mode-spec "${TOP_MODE}" "${TOP_RATE}")
    bottom_mode=$(zenbook-gnome-mode-spec "${BOTTOM_MODE}" "${BOTTOM_RATE}")
    gdctl set \
        --logical-monitor --primary \
        --monitor "${TOP_OUTPUT}" --mode "${top_mode}" \
        --logical-monitor --below "${TOP_OUTPUT}" \
        --monitor "${BOTTOM_OUTPUT}" --mode "${bottom_mode}"
    rc=$?

    flock -u "${lock_fd}"
    exec {lock_fd}>&-

    if (( rc == 0 )); then
        sleep 0.15
        zenbook-sync-display-backlight
    fi
    return ${rc}
}

function zenbook-rotate-displays() {
    local orientation="${1}"
    local lock_fd rc=0
    local top_mode bottom_mode transform
    local pos_flag="--below"

    exec {lock_fd}>"${DISPLAY_LOCK}"
    flock -x "${lock_fd}"

    top_mode=$(zenbook-gnome-mode-spec "${TOP_MODE}" "${TOP_RATE}")
    bottom_mode=$(zenbook-gnome-mode-spec "${BOTTOM_MODE}" "${BOTTOM_RATE}")
    transform=$(zenbook-gnome-transform "${orientation}")

    case "${orientation}" in
        left-up) pos_flag="--left-of" ;;
        right-up) pos_flag="--right-of" ;;
        bottom-up) pos_flag="--above" ;;
        *) pos_flag="--below" ;;
    esac

    if [ "${KEYBOARD_ATTACHED}" = true ]; then
        gdctl set \
            --logical-monitor --primary --transform "${transform}" \
            --monitor "${TOP_OUTPUT}" --mode "${top_mode}" || rc=$?
    else
        gdctl set \
            --logical-monitor --primary --transform "${transform}" \
            --monitor "${TOP_OUTPUT}" --mode "${top_mode}" \
            --logical-monitor "${pos_flag}" "${TOP_OUTPUT}" --transform "${transform}" \
            --monitor "${BOTTOM_OUTPUT}" --mode "${bottom_mode}" || rc=$?
    fi

    flock -u "${lock_fd}"
    exec {lock_fd}>&-
    return ${rc}
}
