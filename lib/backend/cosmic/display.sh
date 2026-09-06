#!/bin/bash
# System76 COSMIC Wayland backend via cosmic-randr.

function zenbook-cosmic-transform() {
    case "${1}" in
        left|left-up) printf 'rotate90\n' ;;
        right|right-up) printf 'rotate270\n' ;;
        inverted|bottom-up) printf 'rotate180\n' ;;
        *) printf 'normal\n' ;;
    esac
}

function zenbook-cosmic-refresh-mHz() {
    # cosmic-randr refresh is millihertz.
    printf '%s\n' "$(( ${1} * 1000 ))"
}

function zenbook-monitor-count() {
    local out
    out=$(cosmic-randr list 2>/dev/null) || { printf '0\n'; return 0; }
    printf '%s\n' "${out}" | awk '
        /^[^[:space:]].*\(/ && $0 !~ /\(disabled\)/ { count++ }
        END { print count+0 }
    '
}

function zenbook-output-active() {
    local output="${1}"
    local out
    out=$(cosmic-randr list 2>/dev/null) || return 1
    printf '%s\n' "${out}" | awk -v output="${output}" '
        index($0, " " output " ") || $0 ~ ("^" output "\\(") || $0 ~ ("^" output " ") {
            if ($0 !~ /\(disabled\)/) found=1
        }
        END { exit(found ? 0 : 1) }
    '
}

function zenbook-output-connected() {
    local output="${1}"
    local out
    out=$(cosmic-randr list 2>/dev/null) || return 1
    printf '%s\n' "${out}" | awk -v output="${output}" '
        index($0, " " output " ") || $0 ~ ("^" output "\\(") || $0 ~ ("^" output " ") {
            found=1
        }
        END { exit(found ? 0 : 1) }
    '
}

function zenbook-output-geometry() {
    local output="${1}"
    local out
    out=$(cosmic-randr list 2>/dev/null) || return 0
    printf '%s\n' "${out}" | awk -v output="${output}" '
        index($0, output) { cur=1; next }
        cur && /Position:/ {
            pos=$2
            gsub(/,/, "+", pos)
        }
        cur && /current/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9]+x[0-9]+/) {
                    mode=$i
                    gsub(/@.*/, "", mode)
                }
            }
            if (mode != "" && pos != "") {
                print mode "+" pos
                exit
            }
            if (mode != "") {
                print mode "+0+0"
                exit
            }
        }
        /^[^[:space:]]/ && cur && !index($0, output) { cur=0 }
    '
}

function zenbook-output-rotation() {
    local output="${1}"
    local out
    out=$(cosmic-randr list 2>/dev/null) || return 1
    printf '%s\n' "${out}" | awk -v output="${output}" '
        index($0, output) { cur=1; next }
        cur && /Transform:/ { print $2; exit }
        /^[^[:space:]]/ && cur && !index($0, output) { cur=0 }
    '
}

function zenbook-disable-bottom-monitor() {
    local lock_fd rc=0 w h refresh
    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    flock -x "${lock_fd}"

    zenbook-save-bottom-windows
    w=${TOP_MODE%x*}
    h=${TOP_MODE#*x}
    refresh=$(zenbook-cosmic-refresh-mHz "${TOP_RATE}")
    cosmic-randr mode "${TOP_OUTPUT}" "${w}" "${h}" --refresh "${refresh}" --pos-x 0 --pos-y 0 --transform normal || rc=$?
    cosmic-randr disable "${BOTTOM_OUTPUT}" || rc=$?

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
    local lock_fd rc=0 tw th bw bh top_refresh bottom_refresh top_h
    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    flock -x "${lock_fd}"

    tw=${TOP_MODE%x*}
    th=${TOP_MODE#*x}
    bw=${BOTTOM_MODE%x*}
    bh=${BOTTOM_MODE#*x}
    top_h=${th}
    top_refresh=$(zenbook-cosmic-refresh-mHz "${TOP_RATE}")
    bottom_refresh=$(zenbook-cosmic-refresh-mHz "${BOTTOM_RATE}")

    cosmic-randr enable "${BOTTOM_OUTPUT}" >/dev/null 2>&1 || true
    cosmic-randr mode "${TOP_OUTPUT}" "${tw}" "${th}" --refresh "${top_refresh}" --pos-x 0 --pos-y 0 --transform normal || rc=$?
    cosmic-randr mode "${BOTTOM_OUTPUT}" "${bw}" "${bh}" --refresh "${bottom_refresh}" --pos-x 0 --pos-y "${top_h}" --transform normal || rc=$?

    flock -u "${lock_fd}"
    exec {lock_fd}>&-

    if (( rc == 0 )); then
        sleep 0.15
        zenbook-sync-display-backlight
    fi
    return ${rc}
}

function zenbook-mirror-displays() {
    local lock_fd rc=0 tw th bw bh top_refresh bottom_refresh
    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    flock -x "${lock_fd}"

    tw=${TOP_MODE%x*}
    th=${TOP_MODE#*x}
    bw=${BOTTOM_MODE%x*}
    bh=${BOTTOM_MODE#*x}
    top_refresh=$(zenbook-cosmic-refresh-mHz "${TOP_RATE}")
    bottom_refresh=$(zenbook-cosmic-refresh-mHz "${BOTTOM_RATE}")

    cosmic-randr enable "${BOTTOM_OUTPUT}" >/dev/null 2>&1 || true
    cosmic-randr mode "${TOP_OUTPUT}" "${tw}" "${th}" --refresh "${top_refresh}" --pos-x 0 --pos-y 0 --transform normal || rc=$?
    cosmic-randr mode "${BOTTOM_OUTPUT}" "${bw}" "${bh}" --refresh "${bottom_refresh}" --pos-x 0 --pos-y 0 --transform normal || rc=$?

    flock -u "${lock_fd}"
    exec {lock_fd}>&-
    return ${rc}
}

function zenbook-facing-displays() {
    local lock_fd rc=0 tw th bw bh top_refresh bottom_refresh top_h
    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    flock -x "${lock_fd}"

    tw=${TOP_MODE%x*}
    th=${TOP_MODE#*x}
    bw=${BOTTOM_MODE%x*}
    bh=${BOTTOM_MODE#*x}
    top_h=${th}
    top_refresh=$(zenbook-cosmic-refresh-mHz "${TOP_RATE}")
    bottom_refresh=$(zenbook-cosmic-refresh-mHz "${BOTTOM_RATE}")

    cosmic-randr enable "${BOTTOM_OUTPUT}" >/dev/null 2>&1 || true
    cosmic-randr mode "${TOP_OUTPUT}" "${tw}" "${th}" --refresh "${top_refresh}" --pos-x 0 --pos-y 0 --transform normal || rc=$?
    cosmic-randr mode "${BOTTOM_OUTPUT}" "${bw}" "${bh}" --refresh "${bottom_refresh}" --pos-x 0 --pos-y "${top_h}" --transform rotate180 || rc=$?

    flock -u "${lock_fd}"
    exec {lock_fd}>&-
    return ${rc}
}

function zenbook-rotate-displays() {
    local orientation="${1}"
    local lock_fd rc=0
    local transform tw th bw bh top_refresh bottom_refresh
    local top_x=0 top_y=0 bottom_x=0 bottom_y=0

    if ! exec {lock_fd}>"${DISPLAY_LOCK}"; then
        echo "$(date) - DISPLAY - ERROR: cannot open display lock" >&2
        return 1
    fi
    flock -x "${lock_fd}"

    transform=$(zenbook-cosmic-transform "${orientation}")
    tw=${TOP_MODE%x*}
    th=${TOP_MODE#*x}
    bw=${BOTTOM_MODE%x*}
    bh=${BOTTOM_MODE#*x}
    top_refresh=$(zenbook-cosmic-refresh-mHz "${TOP_RATE}")
    bottom_refresh=$(zenbook-cosmic-refresh-mHz "${BOTTOM_RATE}")

    case "${orientation}" in
        left-up) top_x=${bh}; top_y=0; bottom_x=0; bottom_y=0 ;;
        right-up) top_x=0; top_y=0; bottom_x=${th}; bottom_y=0 ;;
        bottom-up) top_x=0; top_y=${th}; bottom_x=0; bottom_y=0 ;;
        *) top_x=0; top_y=0; bottom_x=0; bottom_y=${th} ;;
    esac

    if [ "${KEYBOARD_ATTACHED}" = true ]; then
        cosmic-randr mode "${TOP_OUTPUT}" "${tw}" "${th}" --refresh "${top_refresh}" \
            --pos-x 0 --pos-y 0 --transform "${transform}" || rc=$?
        cosmic-randr disable "${BOTTOM_OUTPUT}" || rc=$?
    else
        cosmic-randr enable "${BOTTOM_OUTPUT}" >/dev/null 2>&1 || true
        cosmic-randr mode "${TOP_OUTPUT}" "${tw}" "${th}" --refresh "${top_refresh}" \
            --pos-x "${top_x}" --pos-y "${top_y}" --transform "${transform}" || rc=$?
        cosmic-randr mode "${BOTTOM_OUTPUT}" "${bw}" "${bh}" --refresh "${bottom_refresh}" \
            --pos-x "${bottom_x}" --pos-y "${bottom_y}" --transform "${transform}" || rc=$?
    fi

    flock -u "${lock_fd}"
    exec {lock_fd}>&-
    return ${rc}
}
