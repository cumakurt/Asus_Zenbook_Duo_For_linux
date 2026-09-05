#!/bin/bash
# Network watchers (Wi-Fi / Bluetooth preference while keyboard is attached).

function zenbook-watch-wifi() {
    while true; do
        if ! command -v gdbus >/dev/null 2>&1; then
            sleep 5
            continue
        fi
        while read -r LINE; do
            sleep 1
            zenbook-load-status
            if [ "${KEYBOARD_ATTACHED}" = true ]; then
                if [[ "${LINE}" = *"<true>"* ]]; then
                    WIFI_BEFORE=enabled
                else
                    WIFI_BEFORE=disabled
                fi
                echo "$(date) - NETWORK - WIFI: ${WIFI_BEFORE}"
                zenbook-set-status
            fi
        done < <(gdbus monitor -y -d org.freedesktop.NetworkManager 2>/dev/null | grep --line-buffered WirelessEnabled)
        echo "$(date) - NETWORK - Wi-Fi monitor exited; restarting" >&2
        sleep 1
    done
}

function zenbook-watch-bluetooth() {
    while true; do
        if ! command -v gdbus >/dev/null 2>&1; then
            sleep 5
            continue
        fi
        while read -r LINE; do
            sleep 1
            zenbook-load-status
            if [ "${KEYBOARD_ATTACHED}" = true ]; then
                if [[ "${LINE}" = *"<true>"* ]]; then
                    BLUETOOTH_BEFORE=unblocked
                else
                    BLUETOOTH_BEFORE=blocked
                fi
                echo "$(date) - NETWORK - Bluetooth: ${BLUETOOTH_BEFORE}"
                zenbook-set-status
            fi
        done < <(gdbus monitor -y -d org.bluez 2>/dev/null | grep --line-buffered "'Powered':")
        echo "$(date) - NETWORK - Bluetooth monitor exited; restarting" >&2
        sleep 1
    done
}
