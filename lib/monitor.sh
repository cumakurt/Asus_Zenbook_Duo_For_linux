#!/bin/bash
# Keyboard attach/detach monitor and dual-display orchestration.

# Stable id so dock events replace one bubble instead of stacking.
ZENBOOK_NOTIFY_ID=${ZENBOOK_NOTIFY_ID:-8406}
ZENBOOK_NOTIFY_MS=${ZENBOOK_NOTIFY_MS:-900}

function zenbook-notify() {
    local body="${1}"
    notify-send \
        -r "${ZENBOOK_NOTIFY_ID}" \
        -t "${ZENBOOK_NOTIFY_MS}" \
        --hint=int:transient:1 \
        -i "input-keyboard" \
        "${body}" 2>/dev/null || true
}

# Apply dock/undock side effects. Set force=1 to always run (startup / CLI).
# Otherwise skip when dock state and bottom-panel active state already match.
function zenbook-check-monitor() {
    local force="${1:-0}"
    local prev_attached bottom_active need_change=0

    zenbook-load-status
    prev_attached="${KEYBOARD_ATTACHED:-}"

    KEYBOARD_ATTACHED=false
    if zenbook-keyboard-attached; then
        KEYBOARD_ATTACHED=true
    fi

    if zenbook-output-active "${BOTTOM_OUTPUT}"; then
        bottom_active=1
    else
        bottom_active=0
    fi

    if [[ "${force}" == "1" ]]; then
        need_change=1
    elif [[ "${KEYBOARD_ATTACHED}" != "${prev_attached}" ]]; then
        need_change=1
    elif [[ "${KEYBOARD_ATTACHED}" == true && "${bottom_active}" -eq 1 ]]; then
        need_change=1
    elif [[ "${KEYBOARD_ATTACHED}" != true && "${bottom_active}" -eq 0 ]]; then
        need_change=1
    fi

    MONITOR_COUNT=$(zenbook-monitor-count)
    zenbook-set-status

    if [[ "${need_change}" -eq 0 ]]; then
        echo "$(date) - MONITOR - USB event ignored (dock=${KEYBOARD_ATTACHED}, bottom_active=${bottom_active})"
        return 0
    fi

    echo "$(date) - MONITOR - WIFI before: ${WIFI_BEFORE}, Bluetooth before: ${BLUETOOTH_BEFORE}"
    echo "$(date) - MONITOR - Keyboard attached: ${KEYBOARD_ATTACHED}, active monitor count: ${MONITOR_COUNT}"

    if [ "${KEYBOARD_ATTACHED}" = true ]; then
        echo "$(date) - MONITOR - Keyboard attached"
        zenbook-set-kb-backlight "${DEFAULT_BACKLIGHT}"

        if [ "${WIFI_BEFORE}" = enabled ]; then
            echo "$(date) - MONITOR - Turning on WIFI"
            nmcli radio wifi on
        fi
        if [ "${BLUETOOTH_BEFORE}" = unblocked ]; then
            echo "$(date) - MONITOR - Turning on Bluetooth"
            rfkill unblock bluetooth
        else
            echo "$(date) - MONITOR - Turning off Bluetooth"
            rfkill block bluetooth
        fi

        if zenbook-output-active "${BOTTOM_OUTPUT}"; then
            echo "$(date) - MONITOR - Disabling bottom monitor (backend=${ZENBOOK_BACKEND})"
            if zenbook-disable-bottom-monitor && ! zenbook-output-active "${BOTTOM_OUTPUT}"; then
                zenbook-notify "Keyboard on · Screen 2 off"
            else
                zenbook-notify "Keyboard on · Screen 2 error"
            fi
        else
            zenbook-notify "Keyboard on · Screen 2 off"
        fi
    else
        echo "$(date) - MONITOR - Keyboard detached"
        # Brighten undocked keys for dark-room pickup (USB race + BT hidraw retries).
        zenbook-brighten-kb-for-detach &

        if [ "${WIFI_BEFORE}" = enabled ]; then
            echo "$(date) - MONITOR - Turning on WIFI"
            nmcli radio wifi on
        fi
        echo "$(date) - MONITOR - Turning on Bluetooth"
        rfkill unblock bluetooth

        if ! zenbook-output-active "${BOTTOM_OUTPUT}"; then
            echo "$(date) - MONITOR - Enabling bottom monitor (backend=${ZENBOOK_BACKEND})"
            if zenbook-enable-bottom-monitor && zenbook-output-active "${BOTTOM_OUTPUT}"; then
                zenbook-notify "Keyboard off · Screen 2 on"
            else
                zenbook-notify "Keyboard off · Screen 2 error"
            fi
        else
            zenbook-notify "Keyboard off · Screen 2 on"
        fi
    fi

    MONITOR_COUNT=$(zenbook-monitor-count)
    zenbook-set-status
}

function zenbook-watch-monitor() {
    while true; do
        echo "$(date) - MONITOR - Waiting for USB event"
        # Recursive: device nodes live under /dev/bus/usb/<bus>/, not the top dir.
        if ! inotifywait -qq -r -e attrib,create,delete /dev/bus/usb 2>/dev/null; then
            sleep 1
            continue
        fi
        # Debounce bursty USB uevents (composite HID + pogo pin chatter).
        sleep 0.5
        zenbook-check-monitor
    done
}
