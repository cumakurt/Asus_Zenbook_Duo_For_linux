#!/bin/bash
# Network watchers (Wi-Fi / Bluetooth preference while keyboard is attached).

function zenbook-watch-wifi() {
    local last_state="" new_state
    while true; do
        if ! command -v gdbus >/dev/null 2>&1; then
            sleep 5
            continue
        fi
        while read -r LINE; do
            if [[ "${LINE}" == *"<true>"* ]]; then
                new_state="enabled"
            elif [[ "${LINE}" == *"<false>"* ]]; then
                new_state="disabled"
            else
                continue
            fi

            if [[ "${new_state}" != "${last_state}" ]]; then
                last_state="${new_state}"
                zenbook-load-status
                if [ "${KEYBOARD_ATTACHED}" = true ]; then
                    WIFI_BEFORE="${new_state}"
                    echo "$(date) - NETWORK - WIFI: ${WIFI_BEFORE}"
                    zenbook-set-status
                fi
            fi
        done < <(gdbus monitor -y -d org.freedesktop.NetworkManager 2>/dev/null | grep --line-buffered WirelessEnabled)
        echo "$(date) - NETWORK - Wi-Fi monitor exited; restarting" >&2
        sleep 1
    done
}

function zenbook-watch-bluetooth() {
    local last_state="" new_state
    while true; do
        if ! command -v gdbus >/dev/null 2>&1; then
            sleep 5
            continue
        fi
        while read -r LINE; do
            if [[ "${LINE}" == *"<true>"* ]]; then
                new_state="unblocked"
            elif [[ "${LINE}" == *"<false>"* ]]; then
                new_state="blocked"
            else
                continue
            fi

            if [[ "${new_state}" != "${last_state}" ]]; then
                last_state="${new_state}"
                zenbook-load-status
                if [ "${KEYBOARD_ATTACHED}" = true ]; then
                    BLUETOOTH_BEFORE="${new_state}"
                    echo "$(date) - NETWORK - Bluetooth: ${BLUETOOTH_BEFORE}"
                    zenbook-set-status
                fi
            fi
        done < <(gdbus monitor -y -d org.bluez 2>/dev/null | grep --line-buffered "'Powered':")
        echo "$(date) - NETWORK - Bluetooth monitor exited; restarting" >&2
        sleep 1
    done
}
