#!/bin/bash
# Shared configuration for the Zenbook Duo helper.

# Project metadata
ZENBOOK_PROJECT_NAME=${ZENBOOK_PROJECT_NAME:-"ASUS Zenbook Duo for Linux"}
ZENBOOK_AUTHOR_NAME=${ZENBOOK_AUTHOR_NAME:-"Cuma KURT"}
ZENBOOK_AUTHOR_LINKEDIN=${ZENBOOK_AUTHOR_LINKEDIN:-"https://www.linkedin.com/in/cuma-kurt-34414917/"}
ZENBOOK_AUTHOR_GITHUB=${ZENBOOK_AUTHOR_GITHUB:-"https://github.com/cumakurt/Asus_Zenbook_Duo_For_linux"}
ZENBOOK_LICENSE=${ZENBOOK_LICENSE:-"GPL-3.0-or-later"}

# Default keyboard backlight while docked (0-3)
DEFAULT_BACKLIGHT=${DEFAULT_BACKLIGHT:-3}
# Max backlight after undock so the keyboard is visible in the dark (0-3).
DETACH_BACKLIGHT=${DETACH_BACKLIGHT:-3}

# Display configuration for ASUS Zenbook Duo UX8406CA
TOP_OUTPUT=${TOP_OUTPUT:-eDP-1}
BOTTOM_OUTPUT=${BOTTOM_OUTPUT:-eDP-2}
TOP_MODE=${TOP_MODE:-2880x1800}
BOTTOM_MODE=${BOTTOM_MODE:-2880x1800}
TOP_RATE=${TOP_RATE:-120}
BOTTOM_RATE=${BOTTOM_RATE:-60}

# Prefer per-user runtime dir when available (avoids /tmp symlink races).
if [[ -z "${RUNTIME_DIR:-}" ]]; then
    if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "${XDG_RUNTIME_DIR}" ]]; then
        RUNTIME_DIR="${XDG_RUNTIME_DIR}/zenbook"
    else
        RUNTIME_DIR=/tmp/zenbook
    fi
fi

DISPLAY_LOCK=${DISPLAY_LOCK:-${RUNTIME_DIR}/display.lock}
STATUS_LOCK=${STATUS_LOCK:-${RUNTIME_DIR}/status.lock}
BOTTOM_WINDOWS_STATE=${BOTTOM_WINDOWS_STATE:-${RUNTIME_DIR}/bottom-windows}
STATUS_FILE=${STATUS_FILE:-${RUNTIME_DIR}/status}
LOG_FILE=${LOG_FILE:-${RUNTIME_DIR}/zenbook.log}

# Auto-detect top backlight when possible; fall back to intel_backlight.
if [[ -z "${TOP_BACKLIGHT:-}" ]]; then
    TOP_BACKLIGHT=""
    for _zenbook_bl in /sys/class/backlight/*; do
        [[ -r "${_zenbook_bl}/brightness" ]] || continue
        case "$(basename "${_zenbook_bl}")" in
            *eDP-2*|*screenpad*) continue ;;
            *) TOP_BACKLIGHT=${_zenbook_bl}; break ;;
        esac
    done
    TOP_BACKLIGHT=${TOP_BACKLIGHT:-/sys/class/backlight/intel_backlight}
    unset _zenbook_bl
fi

BRIGHTNESS=${BRIGHTNESS:--1}

# USB product string (UX8406 reports "ASUS Zenbook Duo Keyboard").
KEYBOARD_PRODUCT_NAME=${KEYBOARD_PRODUCT_NAME:-ASUS Zenbook Duo Keyboard}
# Space-separated VID:PID list (current 1bf2; legacy Duo keyboards often 1b2c).
KEYBOARD_USB_IDS=${KEYBOARD_USB_IDS:-0b05:1bf2 0b05:1b2c}
# Bluetooth product IDs used when the keyboard is undocked.
KEYBOARD_BT_IDS=${KEYBOARD_BT_IDS:-0b05:1bf3 0b05:1b2d}

# Touchscreen / stylus name substrings for xinput map-to-output (UX8406CA).
# ELAN9008 is typically the top OLED; ELAN9009 the bottom OLED.
TOP_TOUCH_MATCH=${TOP_TOUCH_MATCH:-ELAN9008}
BOTTOM_TOUCH_MATCH=${BOTTOM_TOUCH_MATCH:-ELAN9009}
