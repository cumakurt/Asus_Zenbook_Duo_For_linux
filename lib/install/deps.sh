#!/bin/bash
# Package dependency lists and installers per package manager / backend.

zenbook-deps-common() {
    case "${ZENBOOK_PKG_MANAGER}" in
        apt)
            printf '%s\n' \
                inotify-tools usbutils iio-sensor-proxy \
                brightnessctl libnotify-bin libglib2.0-bin network-manager rfkill gcc
            ;;
        dnf)
            printf '%s\n' \
                inotify-tools usbutils iio-sensor-proxy \
                brightnessctl libnotify glib2 NetworkManager rfkill gcc
            ;;
        pacman)
            printf '%s\n' \
                inotify-tools usbutils iio-sensor-proxy \
                brightnessctl libnotify glib2 networkmanager rfkill gcc
            ;;
    esac
}

zenbook-deps-backend() {
    case "${ZENBOOK_PKG_MANAGER}:${ZENBOOK_BACKEND}" in
        apt:x11)
            printf '%s\n' x11-xserver-utils x11-utils wmctrl xinput
            ;;
        apt:gnome)
            printf '%s\n' mutter
            ;;
        apt:kde)
            printf '%s\n' libkscreen-bin
            ;;
        apt:wlr)
            printf '%s\n' wlr-randr
            ;;
        apt:hyprland)
            # hyprctl ships with Hyprland; no extra package on most distros.
            ;;
        apt:cosmic)
            # cosmic-randr ships with COSMIC; optional if packaged separately.
            printf '%s\n' cosmic-randr
            ;;
        dnf:x11)
            printf '%s\n' xorg-x11-server-utils xprop wmctrl xinput
            ;;
        dnf:gnome)
            printf '%s\n' mutter
            ;;
        dnf:kde)
            printf '%s\n' libkscreen
            ;;
        dnf:wlr)
            printf '%s\n' wlr-randr
            ;;
        dnf:hyprland)
            ;;
        dnf:cosmic)
            printf '%s\n' cosmic-randr
            ;;
        pacman:x11)
            printf '%s\n' xorg-xrandr xorg-xprop wmctrl xorg-xinput
            ;;
        pacman:gnome)
            printf '%s\n' mutter
            ;;
        pacman:kde)
            printf '%s\n' libkscreen
            ;;
        pacman:wlr)
            printf '%s\n' wlr-randr
            ;;
        pacman:hyprland)
            ;;
        pacman:cosmic)
            printf '%s\n' cosmic-randr
            ;;
    esac
}

zenbook-deps-list() {
    { zenbook-deps-common; zenbook-deps-backend; } | awk 'NF && !seen[$0]++'
}

zenbook-install-packages() {
    local packages
    mapfile -t packages < <(zenbook-deps-list)
    ((${#packages[@]})) || return 0

    case "${ZENBOOK_PKG_MANAGER}" in
        apt)
            sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
            local available=()
            local pkg
            for pkg in "${packages[@]}"; do
                if apt-cache show "${pkg}" >/dev/null 2>&1; then
                    available+=("${pkg}")
                fi
            done
            ((${#available[@]})) || return 0
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${available[@]}"
            ;;
        dnf)
            sudo dnf install -y -q "${packages[@]}"
            ;;
        pacman)
            sudo pacman -Sy --needed --noconfirm --quiet "${packages[@]}"
            ;;
        *)
            printf 'No package manager available to install: %s\n' "${packages[*]}" >&2
            return 1
            ;;
    esac
}
