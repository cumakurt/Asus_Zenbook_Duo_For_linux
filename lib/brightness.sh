#!/bin/bash
# Panel brightness discovery and sync between top and bottom displays.

function zenbook-find-bottom-backlight() {
    local path
    for path in /sys/class/backlight/card*-eDP-2-backlight; do
        if [ -r "${path}/brightness" ]; then
            printf '%s\n' "${path}"
            return 0
        fi
    done
    if [ -r /sys/class/backlight/asus_screenpad/brightness ]; then
        printf '%s\n' /sys/class/backlight/asus_screenpad
        return 0
    fi
    return 1
}

function zenbook-write-backlight() {
    local path="${1}"
    local value="${2}"
    local device
    device=$(basename "${path}")

    if command -v brightnessctl >/dev/null 2>&1; then
        brightnessctl -q -d "${device}" set "${value}" >/dev/null 2>&1 && return 0
    fi
    if [ -w "${path}/brightness" ]; then
        printf '%s\n' "${value}" > "${path}/brightness" && return 0
    fi
    printf '%s\n' "${value}" | /usr/bin/sudo -n /usr/bin/tee "${path}/brightness" >/dev/null 2>&1
}

function zenbook-sync-display-backlight() {
    zenbook-load-status
    [ "${KEYBOARD_ATTACHED}" = false ] || return 0
    zenbook-output-active "${BOTTOM_OUTPUT}" || return 0
    [ -r "${TOP_BACKLIGHT}/brightness" ] || return 0

    # Re-resolve each sync: the sysfs node may appear only after enabling eDP-2.
    BOTTOM_BACKLIGHT=$(zenbook-find-bottom-backlight 2>/dev/null || true)
    [ -n "${BOTTOM_BACKLIGHT}" ] || return 0
    [ -r "${BOTTOM_BACKLIGHT}/brightness" ] || return 0

    local current top_max bottom_max target
    current=$(cat "${TOP_BACKLIGHT}/brightness" 2>/dev/null || echo "")
    top_max=$(cat "${TOP_BACKLIGHT}/max_brightness" 2>/dev/null || echo "")
    bottom_max=$(cat "${BOTTOM_BACKLIGHT}/max_brightness" 2>/dev/null || echo "")

    if [[ ! "${current}" =~ ^[0-9]+$ ]]; then
        return 0
    fi
    if [[ ! "${top_max}" =~ ^[0-9]+$ || ! "${bottom_max}" =~ ^[0-9]+$ ]]; then
        echo "$(date) - DISPLAY - WARNING: unreadable max_brightness; skipping sync" >&2
        return 0
    fi

    if (( top_max > 0 && bottom_max > 0 )); then
        target=$((current * bottom_max / top_max))
    else
        target=${current}
    fi

    if [ "${target}" != "${BRIGHTNESS}" ]; then
        BRIGHTNESS=${target}
        if zenbook-write-backlight "${BOTTOM_BACKLIGHT}" "${target}"; then
            echo "$(date) - DISPLAY - Synced ${BOTTOM_OUTPUT} brightness to ${target}"
        else
            echo "$(date) - DISPLAY - WARNING: could not set ${BOTTOM_OUTPUT} brightness to ${target}"
        fi
    fi
}

function zenbook-watch-display-backlight() {
    local top_name last_val="" cur_val
    local warned_missing=0

    # Stay alive even if sysfs appears late (resume / driver probe). Exiting would
    # take down the daemon under wait -n supervision.
    while [ ! -r "${TOP_BACKLIGHT}/brightness" ]; do
        if [[ "${warned_missing}" -eq 0 ]]; then
            echo "$(date) - DISPLAY - Top-panel brightness interface not found; waiting" >&2
            warned_missing=1
        fi
        sleep 5
    done
    if [[ "${warned_missing}" -eq 1 ]]; then
        echo "$(date) - DISPLAY - Top-panel brightness interface ready"
    fi

    top_name=$(basename "${TOP_BACKLIGHT}")

    if command -v udevadm >/dev/null 2>&1; then
        while true; do
            while read -r _; do
                zenbook-sync-display-backlight
            done < <(
                udevadm monitor --udev --subsystem-match=backlight 2>/dev/null |
                    grep --line-buffered "${top_name}"
            )
            echo "$(date) - DISPLAY - udevadm monitor exited; restarting in 1s" >&2
            sleep 1
        done
    else
        while true; do
            cur_val=$(cat "${TOP_BACKLIGHT}/brightness" 2>/dev/null || echo "")
            if [[ -n "${cur_val}" && "${cur_val}" != "${last_val}" ]]; then
                last_val="${cur_val}"
                zenbook-sync-display-backlight
            fi
            sleep 1
        done
    fi
}
