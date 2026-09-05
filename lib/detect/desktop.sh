#!/bin/bash
# Desktop environment, compositor, session type, and display-backend detection.
# Covers modern X11 and Wayland desktops via dedicated or auto-probed backends.

zenbook-detect-compositor() {
    local comp=unknown

    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        comp=hyprland
    elif [[ -n "${SWAYSOCK:-}" ]]; then
        comp=sway
    elif [[ -n "${WAYFIRE_SOCKET:-}" ]]; then
        comp=wayfire
    elif pgrep -u "${UID:-$(id -u)}" -x cosmic-comp >/dev/null 2>&1; then
        comp=cosmic
    elif pgrep -u "${UID:-$(id -u)}" -x labwc >/dev/null 2>&1; then
        comp=labwc
    elif pgrep -u "${UID:-$(id -u)}" -x river >/dev/null 2>&1; then
        comp=river
    elif pgrep -u "${UID:-$(id -u)}" -x niri >/dev/null 2>&1; then
        comp=niri
    elif pgrep -u "${UID:-$(id -u)}" -x gnome-shell >/dev/null 2>&1; then
        comp=mutter
    elif pgrep -u "${UID:-$(id -u)}" -x kwin_wayland >/dev/null 2>&1 || pgrep -u "${UID:-$(id -u)}" -x kwin_x11 >/dev/null 2>&1; then
        comp=kwin
    fi

    ZENBOOK_COMPOSITOR=${comp}
    export ZENBOOK_COMPOSITOR
}

zenbook-normalize-de-token() {
    local token="${1,,}"
    token=${token// /}
    case "${token}" in
        *hyprland*) printf 'hyprland\n' ;;
        *sway*) printf 'sway\n' ;;
        *wayfire*) printf 'wayfire\n' ;;
        *river*) printf 'river\n' ;;
        *niri*) printf 'niri\n' ;;
        *labwc*) printf 'labwc\n' ;;
        *cosmic*) printf 'cosmic\n' ;;
        *mate*) printf 'mate\n' ;;
        *gnome*) printf 'gnome\n' ;;
        *kde*|*plasma*) printf 'kde\n' ;;
        *xfce*) printf 'xfce\n' ;;
        *cinnamon*) printf 'cinnamon\n' ;;
        *lxqt*) printf 'lxqt\n' ;;
        *budgie*) printf 'budgie\n' ;;
        *lxde*) printf 'lxde\n' ;;
        *pantheon*|*elementary*) printf 'pantheon\n' ;;
        *deepin*|*dde*) printf 'deepin\n' ;;
        *ukui*) printf 'ukui\n' ;;
        *enlightenment*|*e17*|*e16*) printf 'enlightenment\n' ;;
        *trinity*|*tde*) printf 'trinity\n' ;;
        *i3*) printf 'i3\n' ;;
        *openbox*) printf 'openbox\n' ;;
        *awesome*) printf 'awesome\n' ;;
        *qtile*) printf 'qtile\n' ;;
        *bspwm*) printf 'bspwm\n' ;;
        *herbstluftwm*) printf 'herbstluftwm\n' ;;
        *xmonad*) printf 'xmonad\n' ;;
        *unity*) printf 'unity\n' ;;
        *) printf 'unknown\n' ;;
    esac
}

zenbook-backend-preferred-for-de() {
    local de="${1}"
    local session="${2}"
    local compositor="${3}"

    if [[ "${session}" == x11 ]]; then
        printf 'x11\n'
        return 0
    fi

    case "${compositor}" in
        hyprland) printf 'hyprland\n'; return 0 ;;
        sway|wayfire|river|labwc|niri) printf 'wlr\n'; return 0 ;;
        cosmic) printf 'cosmic\n'; return 0 ;;
        mutter) printf 'gnome\n'; return 0 ;;
        kwin)
            if [[ "${session}" == wayland ]]; then
                printf 'kde\n'
            else
                printf 'x11\n'
            fi
            return 0
            ;;
    esac

    case "${de}" in
        hyprland) printf 'hyprland\n' ;;
        sway|wayfire|river|niri|labwc) printf 'wlr\n' ;;
        cosmic) printf 'cosmic\n' ;;
        gnome|budgie|pantheon|unity) printf 'gnome\n' ;;
        kde) printf 'kde\n' ;;
        # Traditional DEs on Wayland often speak wlroots or fall back to probe.
        mate|xfce|cinnamon|lxqt|lxde|deepin|ukui|enlightenment|trinity|i3|openbox|awesome|qtile|bspwm|herbstluftwm|xmonad|unknown)
            if [[ "${session}" == wayland ]]; then
                printf 'wlr\n'
            else
                printf 'x11\n'
            fi
            ;;
        *)
            if [[ "${session}" == wayland ]]; then
                printf 'wlr\n'
            else
                printf 'x11\n'
            fi
            ;;
    esac
}

zenbook-backend-tool-name() {
    case "${1}" in
        x11) printf 'xrandr\n' ;;
        gnome) printf 'gdctl\n' ;;
        kde) printf 'kscreen-doctor\n' ;;
        wlr) printf 'wlr-randr\n' ;;
        hyprland) printf 'hyprctl\n' ;;
        cosmic) printf 'cosmic-randr\n' ;;
        *) printf '\n' ;;
    esac
}

zenbook-backend-tool-present() {
    local backend="${1}"
    local tool
    tool=$(zenbook-backend-tool-name "${backend}")
    [[ -n "${tool}" ]] && command -v "${tool}" >/dev/null 2>&1
}

zenbook-backend-available() {
    local backend="${1}"
    zenbook-backend-tool-present "${backend}" || return 1

    # Prefer a live probe so leftover binaries do not steal the backend.
    case "${backend}" in
        x11)
            [[ "${ZENBOOK_SESSION:-}" == wayland ]] && return 1
            # Accept binary presence when no DISPLAY (install from TTY).
            [[ -z "${DISPLAY:-}" ]] && return 0
            xrandr --query >/dev/null 2>&1
            ;;
        gnome)
            gdctl show >/dev/null 2>&1 && return 0
            # Install-time fallback when gdctl exists but session is inactive.
            [[ "${ZENBOOK_COMPOSITOR:-}" == mutter || "${ZENBOOK_DE:-}" == gnome || "${ZENBOOK_DE:-}" == budgie || "${ZENBOOK_DE:-}" == pantheon ]]
            ;;
        kde)
            kscreen-doctor -o >/dev/null 2>&1 && return 0
            [[ "${ZENBOOK_COMPOSITOR:-}" == kwin || "${ZENBOOK_DE:-}" == kde ]]
            ;;
        wlr)
            wlr-randr >/dev/null 2>&1 && return 0
            case "${ZENBOOK_COMPOSITOR:-}${ZENBOOK_DE:-}" in
                *sway*|*wayfire*|*labwc*|*river*|*niri*) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        hyprland)
            [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || [[ "${ZENBOOK_DE:-}" == hyprland || "${ZENBOOK_COMPOSITOR:-}" == hyprland ]] || return 1
            command -v hyprctl >/dev/null 2>&1
            ;;
        cosmic)
            cosmic-randr list >/dev/null 2>&1 && return 0
            [[ "${ZENBOOK_DE:-}" == cosmic || "${ZENBOOK_COMPOSITOR:-}" == cosmic ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# Probe order when the preferred tool is missing.
zenbook-backend-probe-order() {
    local preferred="${1}"
    local session="${2}"
    printf '%s\n' "${preferred}"
    if [[ "${session}" == wayland ]]; then
        printf '%s\n' wlr hyprland cosmic gnome kde x11
    else
        printf '%s\n' x11 gnome kde wlr hyprland cosmic
    fi
}

zenbook-select-backend() {
    local preferred session candidate
    preferred=$(zenbook-backend-preferred-for-de "${ZENBOOK_DE}" "${ZENBOOK_SESSION}" "${ZENBOOK_COMPOSITOR}")
    session=${ZENBOOK_SESSION}

    if [[ -n "${ZENBOOK_BACKEND_OVERRIDE:-}" ]]; then
        printf '%s\n' "${ZENBOOK_BACKEND_OVERRIDE}"
        return 0
    fi

    while read -r candidate; do
        [[ -n "${candidate}" ]] || continue
        if zenbook-backend-available "${candidate}"; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done < <(zenbook-backend-probe-order "${preferred}" "${session}" | awk 'NF && !seen[$0]++')

    # Last resort: keep preferred so install can pull the matching package.
    printf '%s\n' "${preferred}"
}

zenbook-only-show-in-for-de() {
    case "${1}" in
        mate) printf 'MATE\n' ;;
        gnome) printf 'GNOME\n' ;;
        kde) printf 'KDE\n' ;;
        xfce) printf 'XFCE\n' ;;
        cinnamon) printf 'X-Cinnamon\n' ;;
        lxqt) printf 'LXQt\n' ;;
        budgie) printf 'Budgie\n' ;;
        lxde) printf 'LXDE\n' ;;
        pantheon) printf 'Pantheon\n' ;;
        deepin) printf 'Deepin\n' ;;
        ukui) printf 'UKUI\n' ;;
        enlightenment) printf 'Enlightenment\n' ;;
        cosmic) printf 'COSMIC\n' ;;
        trinity) printf 'TDE\n' ;;
        unity) printf 'Unity\n' ;;
        # Tiling / compositor sessions usually ignore OnlyShowIn; leave empty.
        *) printf '\n' ;;
    esac
}

zenbook-detect-desktop() {
    local raw=""
    local token normalized
    local de=unknown
    local session
    local backend=""

    raw="${XDG_CURRENT_DESKTOP:-}"
    if [[ -z "${raw}" ]]; then
        raw="${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-}}"
    fi
    ZENBOOK_DE_RAW=${raw:-unset}

    IFS=':' read -r -a _zenbook_de_tokens <<< "${raw}"
    for token in "${_zenbook_de_tokens[@]}"; do
        normalized=$(zenbook-normalize-de-token "${token}")
        if [[ "${normalized}" != unknown ]]; then
            de=${normalized}
            break
        fi
    done

    if [[ "${de}" == unknown ]]; then
        de=$(zenbook-normalize-de-token "${DESKTOP_SESSION:-}")
    fi

    session=${XDG_SESSION_TYPE:-unknown}
    session=${session,,}
    case "${session}" in
        x11|wayland) ;;
        *) session=unknown ;;
    esac

    zenbook-detect-compositor

    # If DE is still unknown, infer from compositor.
    if [[ "${de}" == unknown ]]; then
        case "${ZENBOOK_COMPOSITOR}" in
            hyprland) de=hyprland ;;
            sway) de=sway ;;
            wayfire) de=wayfire ;;
            river) de=river ;;
            niri) de=niri ;;
            labwc) de=labwc ;;
            cosmic) de=cosmic ;;
            mutter) de=gnome ;;
            kwin) de=kde ;;
        esac
    fi

    ZENBOOK_DE=${de}
    ZENBOOK_SESSION=${session}
    ZENBOOK_BACKEND=$(zenbook-select-backend)
    ZENBOOK_ONLY_SHOW_IN=$(zenbook-only-show-in-for-de "${de}")

    export ZENBOOK_DE ZENBOOK_DE_RAW ZENBOOK_SESSION ZENBOOK_BACKEND ZENBOOK_ONLY_SHOW_IN ZENBOOK_COMPOSITOR
}

zenbook-backend-tool() {
    zenbook-backend-tool-name "${ZENBOOK_BACKEND:-}"
}

zenbook-backend-ready() {
    zenbook-backend-available "${ZENBOOK_BACKEND:-}"
}

zenbook-print-detection() {
    printf 'OS:            %s (%s)\n' "${ZENBOOK_OS_PRETTY:-unknown}" "${ZENBOOK_OS_ID:-unknown}"
    printf 'Package mgr:   %s\n' "${ZENBOOK_PKG_MANAGER:-unsupported}"
    printf 'Desktop raw:   %s\n' "${ZENBOOK_DE_RAW:-unset}"
    printf 'Desktop:       %s\n' "${ZENBOOK_DE:-unknown}"
    printf 'Compositor:    %s\n' "${ZENBOOK_COMPOSITOR:-unknown}"
    printf 'Session:       %s\n' "${ZENBOOK_SESSION:-unknown}"
    printf 'Backend:       %s\n' "${ZENBOOK_BACKEND:-unknown}"
    printf 'Backend tool:  %s\n' "$(zenbook-backend-tool)"
    printf 'OnlyShowIn:    %s\n' "${ZENBOOK_ONLY_SHOW_IN:-<all>}"
}
