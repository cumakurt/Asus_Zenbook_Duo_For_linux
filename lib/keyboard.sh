#!/bin/bash
# Detachable keyboard detection and backlight control.
#
# Evidence (2026-09-05):
# - GATT/disconnect loops + corrupt BlueZ attributes (second HID EndGroupHandle=65535)
#   produced Connected-without-HID (no uhid).
# - "Already Connected" must NOT skip work — only real HOGP (uhid / non-Primax xinput) counts.
# - Recovery: at most one disconnect+connect per undock. Never GATT. Never reconnect loops.

function zenbook-keyboard-usb-id() {
    local id
    for id in ${KEYBOARD_USB_IDS}; do
        if lsusb -d "${id}" >/dev/null 2>&1; then
            printf '%s\n' "${id}"
            return 0
        fi
    done
    lsusb | awk -v name="${KEYBOARD_PRODUCT_NAME}" '
        BEGIN { IGNORECASE = 1 }
        index(tolower($0), tolower(name)) {
            print $6
            exit
        }
    '
}

function zenbook-keyboard-attached() {
    local id
    for id in ${KEYBOARD_USB_IDS}; do
        if lsusb -d "${id}" >/dev/null 2>&1; then
            return 0
        fi
    done
    lsusb 2>/dev/null | grep -qiF "${KEYBOARD_PRODUCT_NAME}" && return 0
    lsusb 2>/dev/null | grep -qi 'Zenbook Duo Keyboard'
}

function zenbook-kbd-backlight-bin() {
    local candidate
    for candidate in \
        "${ZENBOOK_LIB_DIR}/kbd-backlight" \
        "${ZENBOOK_LIB_DIR}/../kbd-backlight"
    do
        if [[ -x "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

function zenbook-set-kb-backlight-hid() {
    local level="${1}"
    local usb_id="${2}"
    local backlight_bin vendor_id product_id out rc

    [[ "${usb_id}" =~ ^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}$ ]] || return 1
    backlight_bin=$(zenbook-kbd-backlight-bin) || return 1
    vendor_id=${usb_id%:*}
    product_id=${usb_id#*:}
    # hidraw FEATURE only — never GATT / never BT reconnect for backlight.
    out=$("${backlight_bin}" "${level}" "0x${vendor_id}" "0x${product_id}" 2>&1)
    rc=$?
    if [[ "${rc}" -eq 0 ]]; then
        echo "$(date) - KEYBOARD - ${out}"
        return 0
    fi
    return 1
}

function zenbook-set-kb-backlight() {
    local level="${1}"
    local mode="${2:-auto}"
    local usb_id ids tried=0

    if [[ ! "${level}" =~ ^[0-3]$ ]]; then
        echo "$(date) - KEYBOARD - WARNING: invalid backlight level '${level}'" >&2
        return 1
    fi

    if [[ "${mode}" == "usb" ]] || { [[ "${mode}" == "auto" ]] && zenbook-keyboard-attached; }; then
        ids=${KEYBOARD_USB_IDS}
    elif [[ "${mode}" == "bt" ]] || [[ "${mode}" == "auto" ]]; then
        ids=${KEYBOARD_BT_IDS}
    else
        ids="${KEYBOARD_USB_IDS} ${KEYBOARD_BT_IDS}"
    fi

    for usb_id in ${ids}; do
        tried=1
        if zenbook-set-kb-backlight-hid "${level}" "${usb_id}"; then
            return 0
        fi
    done

    if [[ "${mode}" == "usb" || "${mode}" == "auto" ]]; then
        usb_id=$(zenbook-keyboard-usb-id)
        if [[ -n "${usb_id}" ]]; then
            tried=1
            zenbook-set-kb-backlight-hid "${level}" "${usb_id}" && return 0
        fi
    fi

    [[ "${tried}" -eq 0 ]] && return 0
    echo "$(date) - KEYBOARD - WARNING: failed to set backlight level ${level}" >&2
    return 1
}

# Docked USB: hidraw/usbdevfs may not be ready on the first attach uevent.
function zenbook-apply-docked-backlight() {
    local level="${1:-${DEFAULT_BACKLIGHT:-3}}"
    local attempt

    if [[ ! "${level}" =~ ^[0-3]$ ]]; then
        echo "$(date) - KEYBOARD - WARNING: invalid docked backlight level '${level}'" >&2
        return 1
    fi

    for attempt in 1 2 3 4 5 6 7 8; do
        if ! zenbook-keyboard-attached; then
            echo "$(date) - KEYBOARD - docked backlight aborted (USB gone)"
            return 1
        fi
        if zenbook-set-kb-backlight "${level}" "usb"; then
            echo "$(date) - KEYBOARD - docked backlight=${level} (attempt ${attempt})"
            return 0
        fi
        sleep 0.35
    done
    echo "$(date) - KEYBOARD - WARNING: docked backlight FEATURE not applied" >&2
    return 1
}

function zenbook-cancel-detach-backlight() {
    local pid
    [[ -f "${DETACH_BACKLIGHT_PID_FILE}" ]] || return 0
    pid=$(cat "${DETACH_BACKLIGHT_PID_FILE}" 2>/dev/null || true)
    if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
        kill "${pid}" 2>/dev/null || true
        wait "${pid}" 2>/dev/null || true
    fi
    rm -f "${DETACH_BACKLIGHT_PID_FILE}"
}

function zenbook-keyboard-bt-mac() {
    local mac
    if [[ -n "${KEYBOARD_BT_MAC:-}" ]]; then
        printf '%s\n' "${KEYBOARD_BT_MAC}"
        return 0
    fi
    command -v bluetoothctl >/dev/null 2>&1 || return 1
    mac=$(
        bluetoothctl devices 2>/dev/null |
            awk 'BEGIN{IGNORECASE=1} /zenbook duo keyboard/ {print $2; exit}'
    )
    [[ -n "${mac}" ]] || return 1
    printf '%s\n' "${mac}"
}

function zenbook-bt-device-connected() {
    local mac="${1}"
    [[ -n "${mac}" ]] || return 1
    bluetoothctl info "${mac}" 2>/dev/null | grep -qiE '^[[:space:]]*Connected:[[:space:]]*yes'
}

function zenbook-bt-services-resolved() {
    local mac="${1}"
    [[ -n "${mac}" ]] || return 1
    bluetoothctl info "${mac}" 2>/dev/null | grep -qiE '^[[:space:]]*ServicesResolved:[[:space:]]*yes'
}

function zenbook-bt-hid-sysfs-present() {
    local id product
    for id in ${KEYBOARD_BT_IDS}; do
        [[ "${id}" =~ ^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}$ ]] || continue
        product=${id#*:}
        product=${product^^}
        # Avoid zsh/bash nomatch issues: use find
        if find /sys/bus/hid/devices -maxdepth 1 -name "0005:0B05:${product}.*" 2>/dev/null | grep -q .; then
            return 0
        fi
    done
    return 1
}

function zenbook-bt-duo-inputs-present() {
    command -v xinput >/dev/null 2>&1 || return 1
    xinput list 2>/dev/null |
        grep -i 'Zenbook Duo Keyboard' |
        grep -vi 'Primax' >/dev/null
}

function zenbook-bt-hid-ready() {
    zenbook-bt-hid-sysfs-present || zenbook-bt-duo-inputs-present
}

function zenbook-heal-keyboard-inputs() {
    local line id name has_touchpad=0
    command -v xinput >/dev/null 2>&1 || return 0
    [[ "${ZENBOOK_SESSION:-}" == wayland ]] && return 0

    if xinput list 2>/dev/null | grep -i 'Zenbook Duo Keyboard Touchpad' | grep -vi 'Primax' >/dev/null; then
        has_touchpad=1
    fi

    while IFS= read -r line; do
        [[ "${line}" == *id=* ]] || continue
        id=$(sed -n 's/.*id=\([0-9]\+\).*/\1/p' <<<"${line}")
        [[ "${id}" =~ ^[0-9]+$ ]] || continue
        name=$(xinput list --name-only "${id}" 2>/dev/null | head -n1)
        while [[ -n "${name}" && "${name}" != [A-Za-z0-9]* ]]; do
            name="${name#?}"
        done
        [[ "${name}" == Primax* ]] && continue

        case "${name}" in
            *"Keyboard Mouse")
                if [[ "${has_touchpad}" -eq 1 && "${ZENBOOK_KEEP_DUO_MOUSE:-0}" != "1" ]]; then
                    xinput disable "${id}" >/dev/null 2>&1 || true
                    echo "$(date) - KEYBOARD - disabled conflicting Mouse id=${id}"
                else
                    xinput enable "${id}" >/dev/null 2>&1 || true
                fi
                ;;
            *)
                xinput enable "${id}" >/dev/null 2>&1 || true
                xinput set-prop "${id}" "Device Enabled" 1 >/dev/null 2>&1 || true
                xinput set-prop "${id}" "libinput Send Events Mode Enabled" 0 0 >/dev/null 2>&1 || true
                echo "$(date) - KEYBOARD - healed input id=${id} (${name})"
                ;;
        esac
    done < <(xinput list 2>/dev/null | grep -i 'Zenbook Duo Keyboard')
}

function zenbook-bt-disconnect-once() {
    local mac="${1}"
    local out
    [[ -n "${mac}" ]] || return 1
    if ! zenbook-bt-device-connected "${mac}"; then
        return 0
    fi
    echo "$(date) - KEYBOARD - BT disconnect once (${mac}) — clearing Connected-without-HID"
    # Outer timeout so a wedged bluetoothctl cannot stall undock forever.
    out=$(timeout 10 bluetoothctl --timeout 8 disconnect "${mac}" 2>&1) || true
    echo "$(date) - KEYBOARD - BT disconnect: $(tr '\n' ' ' <<<"${out}" | cut -c1-120)"
    sleep 1.5
}

function zenbook-bt-connect-once() {
    local mac="${1}"
    local out
    [[ -n "${mac}" ]] || return 1
    command -v bluetoothctl >/dev/null 2>&1 || return 1

    echo "$(date) - KEYBOARD - BT connect once (${mac})"
    out=$(timeout 22 bluetoothctl --timeout 20 connect "${mac}" 2>&1) || true
    if grep -qiE 'Connection successful|Already connected' <<<"${out}"; then
        echo "$(date) - KEYBOARD - BT connect ok"
        return 0
    fi
    echo "$(date) - KEYBOARD - BT connect result: $(tr '\n' ' ' <<<"${out}" | cut -c1-160)"
    zenbook-bt-device-connected "${mac}"
}

# Drop BT while USB is docked so the next undock starts from a clean link.
function zenbook-bt-release-while-docked() {
    local mac
    mac=$(zenbook-keyboard-bt-mac 2>/dev/null || true)
    [[ -n "${mac}" ]] || return 0
    if zenbook-bt-device-connected "${mac}"; then
        zenbook-bt-disconnect-once "${mac}" || true
    fi
}

function zenbook-finish-detach-hid() {
    local level="${1}"
    local attempt

    zenbook-heal-keyboard-inputs || true
    # hidraw ACL / iface settle briefly after HOGP; retry FEATURE only (no GATT).
    for attempt in 1 2 3 4 5 6 7 8; do
        if zenbook-set-kb-backlight "${level}" "bt"; then
            echo "$(date) - KEYBOARD - detach backlight=${level} (attempt ${attempt})"
            return 0
        fi
        sleep 0.35
    done
    echo "$(date) - KEYBOARD - BT HID ready; backlight FEATURE not applied" >&2
}

function zenbook-wait-bt-hid() {
    local mac="${1}"
    local seconds="${2:-15}"
    local i
    for ((i = 1; i <= seconds * 2; i++)); do
        if zenbook-keyboard-attached; then
            echo "$(date) - KEYBOARD - USB dock returned during BT wait"
            return 2
        fi
        if zenbook-bt-hid-ready; then
            return 0
        fi
        sleep 0.5
    done
    if zenbook-bt-device-connected "${mac}"; then
        if zenbook-bt-services-resolved "${mac}"; then
            echo "$(date) - KEYBOARD - Connected+ServicesResolved but no uhid yet"
        else
            echo "$(date) - KEYBOARD - Connected without ServicesResolved (HOGP not up)"
        fi
        return 1
    fi
    echo "$(date) - KEYBOARD - not Connected after wait"
    return 1
}

# Undock: wait briefly, connect, if Connected-without-HID do ONE disconnect+connect.
function zenbook-brighten-kb-for-detach() {
    local level="${DETACH_BACKLIGHT:-3}"
    local mac

    if zenbook-keyboard-attached; then
        return 0
    fi

    mac=$(zenbook-keyboard-bt-mac 2>/dev/null || true)
    echo "$(date) - KEYBOARD - undock: HOGP bring-up (${mac:-no-mac})"

    # Let keyboard BT radio wake after magnetic undock.
    sleep 2
    if zenbook-keyboard-attached; then
        return 0
    fi
    if zenbook-bt-hid-ready; then
        echo "$(date) - KEYBOARD - BT HID ready (auto)"
        zenbook-finish-detach-hid "${level}"
        return 0
    fi

    if [[ -z "${mac}" ]]; then
        echo "$(date) - KEYBOARD - WARNING: Duo BT MAC unknown" >&2
        return 0
    fi

    # Fresh connect. Do not bail out early on Connected — that was the 16:31 failure mode.
    if zenbook-bt-device-connected "${mac}" && ! zenbook-bt-hid-ready; then
        echo "$(date) - KEYBOARD - Connected-without-HID detected before connect"
        zenbook-bt-disconnect-once "${mac}" || true
    fi
    zenbook-bt-connect-once "${mac}" || true

    zenbook-wait-bt-hid "${mac}" 12
    local wait_rc=$?
    if [[ "${wait_rc}" -eq 0 ]]; then
        echo "$(date) - KEYBOARD - BT HID ready (after connect)"
        zenbook-finish-detach-hid "${level}"
        return 0
    elif [[ "${wait_rc}" -eq 2 ]]; then
        return 0
    fi

    # One recovery cycle only — not a loop.
    if ! zenbook-keyboard-attached && ! zenbook-bt-hid-ready; then
        echo "$(date) - KEYBOARD - HOGP recovery: one disconnect+connect"
        zenbook-bt-disconnect-once "${mac}" || true
        sleep 1
        zenbook-bt-connect-once "${mac}" || true
        zenbook-wait-bt-hid "${mac}" 20
        wait_rc=$?
        if [[ "${wait_rc}" -eq 0 ]]; then
            echo "$(date) - KEYBOARD - BT HID ready (after recovery)"
            zenbook-finish-detach-hid "${level}"
            return 0
        elif [[ "${wait_rc}" -eq 2 ]]; then
            return 0
        fi
    fi

    if zenbook-bt-hid-ready; then
        zenbook-finish-detach-hid "${level}"
        return 0
    fi

    echo "$(date) - KEYBOARD - WARNING: BT HID failed — toggle keyboard BT switch or re-pair (F10)" >&2
    return 0
}

function zenbook-start-detach-backlight() {
    local pid
    zenbook-cancel-detach-backlight
    (
        zenbook-brighten-kb-for-detach
        rm -f "${DETACH_BACKLIGHT_PID_FILE}"
    ) &
    pid=$!
    printf '%s\n' "${pid}" > "${DETACH_BACKLIGHT_PID_FILE}"
    if declare -p ZENBOOK_PIDS >/dev/null 2>&1; then
        ZENBOOK_PIDS+=("${pid}")
    fi
}
