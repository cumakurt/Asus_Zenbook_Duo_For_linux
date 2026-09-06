#!/bin/bash
# X11 display backend via XRandR (MATE, XFCE, Cinnamon, GNOME/KDE on X11, etc.).

function zenbook-monitor-count() {
    xrandr --listactivemonitors 2>/dev/null |
        awk 'NR > 1 {count++} END {print count+0}'
}

function zenbook-output-active() {
    local output="${1}"
    xrandr --query 2>/dev/null |
        awk -v output="${output}" '
            $1 == output && $2 == "connected" {
                for (i = 3; i <= NF; i++) {
                    if ($i ~ /^[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+$/) {
                        found = 1
                    }
                }
            }
            END { exit(found ? 0 : 1) }
        '
}

function zenbook-output-connected() {
    local output="${1}"
    xrandr --query 2>/dev/null |
        awk -v output="${output}" '
            $1 == output && $2 == "connected" { found = 1 }
            END { exit(found ? 0 : 1) }
        '
}

function zenbook-output-geometry() {
    local output="${1}"
    xrandr --query 2>/dev/null |
        awk -v output="${output}" '
            $1 == output && $2 == "connected" {
                for (i = 3; i <= NF; i++) {
                    if ($i ~ /^[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+$/) {
                        print $i
                        exit
                    }
                }
            }
        '
}

function zenbook-output-rotation() {
    local output="${1}"
    xrandr --query 2>/dev/null |
        awk -v output="${output}" '
            $1 == output && $2 == "connected" {
                for (i = 3; i <= NF; i++) {
                    if ($i ~ /^(normal|left|right|inverted)$/) {
                        print $i
                        exit
                    }
                }
            }
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
    xrandr \
        --output "${TOP_OUTPUT}" --primary --mode "${TOP_MODE}" --rate "${TOP_RATE}" --rotate normal --pos 0x0 \
        --output "${BOTTOM_OUTPUT}" --off || rc=$?

    if (( rc == 0 )); then
        zenbook-move-saved-windows-to-top
        zenbook-map-touch-inputs || true
    else
        rm -f "${BOTTOM_WINDOWS_STATE}"
    fi

    flock -u "${lock_fd}"
    exec {lock_fd}>&-
    return ${rc}
}

function zenbook-enable-bottom-monitor() {
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

    xrandr \
        --output "${TOP_OUTPUT}" --primary --mode "${TOP_MODE}" --rate "${TOP_RATE}" --rotate normal --pos 0x0 \
        --output "${BOTTOM_OUTPUT}" --mode "${BOTTOM_MODE}" --rate "${BOTTOM_RATE}" --rotate normal --below "${TOP_OUTPUT}" || rc=$?

    flock -u "${lock_fd}"
    exec {lock_fd}>&-

    if (( rc == 0 )); then
        sleep 0.15
        zenbook-sync-display-backlight
        zenbook-map-touch-inputs || true
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

    xrandr \
        --output "${TOP_OUTPUT}" --primary --mode "${TOP_MODE}" --rate "${TOP_RATE}" --rotate normal --pos 0x0 \
        --output "${BOTTOM_OUTPUT}" --mode "${BOTTOM_MODE}" --rate "${BOTTOM_RATE}" --rotate normal --same-as "${TOP_OUTPUT}" || rc=$?

    flock -u "${lock_fd}"
    exec {lock_fd}>&-

    if (( rc == 0 )); then
        zenbook-map-touch-inputs || true
    fi
    return ${rc}
}

function zenbook-facing-displays() {
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

    xrandr \
        --output "${TOP_OUTPUT}" --primary --mode "${TOP_MODE}" --rate "${TOP_RATE}" --rotate normal --pos 0x0 \
        --output "${BOTTOM_OUTPUT}" --mode "${BOTTOM_MODE}" --rate "${BOTTOM_RATE}" --rotate inverted --below "${TOP_OUTPUT}" || rc=$?

    flock -u "${lock_fd}"
    exec {lock_fd}>&-

    if (( rc == 0 )); then
        zenbook-map-touch-inputs || true
    fi
    return ${rc}
}

function zenbook-rotate-displays() {
    local orientation="${1}"
    local lock_fd
    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    if ! flock -x "${lock_fd}"; then
        echo "$(date) - DISPLAY - ERROR: cannot acquire display lock" >&2
        exec {lock_fd}>&-
        return 1
    fi

    local rc=0
    case "${orientation}" in
        left-up)
            if [ "${KEYBOARD_ATTACHED}" = true ]; then
                xrandr --output "${TOP_OUTPUT}" --primary --mode "${TOP_MODE}" --rate "${TOP_RATE}" --rotate left --pos 0x0 \
                       --output "${BOTTOM_OUTPUT}" --off || rc=$?
            else
                xrandr --output "${TOP_OUTPUT}" --primary --mode "${TOP_MODE}" --rate "${TOP_RATE}" --rotate left \
                       --output "${BOTTOM_OUTPUT}" --mode "${BOTTOM_MODE}" --rate "${BOTTOM_RATE}" --rotate left --left-of "${TOP_OUTPUT}" || rc=$?
            fi
            ;;
        right-up)
            if [ "${KEYBOARD_ATTACHED}" = true ]; then
                xrandr --output "${TOP_OUTPUT}" --primary --mode "${TOP_MODE}" --rate "${TOP_RATE}" --rotate right --pos 0x0 \
                       --output "${BOTTOM_OUTPUT}" --off || rc=$?
            else
                xrandr --output "${TOP_OUTPUT}" --primary --mode "${TOP_MODE}" --rate "${TOP_RATE}" --rotate right \
                       --output "${BOTTOM_OUTPUT}" --mode "${BOTTOM_MODE}" --rate "${BOTTOM_RATE}" --rotate right --right-of "${TOP_OUTPUT}" || rc=$?
            fi
            ;;
        bottom-up)
            if [ "${KEYBOARD_ATTACHED}" = true ]; then
                xrandr --output "${TOP_OUTPUT}" --primary --mode "${TOP_MODE}" --rate "${TOP_RATE}" --rotate inverted --pos 0x0 \
                       --output "${BOTTOM_OUTPUT}" --off || rc=$?
            else
                xrandr --output "${TOP_OUTPUT}" --primary --mode "${TOP_MODE}" --rate "${TOP_RATE}" --rotate inverted \
                       --output "${BOTTOM_OUTPUT}" --mode "${BOTTOM_MODE}" --rate "${BOTTOM_RATE}" --rotate inverted --above "${TOP_OUTPUT}" || rc=$?
            fi
            ;;
        normal)
            if [ "${KEYBOARD_ATTACHED}" = true ]; then
                xrandr --output "${TOP_OUTPUT}" --primary --mode "${TOP_MODE}" --rate "${TOP_RATE}" --rotate normal --pos 0x0 \
                       --output "${BOTTOM_OUTPUT}" --off || rc=$?
            else
                xrandr --output "${TOP_OUTPUT}" --primary --mode "${TOP_MODE}" --rate "${TOP_RATE}" --rotate normal --pos 0x0 \
                       --output "${BOTTOM_OUTPUT}" --mode "${BOTTOM_MODE}" --rate "${BOTTOM_RATE}" --rotate normal --below "${TOP_OUTPUT}" || rc=$?
            fi
            ;;
    esac

    flock -u "${lock_fd}"
    exec {lock_fd}>&-

    if (( rc == 0 )); then
        zenbook-map-touch-inputs || true
    fi
    return ${rc}
}
