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

    if [[ "${need_change}" -eq 0 ]]; then
        MONITOR_COUNT=$(zenbook-monitor-count)
        zenbook-set-status
        echo "$(date) - MONITOR - USB event ignored (dock=${KEYBOARD_ATTACHED}, bottom_active=${bottom_active})"
        return 0
    fi

    MONITOR_COUNT=$(zenbook-monitor-count)
    echo "$(date) - MONITOR - WIFI before: ${WIFI_BEFORE}, Bluetooth before: ${BLUETOOTH_BEFORE}"
    echo "$(date) - MONITOR - Keyboard attached: ${KEYBOARD_ATTACHED}, active monitor count: ${MONITOR_COUNT}"

    if [ "${KEYBOARD_ATTACHED}" = true ]; then
        echo "$(date) - MONITOR - Keyboard attached"
        # Cancel any in-flight undock backlight retries before setting docked level.
        zenbook-cancel-detach-backlight
        zenbook-apply-docked-backlight "${DEFAULT_BACKLIGHT}" || true
        # USB is primary — drop any zombie BT link so the next undock can HOGP cleanly.
        zenbook-bt-release-while-docked || true

        if [ "${WIFI_BEFORE}" = enabled ]; then
            echo "$(date) - MONITOR - Turning on WIFI"
            nmcli radio wifi on 2>/dev/null || echo "$(date) - MONITOR - WARNING: nmcli wifi on failed" >&2
        elif [ "${WIFI_BEFORE}" = disabled ]; then
            echo "$(date) - MONITOR - Turning off WIFI"
            nmcli radio wifi off 2>/dev/null || echo "$(date) - MONITOR - WARNING: nmcli wifi off failed" >&2
        fi
        if [ "${BLUETOOTH_BEFORE}" = unblocked ]; then
            echo "$(date) - MONITOR - Turning on Bluetooth"
            rfkill unblock bluetooth 2>/dev/null || echo "$(date) - MONITOR - WARNING: rfkill unblock failed" >&2
        elif [ "${BLUETOOTH_BEFORE}" = blocked ]; then
            echo "$(date) - MONITOR - Turning off Bluetooth"
            rfkill block bluetooth 2>/dev/null || echo "$(date) - MONITOR - WARNING: rfkill block failed" >&2
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
        # Unblock Bluetooth; helper may host-connect once (never disconnect/GATT).
        if [ "${WIFI_BEFORE}" = enabled ]; then
            echo "$(date) - MONITOR - Turning on WIFI"
            nmcli radio wifi on 2>/dev/null || echo "$(date) - MONITOR - WARNING: nmcli wifi on failed" >&2
        fi
        echo "$(date) - MONITOR - Turning on Bluetooth"
        rfkill unblock bluetooth 2>/dev/null || echo "$(date) - MONITOR - WARNING: rfkill unblock failed" >&2

        # Connect-once + wait for HOGP; set hidraw backlight when ready.
        zenbook-start-detach-backlight

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

    # Commit dock + layout state only after panel actions complete.
    MONITOR_COUNT=$(zenbook-monitor-count)
    zenbook-set-status
}

function zenbook-watch-monitor() {
    local last_apply_ms=0 now_ms line discard need_recheck=0 read_rc
    echo "$(date) - MONITOR - Watching for USB events"
    while true; do
        if ! command -v inotifywait >/dev/null 2>&1; then
            echo "$(date) - MONITOR - inotifywait not found; polling USB state every 2s" >&2
            sleep 2
            zenbook-check-monitor
            continue
        fi

        need_recheck=0
        while true; do
            if [[ "${need_recheck}" -eq 1 ]]; then
                # Trailing-edge: after cool-down, re-check even if no new USB event.
                line=""
                read -r -t 0.4 line
                read_rc=$?
                if (( read_rc > 128 )); then
                    : # timeout — apply pending recheck below
                elif (( read_rc != 0 )); then
                    break # EOF from inotifywait
                fi
            else
                if ! read -r line; then
                    break
                fi
            fi

            if [[ -n "${line}" ]]; then
                # Debounce bursty USB uevents (composite HID + pogo pin chatter).
                sleep 0.5
                while read -r -t 0.1 discard; do :; done
                need_recheck=1
            elif [[ "${need_recheck}" -ne 1 ]]; then
                continue
            fi

            now_ms=$(date +%s%3N 2>/dev/null || date +%s)
            if [[ "${now_ms}" =~ ^[0-9]+$ && "${last_apply_ms}" =~ ^[0-9]+$ ]]; then
                if (( now_ms - last_apply_ms < 1000 )); then
                    need_recheck=1
                    continue
                fi
            fi
            need_recheck=0
            last_apply_ms=${now_ms}
            zenbook-check-monitor
        done < <(inotifywait -m -q -r -e attrib,create,delete /dev/bus/usb 2>/dev/null)

        echo "$(date) - MONITOR - inotifywait exited; restarting in 1s" >&2
        sleep 1
    done
}
