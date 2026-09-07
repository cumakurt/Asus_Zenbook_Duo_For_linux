#!/bin/bash
# CLI dispatcher for Duo workflow, ACPI, keyboard backlight, and rotation.

function zenbook-cli() {
    zenbook-load-status
    case "${1}" in
    help|-h|--help)
        zenbook-print-help
    ;;
    status)
        zenbook-print-status
    ;;
    detect|env|profile)
        zenbook-print-detection
        printf '\n'
        zenbook-print-profile
    ;;
    about|version|--version|-V)
        zenbook-print-about
    ;;
    pre|hibernate|shutdown)
        echo "$(date) - ACPI - $*"
        if zenbook-keyboard-attached; then
            zenbook-set-kb-backlight 0 "usb" || true
        else
            zenbook-set-kb-backlight 0 "bt" || true
        fi
    ;;
    post|thaw|boot)
        echo "$(date) - ACPI - $*"
        if zenbook-keyboard-attached; then
            zenbook-apply-docked-backlight "${DEFAULT_BACKLIGHT}" || true
        else
            zenbook-set-kb-backlight "${DETACH_BACKLIGHT}" "bt" || true
        fi
        zenbook-check-monitor 1
        zenbook-map-touch-inputs || true
    ;;
    kbb)
        if [[ ! "${2:-}" =~ ^[0-3]$ ]]; then
            echo "$(date) - KEYBOARD - ERROR: kbb requires level 0-3" >&2
            return 1
        fi
        echo "$(date) - KEYBOARD - Backlight = ${2}"
        if zenbook-keyboard-attached; then
            zenbook-set-kb-backlight "${2}" "usb"
        else
            zenbook-set-kb-backlight "${2}" "bt"
        fi
    ;;
    softkbd|osk)
        zenbook-softkbd
    ;;
    touch|touchmap)
        zenbook-map-touch-inputs
    ;;
    keyboard-heal|kbd-heal|heal-kbd)
        zenbook-heal-keyboard-inputs
    ;;
    bt-connect|keyboard-bt)
        # Safe host connect for paired Duo keyboard (never disconnects).
        local mac
        if zenbook-keyboard-attached; then
            echo "$(date) - KEYBOARD - USB docked; skip BT connect"
            return 0
        fi
        mac=$(zenbook-keyboard-bt-mac 2>/dev/null || true)
        if [[ -z "${mac}" ]]; then
            echo "$(date) - KEYBOARD - ERROR: Duo BT MAC not found" >&2
            return 1
        fi
        zenbook-bt-connect-once "${mac}" || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            zenbook-bt-hid-ready && break
            sleep 0.5
        done
        zenbook-heal-keyboard-inputs
    ;;
    bottom)
        zenbook-set-bottom "${2:-toggle}"
    ;;
    share)
        zenbook-share-mode "${2:-extend}"
    ;;
    rotate-lock|rotation-lock)
        zenbook-set-rotate-lock "${2:-toggle}"
    ;;
    left-up|right-up|bottom-up|normal)
        zenbook-load-status
        if [[ "${ROTATE_LOCK}" == true && -z "${ZENBOOK_FORCE_ROTATE:-}" ]]; then
            echo "$(date) - ROTATE - blocked by rotate-lock (use: zenbook rotate-lock off)"
            return 0
        fi
        echo "$(date) - ROTATE - ${1}"
        if zenbook-keyboard-attached; then
            KEYBOARD_ATTACHED=true
        else
            KEYBOARD_ATTACHED=false
        fi
        zenbook-rotate-displays "${1}"
        MONITOR_COUNT=$(zenbook-monitor-count)
        zenbook-set-status
        zenbook-map-touch-inputs || true
        ;;
    *)
        echo "$(date) - UNKNOWN - $*"
        echo "Try: zenbook help" >&2
        return 1
        ;;
    esac
}
