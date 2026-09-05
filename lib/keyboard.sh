#!/bin/bash
# Detachable keyboard detection and backlight control.

function zenbook-keyboard-usb-id() {
    local id
    # Prefer known VID:PID matches; fall back to product-string scan.
    for id in ${KEYBOARD_USB_IDS}; do
        if lsusb -d "${id}" >/dev/null 2>&1; then
            printf '%s\n' "${id}"
            return 0
        fi
    done
    lsusb | awk -v name="${KEYBOARD_PRODUCT_NAME}" '
        index($0, name) {
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
    # Substring match covers "ASUS Zenbook Duo Keyboard" and shorter variants.
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

function zenbook-keyboard-backlight-ids() {
    # USB dock IDs first, then Bluetooth product IDs for undocked mode.
    printf '%s %s\n' "${KEYBOARD_USB_IDS}" "${KEYBOARD_BT_IDS}"
}

function zenbook-set-kb-backlight() {
    local level="${1}"
    local backlight_bin usb_id vendor_id product_id
    local tried=0

    if ! backlight_bin=$(zenbook-kbd-backlight-bin); then
        echo "$(date) - KEYBOARD - WARNING: kbd-backlight helper not found" >&2
        return 1
    fi

    for usb_id in $(zenbook-keyboard-backlight-ids); do
        [[ "${usb_id}" =~ ^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}$ ]] || continue
        tried=1
        vendor_id=${usb_id%:*}
        product_id=${usb_id#*:}
        # udev uaccess grants the active session permission; no sudo needed.
        if "${backlight_bin}" "${level}" "0x${vendor_id}" "0x${product_id}" >/dev/null 2>&1; then
            return 0
        fi
    done

    # Last resort: whatever lsusb currently reports for the product string.
    usb_id=$(zenbook-keyboard-usb-id)
    if [[ -n "${usb_id}" ]]; then
        tried=1
        vendor_id=${usb_id%:*}
        product_id=${usb_id#*:}
        if "${backlight_bin}" "${level}" "0x${vendor_id}" "0x${product_id}" >/dev/null 2>&1; then
            return 0
        fi
    fi

    if [[ "${tried}" -eq 0 ]]; then
        return 0
    fi
    echo "$(date) - KEYBOARD - WARNING: failed to set backlight level ${level}" >&2
    return 1
}

# After undock, brighten keys so the keyboard is findable in the dark.
# USB may already be gone; BT hidraw often appears a moment later.
function zenbook-brighten-kb-for-detach() {
    local level="${DETACH_BACKLIGHT:-3}"
    local attempt

    if zenbook-set-kb-backlight "${level}"; then
        echo "$(date) - KEYBOARD - detach backlight=${level}"
        return 0
    fi

    for attempt in 1 2 3 4 5 6 7 8; do
        sleep 0.45
        if zenbook-set-kb-backlight "${level}"; then
            echo "$(date) - KEYBOARD - detach backlight=${level} (attempt ${attempt})"
            return 0
        fi
    done

    echo "$(date) - KEYBOARD - WARNING: detach backlight ${level} not applied" >&2
    return 1
}
