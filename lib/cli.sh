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
        zenbook-set-kb-backlight 0
    ;;
    post|thaw|boot)
        echo "$(date) - ACPI - $*"
        zenbook-set-kb-backlight "${DEFAULT_BACKLIGHT}"
        zenbook-check-monitor 1
        zenbook-map-touch-inputs || true
    ;;
    kbb)
        echo "$(date) - KEYBOARD - Backlight = ${2}"
        zenbook-set-kb-backlight "${2}"
    ;;
    softkbd|osk)
        zenbook-softkbd
    ;;
    touch|touchmap)
        zenbook-map-touch-inputs
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
