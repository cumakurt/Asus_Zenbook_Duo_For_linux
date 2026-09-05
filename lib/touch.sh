#!/bin/bash
# Dual-panel touchscreen / stylus mapping (X11 via xinput map-to-output).

function zenbook-x11-list-pointer-names() {
    xinput list --name-only 2>/dev/null
}

function zenbook-x11-device-is-mappable() {
    local name="${1}"
    # Skip relative touchpads; map touchscreens + stylus/eraser only.
    [[ "${name}" == *"Touchpad"* ]] && return 1
    [[ "${name}" == *"ELAN"* ]] || [[ "${name}" == *"Touchscreen"* ]] || [[ "${name}" == *"Stylus"* ]] || [[ "${name}" == *"eraser"* ]]
}

function zenbook-x11-map-device-to-output() {
    local name="${1}"
    local output="${2}"

    if ! xrandr --query 2>/dev/null | awk -v o="${output}" '$1 == o && $2 == "connected" { found=1 } END { exit(found ? 0 : 1) }'; then
        return 1
    fi
    if xinput map-to-output "${name}" "${output}" >/dev/null 2>&1; then
        echo "$(date) - TOUCH - mapped '${name}' -> ${output}"
        return 0
    fi
    echo "$(date) - TOUCH - WARNING: failed to map '${name}' -> ${output}" >&2
    return 1
}

function zenbook-x11-map-touch-inputs() {
    local top_match="${TOP_TOUCH_MATCH:-ELAN9008}"
    local bottom_match="${BOTTOM_TOUCH_MATCH:-ELAN9009}"
    local name top_out bottom_out
    local mapped=0

    if ! command -v xinput >/dev/null 2>&1; then
        echo "$(date) - TOUCH - WARNING: xinput not installed; dual touch mapping skipped" >&2
        return 1
    fi

    top_out="${TOP_OUTPUT}"
    if zenbook-output-active "${BOTTOM_OUTPUT}"; then
        bottom_out="${BOTTOM_OUTPUT}"
    else
        # Bottom OLED off (keyboard docked): keep bottom digitizers on the top panel
        # so absolute coords are not stretched across a dead region.
        bottom_out="${TOP_OUTPUT}"
    fi

    while IFS= read -r name; do
        [[ -n "${name}" ]] || continue
        zenbook-x11-device-is-mappable "${name}" || continue

        if [[ "${name}" == *"${top_match}"* ]]; then
            zenbook-x11-map-device-to-output "${name}" "${top_out}" && mapped=$((mapped + 1))
        elif [[ "${name}" == *"${bottom_match}"* ]]; then
            zenbook-x11-map-device-to-output "${name}" "${bottom_out}" && mapped=$((mapped + 1))
        fi
    done < <(zenbook-x11-list-pointer-names)

    if (( mapped == 0 )); then
        echo "$(date) - TOUCH - WARNING: no ELAN touch/stylus devices matched (${top_match}/${bottom_match})" >&2
        return 1
    fi
    echo "$(date) - TOUCH - mapped ${mapped} device(s) (top=${top_out}, bottom=${bottom_out})"
    return 0
}

# Backend entry point: only map when the active profile supports X11 touch.
function zenbook-map-touch-inputs() {
    # After undock, heal Duo BT clickpad before remapping panel digitizers.
    if declare -F zenbook-heal-keyboard-inputs >/dev/null 2>&1; then
        zenbook-heal-keyboard-inputs || true
    fi

    case "${ZENBOOK_PROFILE_TOUCH:-${ZENBOOK_BACKEND:-}}" in
        x11)
            zenbook-x11-map-touch-inputs
            ;;
        *)
            return 0
            ;;
    esac
}
