#!/bin/bash
# KDE Plasma Wayland display backend via kscreen-doctor.

function zenbook-kde-rotation() {
    case "${1}" in
        left|left-up) printf 'left\n' ;;
        right|right-up) printf 'right\n' ;;
        inverted|bottom-up) printf 'inverted\n' ;;
        *) printf 'normal\n' ;;
    esac
}

function zenbook-monitor-count() {
    local out
    out=$(kscreen-doctor -o 2>/dev/null) || { printf '0\n'; return 0; }
    printf '%s\n' "${out}" | awk '
        $1 == "Output:" {
            # Format: Output: <id> <name> ...
            name = (NF >= 3 ? $3 : $2)
            next
        }
        /enabled/ && name != "" { count++; name="" }
        END { print count+0 }
    '
}

function zenbook-output-active() {
    local output="${1}"
    local out
    out=$(kscreen-doctor -o 2>/dev/null) || return 1
    printf '%s\n' "${out}" | awk -v output="${output}" '
        $1 == "Output:" {
            name = (NF >= 3 ? $3 : $2)
            cur = (name == output)
            next
        }
        cur && /enabled/ { found=1 }
        END { exit(found ? 0 : 1) }
    '
}

function zenbook-output-connected() {
    local output="${1}"
    local out
    out=$(kscreen-doctor -o 2>/dev/null) || return 1
    printf '%s\n' "${out}" | awk -v output="${output}" '
        $1 == "Output:" {
            name = (NF >= 3 ? $3 : $2)
            if (name == output) found=1
        }
        END { exit(found ? 0 : 1) }
    '
}

function zenbook-output-geometry() {
    local output="${1}"
    local out
    out=$(kscreen-doctor -o 2>/dev/null) || return 0
    printf '%s\n' "${out}" | awk -v output="${output}" '
        $1 == "Output:" {
            name = (NF >= 3 ? $3 : $2)
            cur = (name == output)
            next
        }
        cur && /Geometry:/ {
            # Common: "Geometry: X,Y WxH"
            pos=$2
            size=$3
            gsub(/,/, "+", pos)
            if (size ~ /^[0-9]+x[0-9]+$/ && pos ~ /^-?[0-9]+\+-?[0-9]+$/) {
                print size "+" pos
                exit
            }
            for (i = 1; i <= NF; i++) {
                if ($i ~ /[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+/) {
                    print $i
                    exit
                }
            }
        }
        cur && /Modes:/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9]+x[0-9]+/) {
                    gsub(/@.*$/, "", $i)
                    print $i "+0+0"
                    exit
                }
            }
        }
    '
}

function zenbook-disable-bottom-monitor() {
    local lock_fd rc
    exec {lock_fd}>"${DISPLAY_LOCK}"
    flock -x "${lock_fd}"

    zenbook-save-bottom-windows
    kscreen-doctor \
        "output.${TOP_OUTPUT}.enable" \
        "output.${TOP_OUTPUT}.primary" \
        "output.${TOP_OUTPUT}.position.0,0" \
        "output.${BOTTOM_OUTPUT}.disable"
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
    exec {lock_fd}>"${DISPLAY_LOCK}"
    flock -x "${lock_fd}"

    top_h=${TOP_MODE#*x}
    kscreen-doctor \
        "output.${TOP_OUTPUT}.enable" \
        "output.${TOP_OUTPUT}.mode.${TOP_MODE}@${TOP_RATE}" \
        "output.${TOP_OUTPUT}.rotation.normal" \
        "output.${TOP_OUTPUT}.primary" \
        "output.${TOP_OUTPUT}.position.0,0" \
        "output.${BOTTOM_OUTPUT}.enable" \
        "output.${BOTTOM_OUTPUT}.mode.${BOTTOM_MODE}@${BOTTOM_RATE}" \
        "output.${BOTTOM_OUTPUT}.rotation.normal" \
        "output.${BOTTOM_OUTPUT}.position.0,${top_h}"
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
    local rotation pos_x=0 pos_y=0
    local top_w top_h bottom_w

    exec {lock_fd}>"${DISPLAY_LOCK}"
    flock -x "${lock_fd}"

    rotation=$(zenbook-kde-rotation "${orientation}")
    top_w=${TOP_MODE%x*}
    top_h=${TOP_MODE#*x}
    bottom_w=${BOTTOM_MODE%x*}

    case "${orientation}" in
        left-up) pos_x=0; pos_y=0 ;;
        right-up) pos_x=${top_w}; pos_y=0 ;;
        bottom-up) pos_x=0; pos_y=0 ;;
        *) pos_x=0; pos_y=${top_h} ;;
    esac

    if [ "${KEYBOARD_ATTACHED}" = true ]; then
        kscreen-doctor \
            "output.${TOP_OUTPUT}.enable" \
            "output.${TOP_OUTPUT}.mode.${TOP_MODE}@${TOP_RATE}" \
            "output.${TOP_OUTPUT}.rotation.${rotation}" \
            "output.${TOP_OUTPUT}.primary" \
            "output.${TOP_OUTPUT}.position.0,0" \
            "output.${BOTTOM_OUTPUT}.disable" || rc=$?
    else
        case "${orientation}" in
            left-up)
                kscreen-doctor \
                    "output.${TOP_OUTPUT}.enable" \
                    "output.${TOP_OUTPUT}.mode.${TOP_MODE}@${TOP_RATE}" \
                    "output.${TOP_OUTPUT}.rotation.${rotation}" \
                    "output.${TOP_OUTPUT}.primary" \
                    "output.${TOP_OUTPUT}.position.${bottom_w},0" \
                    "output.${BOTTOM_OUTPUT}.enable" \
                    "output.${BOTTOM_OUTPUT}.mode.${BOTTOM_MODE}@${BOTTOM_RATE}" \
                    "output.${BOTTOM_OUTPUT}.rotation.${rotation}" \
                    "output.${BOTTOM_OUTPUT}.position.0,0" || rc=$?
                ;;
            right-up)
                kscreen-doctor \
                    "output.${TOP_OUTPUT}.enable" \
                    "output.${TOP_OUTPUT}.mode.${TOP_MODE}@${TOP_RATE}" \
                    "output.${TOP_OUTPUT}.rotation.${rotation}" \
                    "output.${TOP_OUTPUT}.primary" \
                    "output.${TOP_OUTPUT}.position.0,0" \
                    "output.${BOTTOM_OUTPUT}.enable" \
                    "output.${BOTTOM_OUTPUT}.mode.${BOTTOM_MODE}@${BOTTOM_RATE}" \
                    "output.${BOTTOM_OUTPUT}.rotation.${rotation}" \
                    "output.${BOTTOM_OUTPUT}.position.${top_w},0" || rc=$?
                ;;
            bottom-up)
                kscreen-doctor \
                    "output.${TOP_OUTPUT}.enable" \
                    "output.${TOP_OUTPUT}.mode.${TOP_MODE}@${TOP_RATE}" \
                    "output.${TOP_OUTPUT}.rotation.${rotation}" \
                    "output.${TOP_OUTPUT}.primary" \
                    "output.${TOP_OUTPUT}.position.0,${top_h}" \
                    "output.${BOTTOM_OUTPUT}.enable" \
                    "output.${BOTTOM_OUTPUT}.mode.${BOTTOM_MODE}@${BOTTOM_RATE}" \
                    "output.${BOTTOM_OUTPUT}.rotation.${rotation}" \
                    "output.${BOTTOM_OUTPUT}.position.0,0" || rc=$?
                ;;
            *)
                kscreen-doctor \
                    "output.${TOP_OUTPUT}.enable" \
                    "output.${TOP_OUTPUT}.mode.${TOP_MODE}@${TOP_RATE}" \
                    "output.${TOP_OUTPUT}.rotation.${rotation}" \
                    "output.${TOP_OUTPUT}.primary" \
                    "output.${TOP_OUTPUT}.position.0,0" \
                    "output.${BOTTOM_OUTPUT}.enable" \
                    "output.${BOTTOM_OUTPUT}.mode.${BOTTOM_MODE}@${BOTTOM_RATE}" \
                    "output.${BOTTOM_OUTPUT}.rotation.${rotation}" \
                    "output.${BOTTOM_OUTPUT}.position.0,${top_h}" || rc=$?
                ;;
        esac
    fi

    flock -u "${lock_fd}"
    exec {lock_fd}>&-
    return ${rc}
}
