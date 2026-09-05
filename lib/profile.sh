#!/bin/bash
# Desktop × session profile dispatch.
# Each profile selects environment-specific command preferences on top of the
# display backend (x11 / gnome / kde / wlr / hyprland / cosmic).

function zenbook-resolve-profile-id() {
    local de="${ZENBOOK_DE:-unknown}"
    local session="${ZENBOOK_SESSION:-unknown}"

    # Group wlroots family under one Wayland profile.
    case "${de}" in
        sway|wayfire|river|labwc|niri)
            printf 'wlr-%s\n' "${session}"
            return 0
            ;;
        i3|openbox|awesome|qtile|bspwm|herbstluftwm|xmonad)
            printf 'x11wm-%s\n' "${session}"
            return 0
            ;;
    esac

    printf '%s-%s\n' "${de}" "${session}"
}

function zenbook-profile-reset-defaults() {
    ZENBOOK_PROFILE_LABEL="${ZENBOOK_DE:-unknown} / ${ZENBOOK_SESSION:-unknown}"
    ZENBOOK_PROFILE_SOFTKBD=(onboard squeekboard maliit-keyboard florence kvkbd)
    ZENBOOK_PROFILE_TOUCH=none
    ZENBOOK_PROFILE_MIRROR=none
    ZENBOOK_PROFILE_WINDOWS=none
    ZENBOOK_PROFILE_DISPLAY_TOOL="$(zenbook-backend-tool-name "${ZENBOOK_BACKEND:-}")"
}

function zenbook-profile-source-file() {
    local name="${1}"
    local path="${ZENBOOK_LIB_DIR}/profile/${name}.sh"
    if [[ -f "${path}" ]]; then
        # shellcheck source=/dev/null
        . "${path}"
        return 0
    fi
    return 1
}

function zenbook-load-profile() {
    local id fallback session_fallback family_fallback

    if [[ -n "${ZENBOOK_PROFILE_OVERRIDE:-}" ]]; then
        ZENBOOK_PROFILE=${ZENBOOK_PROFILE_OVERRIDE}
    else
        ZENBOOK_PROFILE=$(zenbook-resolve-profile-id)
    fi

    zenbook-profile-reset-defaults

    session_fallback="${ZENBOOK_SESSION:-unknown}"
    case "${ZENBOOK_BACKEND:-}" in
        x11) family_fallback=x11-family ;;
        gnome) family_fallback=gnome-family ;;
        kde) family_fallback=kde-family ;;
        wlr) family_fallback=wlr-family ;;
        hyprland) family_fallback=hyprland-family ;;
        cosmic) family_fallback=cosmic-family ;;
        *) family_fallback=_default ;;
    esac

    # Exact profile → backend family → session → global default.
    if zenbook-profile-source-file "${ZENBOOK_PROFILE}"; then
        :
    elif zenbook-profile-source-file "${family_fallback}"; then
        :
    elif zenbook-profile-source-file "${session_fallback}"; then
        :
    else
        zenbook-profile-source-file "_default" || true
    fi

    export ZENBOOK_PROFILE
    export ZENBOOK_PROFILE_LABEL
    export ZENBOOK_PROFILE_TOUCH
    export ZENBOOK_PROFILE_MIRROR
    export ZENBOOK_PROFILE_WINDOWS
    export ZENBOOK_PROFILE_DISPLAY_TOOL
}

function zenbook-profile-softkbd-candidates() {
    local app
    if ((${#ZENBOOK_PROFILE_SOFTKBD[@]})); then
        printf '%s\n' "${ZENBOOK_PROFILE_SOFTKBD[@]}"
        return 0
    fi
    printf '%s\n' onboard squeekboard maliit-keyboard florence kvkbd
}

function zenbook-print-profile() {
    printf 'Profile:        %s\n' "${ZENBOOK_PROFILE:-unknown}"
    printf 'Profile label:  %s\n' "${ZENBOOK_PROFILE_LABEL:-unknown}"
    printf 'Desktop:        %s\n' "${ZENBOOK_DE:-unknown}"
    printf 'Session:        %s\n' "${ZENBOOK_SESSION:-unknown}"
    printf 'Compositor:     %s\n' "${ZENBOOK_COMPOSITOR:-unknown}"
    printf 'Backend:        %s\n' "${ZENBOOK_BACKEND:-unknown}"
    printf 'Display tool:   %s\n' "${ZENBOOK_PROFILE_DISPLAY_TOOL:-$(zenbook-backend-tool)}"
    printf 'Touch map:      %s\n' "${ZENBOOK_PROFILE_TOUCH:-none}"
    printf 'Window move:    %s\n' "${ZENBOOK_PROFILE_WINDOWS:-none}"
    printf 'Mirror/share:   %s\n' "${ZENBOOK_PROFILE_MIRROR:-none}"
    printf 'Softkbd prefs:  %s\n' "${ZENBOOK_PROFILE_SOFTKBD[*]:-}"
}
