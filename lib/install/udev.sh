#!/bin/bash
# USB / hidraw uaccess rules for the detachable Zenbook Duo keyboard.

zenbook-configure-udev-keyboard() {
    local udev_rule="${1:-/etc/udev/rules.d/70-zenbook-keyboard.rules}"
    local product_name="${KEYBOARD_PRODUCT_NAME:-ASUS Zenbook Duo Keyboard}"
    local keyboard_usb_ids="${KEYBOARD_USB_IDS:-0b05:1bf2 0b05:1b2c}"
    local keyboard_bt_ids="${KEYBOARD_BT_IDS:-0b05:1bf3 0b05:1b2d}"
    local keyboard_usb_id keyboard_vendor="" keyboard_product=""
    local id vendor product
    local seen_ids=""

    keyboard_usb_id=$(lsusb | awk -v name="${product_name}" 'index($0, name) { print $6; exit }')
    if [[ -z "${keyboard_usb_id}" ]]; then
        keyboard_usb_id=$(lsusb | awk 'BEGIN{IGNORECASE=1} /Zenbook Duo Keyboard/ { print $6; exit }')
    fi
    if [[ "${keyboard_usb_id}" =~ ^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}$ ]]; then
        keyboard_vendor=${keyboard_usb_id%:*}
        keyboard_product=${keyboard_usb_id#*:}
    fi

    {
        echo '# ASUS Zenbook Duo detachable keyboard - allow the active local session access'
        # Exact product string used by UX8406CA Primax docks.
        printf 'SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{product}=="%s", TAG+="uaccess"\n' \
            "${product_name}"
        # Shorter legacy product string some images/docs still use.
        if [[ "${product_name}" != "Zenbook Duo Keyboard" ]]; then
            printf 'SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{product}=="Zenbook Duo Keyboard", TAG+="uaccess"\n'
        fi

        for id in ${keyboard_usb_ids} ${keyboard_bt_ids}; do
            [[ "${id}" =~ ^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}$ ]] || continue
            vendor=${id%:*}
            product=${id#*:}
            case " ${seen_ids} " in
                *" ${vendor,,}:${product,,} "*) continue ;;
            esac
            seen_ids+=" ${vendor,,}:${product,,}"
            printf 'SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="%s", ATTR{idProduct}=="%s", TAG+="uaccess"\n' \
                "${vendor,,}" "${product,,}"
            # hidraw is required for backlight when the keyboard is on Bluetooth.
            printf 'KERNEL=="hidraw*", ATTRS{idVendor}=="%s", ATTRS{idProduct}=="%s", TAG+="uaccess"\n' \
                "${vendor,,}" "${product,,}"
        done

        # Also tag whatever is currently plugged in if it was not already listed.
        if [[ -n "${keyboard_vendor}" && -n "${keyboard_product}" ]]; then
            case " ${seen_ids} " in
                *" ${keyboard_vendor,,}:${keyboard_product,,} "*) ;;
                *)
                    printf 'SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="%s", ATTR{idProduct}=="%s", TAG+="uaccess"\n' \
                        "${keyboard_vendor,,}" "${keyboard_product,,}"
                    printf 'KERNEL=="hidraw*", ATTRS{idVendor}=="%s", ATTRS{idProduct}=="%s", TAG+="uaccess"\n' \
                        "${keyboard_vendor,,}" "${keyboard_product,,}"
                    ;;
            esac
        fi
    } | sudo tee "${udev_rule}" >/dev/null

    sudo chmod 0644 "${udev_rule}"
    sudo udevadm control --reload-rules >/dev/null
    sudo udevadm trigger --subsystem-match=usb --action=add >/dev/null 2>&1 || true
    sudo udevadm trigger --subsystem-match=hidraw --action=add >/dev/null 2>&1 || true

    # Return whether the keyboard was visible during setup (0=yes, 1=no).
    [[ -n "${keyboard_vendor}" && -n "${keyboard_product}" ]]
}
