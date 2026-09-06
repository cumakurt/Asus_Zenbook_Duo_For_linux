#!/bin/bash
# wlroots Wayland backend via wlr-randr (Sway, Wayfire, labwc, river, niri, etc.).

function zenbook-wlr-transform() {
    case "${1}" in
        left|left-up) printf '90\n' ;;
        right|right-up) printf '270\n' ;;
        inverted|bottom-up) printf '180\n' ;;
        *) printf 'normal\n' ;;
    esac
}

function zenbook-monitor-count() {
    local out
    out=$(wlr-randr 2>/dev/null) || { printf '0\n'; return 0; }
    printf '%s\n' "${out}" | awk '
        /^[^[:space:]]/ { name=$1 }
        /Enabled: yes/ { count++; name="" }
        END { print count+0 }
    '
}

function zenbook-output-active() {
    local output="${1}"
    local out
    out=$(wlr-randr 2>/dev/null) || return 1
    printf '%s\n' "${out}" | awk -v output="${output}" '
        $1 == output { cur=1; next }
        /^[^[:space:]]/ { cur=0 }
        cur && /Enabled: yes/ { found=1 }
        END { exit(found ? 0 : 1) }
    '
}

function zenbook-output-connected() {
    local output="${1}"
    local out
    out=$(wlr-randr 2>/dev/null) || return 1
    printf '%s\n' "${out}" | awk -v output="${output}" '
        $1 == output { found=1 }
        END { exit(found ? 0 : 1) }
    '
}

function zenbook-output-geometry() {
    local output="${1}"
    local out
    out=$(wlr-randr 2>/dev/null) || return 0
    printf '%s\n' "${out}" | awk -v output="${output}" '
        $1 == output { cur=1; next }
        /^[^[:space:]]/ { cur=0 }
        cur && /current/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9]+x[0-9]+/) {
                    mode=$i
                    gsub(/,.*/, "", mode)
                }
            }
        }
        cur && /Position:/ {
            pos=$2
            gsub(/,/, "+", pos)
            if (mode != "") {
                print mode "+" pos
                exit
            }
        }
    '
}

function zenbook-output-rotation() {
    local output="${1}"
    wlr-randr 2>/dev/null | awk -v out="${output}" '
        $1 == out { in_out=1; next }
        /^[a-zA-Z0-9]/ { in_out=0 }
        in_out && /Transform:/ { print $2; exit }
    '
}

function zenbook-disable-bottom-monitor() {
    local lock_fd rc
    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    flock -x "${lock_fd}"

    zenbook-save-bottom-windows
    wlr-randr --output "${TOP_OUTPUT}" --on --mode "${TOP_MODE}@${TOP_RATE}Hz" --pos 0,0 --transform normal \
              --output "${BOTTOM_OUTPUT}" --off
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
    local lock_fd rc top_h
    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    flock -x "${lock_fd}"

    top_h=${TOP_MODE#*x}
    wlr-randr \
        --output "${TOP_OUTPUT}" --on \
        --mode "${TOP_MODE}@${TOP_RATE}Hz" --pos 0,0 --transform normal \
        --output "${BOTTOM_OUTPUT}" --on \
        --mode "${BOTTOM_MODE}@${BOTTOM_RATE}Hz" --pos "0,${top_h}" --transform normal
    rc=$?

    flock -u "${lock_fd}"
    exec {lock_fd}>&-

    if (( rc == 0 )); then
        sleep 0.15
        zenbook-sync-display-backlight
    fi
    return ${rc}
}

function zenbook-mirror-displays() {
    local lock_fd rc
    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    flock -x "${lock_fd}"

    wlr-randr \
        --output "${TOP_OUTPUT}" --on \
        --mode "${TOP_MODE}@${TOP_RATE}Hz" --pos 0,0 --transform normal \
        --output "${BOTTOM_OUTPUT}" --on \
        --mode "${BOTTOM_MODE}@${BOTTOM_RATE}Hz" --pos 0,0 --transform normal
    rc=$?

    flock -u "${lock_fd}"
    exec {lock_fd}>&-
    return ${rc}
}

function zenbook-facing-displays() {
    local lock_fd rc top_h
    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    flock -x "${lock_fd}"

    top_h=${TOP_MODE#*x}
    wlr-randr \
        --output "${TOP_OUTPUT}" --on \
        --mode "${TOP_MODE}@${TOP_RATE}Hz" --pos 0,0 --transform normal \
        --output "${BOTTOM_OUTPUT}" --on \
        --mode "${BOTTOM_MODE}@${BOTTOM_RATE}Hz" --pos "0,${top_h}" --transform 180
    rc=$?

    flock -u "${lock_fd}"
    exec {lock_fd}>&-
    return ${rc}
}

function zenbook-rotate-displays() {
    local orientation="${1}"
    local lock_fd rc=0
    local transform top_h bottom_h

    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    flock -x "${lock_fd}"

    transform=$(zenbook-wlr-transform "${orientation}")
    top_h=${TOP_MODE#*x}
    bottom_h=${BOTTOM_MODE#*x}

    if [ "${KEYBOARD_ATTACHED}" = true ]; then
        wlr-randr \
            --output "${TOP_OUTPUT}" --on --mode "${TOP_MODE}@${TOP_RATE}Hz" \
            --pos 0,0 --transform "${transform}" \
            --output "${BOTTOM_OUTPUT}" --off || rc=$?
    else
        case "${orientation}" in
            left-up)
                wlr-randr \
                    --output "${TOP_OUTPUT}" --on --mode "${TOP_MODE}@${TOP_RATE}Hz" \
                    --pos "${bottom_h},0" --transform "${transform}" \
                    --output "${BOTTOM_OUTPUT}" --on --mode "${BOTTOM_MODE}@${BOTTOM_RATE}Hz" \
                    --pos 0,0 --transform "${transform}" || rc=$?
                ;;
            right-up)
                wlr-randr \
                    --output "${TOP_OUTPUT}" --on --mode "${TOP_MODE}@${TOP_RATE}Hz" \
                    --pos 0,0 --transform "${transform}" \
                    --output "${BOTTOM_OUTPUT}" --on --mode "${BOTTOM_MODE}@${BOTTOM_RATE}Hz" \
                    --pos "${top_h},0" --transform "${transform}" || rc=$?
                ;;
            bottom-up)
                wlr-randr \
                    --output "${TOP_OUTPUT}" --on --mode "${TOP_MODE}@${TOP_RATE}Hz" \
                    --pos "0,${top_h}" --transform "${transform}" \
                    --output "${BOTTOM_OUTPUT}" --on --mode "${BOTTOM_MODE}@${BOTTOM_RATE}Hz" \
                    --pos 0,0 --transform "${transform}" || rc=$?
                ;;
            *)
                wlr-randr \
                    --output "${TOP_OUTPUT}" --on --mode "${TOP_MODE}@${TOP_RATE}Hz" \
                    --pos 0,0 --transform "${transform}" \
                    --output "${BOTTOM_OUTPUT}" --on --mode "${BOTTOM_MODE}@${BOTTOM_RATE}Hz" \
                    --pos "0,${top_h}" --transform "${transform}" || rc=$?
                ;;
        esac
    fi

    flock -u "${lock_fd}"
    exec {lock_fd}>&-
    return ${rc}
}
