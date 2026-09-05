#!/bin/bash
# Duo-exclusive workflow helpers (ScreenXpert-like gaps that Linux can cover).

function zenbook-keyboard-bt-connected() {
    if command -v bluetoothctl >/dev/null 2>&1; then
        bluetoothctl devices Connected 2>/dev/null | grep -qi 'zenbook duo keyboard' && return 0
        bluetoothctl info 2>/dev/null | grep -qi 'zenbook duo keyboard' && return 0
    fi
    return 1
}

function zenbook-keyboard-bt-battery() {
    local bat
    if ! command -v bluetoothctl >/dev/null 2>&1; then
        return 1
    fi
    # Prefer a connected Duo keyboard device line, then Battery Percentage.
    bat=$(
        bluetoothctl devices Connected 2>/dev/null |
            awk 'BEGIN{IGNORECASE=1} /zenbook duo keyboard/ {print $2; exit}'
    )
    if [[ -z "${bat}" ]]; then
        return 1
    fi
    bluetoothctl info "${bat}" 2>/dev/null |
        awk -F'[:()]' 'BEGIN{IGNORECASE=1} /Battery Percentage/ {
            gsub(/[^0-9]/, "", $2)
            if ($2 != "") { print $2; exit }
        }'
}

function zenbook-print-status() {
    zenbook-load-status
    local top_conn="disconnected"
    local top_state="off"
    local bottom_conn="disconnected"
    local bottom_state="off"
    local kbd_usb="no"
    local kbd_bt="no"
    local kbd_bat="n/a"
    local bat

    if zenbook-keyboard-attached; then
        kbd_usb="yes"
    fi
    if zenbook-keyboard-bt-connected; then
        kbd_bt="yes"
        if bat=$(zenbook-keyboard-bt-battery); then
            kbd_bat="${bat}%"
        fi
    fi
    if declare -F zenbook-output-connected >/dev/null 2>&1 && zenbook-output-connected "${TOP_OUTPUT}"; then
        top_conn="connected"
    fi
    if zenbook-output-active "${TOP_OUTPUT}"; then
        top_state="on"
        # Active implies connected when the backend has no separate probe.
        [[ "${top_conn}" == disconnected ]] && top_conn="connected"
    fi
    if declare -F zenbook-output-connected >/dev/null 2>&1 && zenbook-output-connected "${BOTTOM_OUTPUT}"; then
        bottom_conn="connected"
    fi
    if zenbook-output-active "${BOTTOM_OUTPUT}"; then
        bottom_state="on"
        [[ "${bottom_conn}" == disconnected ]] && bottom_conn="connected"
    fi

    printf 'OS:              %s\n' "${ZENBOOK_OS_PRETTY:-${ZENBOOK_OS_ID:-unknown}}"
    printf 'Desktop:         %s / %s\n' "${ZENBOOK_DE:-unknown}" "${ZENBOOK_SESSION:-unknown}"
    printf 'Profile:         %s (%s)\n' "${ZENBOOK_PROFILE:-unknown}" "${ZENBOOK_PROFILE_LABEL:-unknown}"
    printf 'Compositor:      %s\n' "${ZENBOOK_COMPOSITOR:-unknown}"
    printf 'Backend:         %s (%s)\n' "${ZENBOOK_BACKEND:-unknown}" "${ZENBOOK_PROFILE_DISPLAY_TOOL:-$(zenbook-backend-tool)}"
    printf 'Capabilities:    touch=%s windows=%s mirror=%s\n' \
        "${ZENBOOK_PROFILE_TOUCH:-none}" \
        "${ZENBOOK_PROFILE_WINDOWS:-none}" \
        "${ZENBOOK_PROFILE_MIRROR:-none}"
    printf 'Top output:      %s (%s, %s)\n' "${TOP_OUTPUT}" "${top_conn}" "${top_state}"
    printf 'Bottom output:   %s (%s, %s)\n' "${BOTTOM_OUTPUT}" "${bottom_conn}" "${bottom_state}"
    printf 'Keyboard USB:    %s\n' "${kbd_usb}"
    printf 'Keyboard BT:     %s\n' "${kbd_bt}"
    printf 'Keyboard batt:   %s\n' "${kbd_bat}"
    printf 'Wi-Fi preference:%s\n' "${WIFI_BEFORE:-unknown}"
    printf 'BT preference:   %s\n' "${BLUETOOTH_BEFORE:-unknown}"
    printf 'Rotate lock:     %s\n' "${ROTATE_LOCK:-false}"
    printf 'Share mode:      %s\n' "${SHARE_MODE:-extend}"
    printf 'Runtime dir:     %s\n' "${RUNTIME_DIR}"
}

function zenbook-print-help() {
    cat <<EOF
Usage: zenbook [command]

Daemon:
  (no args)              Start dual-screen / keyboard watchers

Display:
  status                 Show Duo helper status
  detect                 Show DE / session / profile / backend matrix
  bottom on|off|toggle   Force second screen state
  share extend|duplicate|facing|reset
                         Sharing / dual-screen layouts
  normal|left-up|right-up|bottom-up
                         Rotate layout
  rotate-lock on|off|toggle
                         Ignore accelerometer rotations
  touch                  Remap dual OLED touch/stylus to eDP-1 / eDP-2 (X11)

Keyboard:
  kbb 0-3                Keyboard backlight level
  softkbd                Launch profile-preferred on-screen keyboard

ACPI aliases:
  pre|hibernate|shutdown Turn keyboard backlight off
  post|thaw|boot         Restore backlight and re-check monitors

about                    Show author, project links, and license
help                     Show this help
EOF
}

function zenbook-print-about() {
    cat <<EOF
${ZENBOOK_PROJECT_NAME}

Author:    ${ZENBOOK_AUTHOR_NAME}
LinkedIn:  ${ZENBOOK_AUTHOR_LINKEDIN}
GitHub:    ${ZENBOOK_AUTHOR_GITHUB}
License:   ${ZENBOOK_LICENSE}

Keyboard HID backlight protocol adapted from work by Alesya Huzik (BSD-2-Clause).
EOF
}

function zenbook-set-bottom() {
    local action="${1:-toggle}"
    zenbook-load-status

    case "${action}" in
        on|enable)
            if zenbook-keyboard-attached; then
                echo "$(date) - MONITOR - WARNING: physical keyboard is docked; bottom panel may stay covered"
            fi
            KEYBOARD_ATTACHED=false
            zenbook-enable-bottom-monitor
            ;;
        off|disable)
            zenbook-disable-bottom-monitor
            ;;
        toggle)
            if zenbook-output-active "${BOTTOM_OUTPUT}"; then
                zenbook-disable-bottom-monitor
            else
                KEYBOARD_ATTACHED=false
                zenbook-enable-bottom-monitor
            fi
            ;;
        *)
            echo "$(date) - UNKNOWN - bottom ${action}"
            return 1
            ;;
    esac
    MONITOR_COUNT=$(zenbook-monitor-count)
    zenbook-set-status
}

function zenbook-set-rotate-lock() {
    local action="${1:-toggle}"
    zenbook-load-status
    case "${action}" in
        on|enable|true) ROTATE_LOCK=true ;;
        off|disable|false) ROTATE_LOCK=false ;;
        toggle)
            if [[ "${ROTATE_LOCK}" == true ]]; then
                ROTATE_LOCK=false
            else
                ROTATE_LOCK=true
            fi
            ;;
        *)
            echo "$(date) - UNKNOWN - rotate-lock ${action}"
            return 1
            ;;
    esac
    echo "$(date) - ROTATE - lock=${ROTATE_LOCK}"
    zenbook-set-status
}

function zenbook-mirror-bottom() {
    # Backend may override; default uses enable-below then same-as where supported.
    if [[ "${ZENBOOK_PROFILE_MIRROR:-}" != x11 ]] && ! declare -F zenbook-mirror-displays >/dev/null 2>&1; then
        echo "$(date) - SHARE - WARNING: duplicate/mirror not supported on profile=${ZENBOOK_PROFILE:-unknown}; using stacked extend"
        KEYBOARD_ATTACHED=false
        zenbook-enable-bottom-monitor
        return $?
    fi
    if declare -F zenbook-mirror-displays >/dev/null 2>&1; then
        zenbook-mirror-displays
        return $?
    fi
    echo "$(date) - SHARE - WARNING: duplicate/mirror not supported on backend=${ZENBOOK_BACKEND}; using stacked extend"
    KEYBOARD_ATTACHED=false
    zenbook-enable-bottom-monitor
}

function zenbook-share-mode() {
    local mode="${1:-extend}"
    zenbook-load-status

    case "${mode}" in
        extend|reset)
            SHARE_MODE=extend
            KEYBOARD_ATTACHED=false
            if zenbook-keyboard-attached; then
                KEYBOARD_ATTACHED=true
                zenbook-check-monitor 1
            else
                zenbook-enable-bottom-monitor
                zenbook-rotate-displays normal
            fi
            ;;
        duplicate|mirror)
            SHARE_MODE=duplicate
            KEYBOARD_ATTACHED=false
            zenbook-mirror-bottom
            ;;
        facing|present)
            # Face-to-face: guest-oriented layout (ScreenXpert "sharing" style).
            SHARE_MODE=facing
            KEYBOARD_ATTACHED=false
            zenbook-enable-bottom-monitor || true
            zenbook-rotate-displays bottom-up
            ;;
        *)
            echo "$(date) - UNKNOWN - share ${mode}"
            return 1
            ;;
    esac
    MONITOR_COUNT=$(zenbook-monitor-count)
    zenbook-set-status
    echo "$(date) - SHARE - mode=${SHARE_MODE}"
}

function zenbook-softkbd() {
    local app
    local candidates=()

    mapfile -t candidates < <(zenbook-profile-softkbd-candidates 2>/dev/null || true)
    if ((${#candidates[@]} == 0)); then
        candidates=(onboard squeekboard maliit-keyboard florence kvkbd)
    fi

    for app in "${candidates[@]}"; do
        if command -v "${app}" >/dev/null 2>&1; then
            echo "$(date) - INPUT - launching ${app} (profile=${ZENBOOK_PROFILE:-unknown})"
            nohup "${app}" >/dev/null 2>&1 &
            disown || true
            notify-send -r "${ZENBOOK_NOTIFY_ID:-8406}" -t 900 --hint=int:transient:1 -i "input-keyboard" "Soft keyboard on" 2>/dev/null || true
            return 0
        fi
    done
    echo "$(date) - INPUT - ERROR: no soft keyboard for profile=${ZENBOOK_PROFILE:-unknown} (tried: ${candidates[*]})" >&2
    notify-send -r "${ZENBOOK_NOTIFY_ID:-8406}" -t 1200 --hint=int:transient:1 -i "dialog-warning" "Soft keyboard missing" 2>/dev/null || true
    return 1
}
