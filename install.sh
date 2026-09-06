#!/bin/bash
# ASUS Zenbook Duo UX8406CA - automatic OS/DE detection installer.
# Author: Cuma KURT — https://github.com/cumakurt/Asus_Zenbook_Duo_For_linux
# License: GPL-3.0-or-later
# Detects OS, desktop environment and session type, then installs the matching stack.

set -Eeuo pipefail

INSTALL_ROOT=/usr/local/lib/zenbook
INSTALL_LOCATION=/usr/local/bin/zenbook
DEFAULT_BACKLIGHT=3
DRY_RUN=false
STEP_TOTAL=8
STEP_CURRENT=0

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SOURCE_ZENBOOK="${SCRIPT_DIR}/zenbook.sh"
SOURCE_LIB="${SCRIPT_DIR}/lib"
ZENBOOK_LIB_DIR="${SOURCE_LIB}"
export ZENBOOK_LIB_DIR
AUTOSTART_DIR="${HOME}/.config/autostart"
AUTOSTART_FILE="${AUTOSTART_DIR}/zenbook.desktop"
UDEV_RULE=/etc/udev/rules.d/70-zenbook-keyboard.rules

# Colors/symbols only on interactive terminals (respect NO_COLOR).
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
    S_OK='✓'
    S_WARN='!'
    S_ERR='✗'
    S_BULLET='•'
else
    C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
    S_OK='OK'
    S_WARN='!'
    S_ERR='ERR'
    S_BULLET='-'
fi

banner() {
    printf '\n%s%s Zenbook Duo%s %sinstaller%s\n' \
        "${C_BOLD}" "${C_CYAN}" "${C_RESET}" "${C_DIM}" "${C_RESET}"
    printf '  %s%s%s · %sGPL-3.0%s\n' \
        "${C_DIM}" "${ZENBOOK_AUTHOR_NAME:-Cuma KURT}" "${C_RESET}" "${C_DIM}" "${C_RESET}"
}

step() {
    STEP_CURRENT=$((STEP_CURRENT + 1))
    printf '%s[%d/%d]%s %s%s%s\n' \
        "${C_BLUE}${C_BOLD}" "${STEP_CURRENT}" "${STEP_TOTAL}" "${C_RESET}" \
        "${C_BOLD}" "$*" "${C_RESET}"
}

ok() {
    printf '  %s%s%s %s\n' "${C_GREEN}" "${S_OK}" "${C_RESET}" "$*"
}

info() {
    printf '  %s%s%s %s\n' "${C_CYAN}" "${S_BULLET}" "${C_RESET}" "$*"
}

warn() {
    printf '  %s%s%s %s\n' "${C_YELLOW}" "${S_WARN}" "${C_RESET}" "$*" >&2
}

die() {
    printf '%s%s%s %s\n' "${C_RED}${C_BOLD}" "${S_ERR}" "${C_RESET}" "$*" >&2
    exit 1
}

kv() {
    printf '  %s%-10s%s %s\n' "${C_DIM}" "$1" "${C_RESET}" "$2"
}

# shellcheck source=/dev/null
. "${SOURCE_LIB}/detect/os.sh"
# shellcheck source=/dev/null
. "${SOURCE_LIB}/config.sh"
# shellcheck source=/dev/null
. "${SOURCE_LIB}/detect/desktop.sh"
# shellcheck source=/dev/null
. "${SOURCE_LIB}/install/deps.sh"
# shellcheck source=/dev/null
. "${SOURCE_LIB}/install/autostart.sh"
# shellcheck source=/dev/null
. "${SOURCE_LIB}/install/udev.sh"
# shellcheck source=/dev/null
. "${SOURCE_LIB}/install/cleanup.sh"
# shellcheck source=/dev/null
. "${SOURCE_LIB}/install/build-kbd-backlight.sh"
# shellcheck source=/dev/null
. "${SOURCE_LIB}/profile.sh"

validate_sources() {
    local file backend
    [[ -f "${SOURCE_ZENBOOK}" ]] || die "zenbook.sh was not found next to install.sh"
    [[ -d "${SOURCE_LIB}" ]] || die "lib/ was not found next to install.sh"
    [[ -f "${SOURCE_LIB}/kbd-backlight.c" ]] || die "lib/kbd-backlight.c is missing"

    /bin/bash -n "${SOURCE_ZENBOOK}" || die "zenbook.sh has a Bash syntax error"

    while IFS= read -r -d '' file; do
        /bin/bash -n "${file}" || die "Syntax error in ${file#"${SOURCE_LIB}"/}"
    done < <(find "${SOURCE_LIB}" -type f -name '*.sh' -print0)

    for backend in x11 gnome kde wlr hyprland cosmic; do
        [[ -f "${SOURCE_LIB}/backend/${backend}/display.sh" ]] || die "Missing backend: ${backend}"
        [[ -f "${SOURCE_LIB}/backend/${backend}/windows.sh" ]] || die "Missing backend: ${backend}"
    done
}

build_kbd_backlight() {
    local out_dir="${1}"
    local out_bin="${out_dir}/kbd-backlight"
    local tmp_bin

    tmp_bin=$(mktemp)
    if ! zenbook-build-kbd-backlight "${SOURCE_LIB}/kbd-backlight.c" "${tmp_bin}" >/dev/null 2>&1; then
        rm -f "${tmp_bin}"
        die "Failed to compile kbd-backlight (install gcc/cc and retry)"
    fi

    if [[ "${out_dir}" == "${SOURCE_LIB}" ]]; then
        install -m 0755 "${tmp_bin}" "${out_bin}"
    else
        sudo install -m 0755 "${tmp_bin}" "${out_bin}"
    fi
    rm -f "${tmp_bin}"
}

install_tree() {
    local backend file

    sudo install -d -m 0755 "${INSTALL_ROOT}/lib/detect"
    sudo install -d -m 0755 "${INSTALL_ROOT}/lib/install"
    sudo install -d -m 0755 "${INSTALL_ROOT}/lib/profile"

    for backend in x11 gnome kde wlr hyprland cosmic; do
        sudo install -d -m 0755 "${INSTALL_ROOT}/lib/backend/${backend}"
    done

    sudo install -m 0755 "${SOURCE_ZENBOOK}" "${INSTALL_ROOT}/zenbook.sh"

    for file in "${SOURCE_LIB}"/*.sh; do
        [[ -f "${file}" ]] || continue
        sudo install -m 0644 "${file}" "${INSTALL_ROOT}/lib/"
    done
    sudo install -m 0644 "${SOURCE_LIB}/kbd-backlight.c" "${INSTALL_ROOT}/lib/kbd-backlight.c"

    sudo install -m 0644 "${SOURCE_LIB}/detect/"*.sh "${INSTALL_ROOT}/lib/detect/"
    sudo install -m 0644 "${SOURCE_LIB}/install/"*.sh "${INSTALL_ROOT}/lib/install/"
    sudo install -m 0644 "${SOURCE_LIB}/profile/"*.sh "${INSTALL_ROOT}/lib/profile/"

    for backend in x11 gnome kde wlr hyprland cosmic; do
        sudo install -m 0644 "${SOURCE_LIB}/backend/${backend}/"*.sh "${INSTALL_ROOT}/lib/backend/${backend}/"
    done

    build_kbd_backlight "${INSTALL_ROOT}/lib"

    sudo sed -i -E "s/^DEFAULT_BACKLIGHT=.*/DEFAULT_BACKLIGHT=${DEFAULT_BACKLIGHT}/" "${INSTALL_ROOT}/lib/config.sh"
    sudo ln -sfn "${INSTALL_ROOT}/zenbook.sh" "${INSTALL_LOCATION}"
}

session_can_start_helper() {
    case "${ZENBOOK_BACKEND}" in
        x11)
            [[ -n "${DISPLAY:-}" ]] && command -v xrandr >/dev/null 2>&1 && xrandr --query >/dev/null 2>&1
            ;;
        gnome) command -v gdctl >/dev/null 2>&1 ;;
        kde) command -v kscreen-doctor >/dev/null 2>&1 ;;
        wlr) command -v wlr-randr >/dev/null 2>&1 ;;
        hyprland) command -v hyprctl >/dev/null 2>&1 ;;
        cosmic) command -v cosmic-randr >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

probe_outputs() {
    local missing=()
    case "${ZENBOOK_BACKEND}" in
        x11)
            if [[ -n "${DISPLAY:-}" ]] && command -v xrandr >/dev/null 2>&1 && xrandr --query >/dev/null 2>&1; then
                xrandr --query | grep -q '^eDP-1 connected' || missing+=("eDP-1")
                xrandr --query | grep -q '^eDP-2 connected' || missing+=("eDP-2")
            fi
            ;;
        gnome)
            if command -v gdctl >/dev/null 2>&1; then
                gdctl show 2>/dev/null | grep -q 'eDP-1' || missing+=("eDP-1")
                gdctl show 2>/dev/null | grep -q 'eDP-2' || missing+=("eDP-2")
            fi
            ;;
        kde)
            if command -v kscreen-doctor >/dev/null 2>&1; then
                kscreen-doctor -o 2>/dev/null | grep -q 'eDP-1' || missing+=("eDP-1")
                kscreen-doctor -o 2>/dev/null | grep -q 'eDP-2' || missing+=("eDP-2")
            fi
            ;;
        wlr)
            if command -v wlr-randr >/dev/null 2>&1; then
                wlr-randr 2>/dev/null | grep -q 'eDP-1' || missing+=("eDP-1")
                wlr-randr 2>/dev/null | grep -q 'eDP-2' || missing+=("eDP-2")
            fi
            ;;
        hyprland)
            if command -v hyprctl >/dev/null 2>&1; then
                hyprctl monitors 2>/dev/null | grep -q 'eDP-1' || missing+=("eDP-1")
                hyprctl monitors 2>/dev/null | grep -q 'eDP-2' || missing+=("eDP-2")
            fi
            ;;
        cosmic)
            if command -v cosmic-randr >/dev/null 2>&1; then
                cosmic-randr list 2>/dev/null | grep -q 'eDP-1' || missing+=("eDP-1")
                cosmic-randr list 2>/dev/null | grep -q 'eDP-2' || missing+=("eDP-2")
            fi
            ;;
    esac
    if ((${#missing[@]})); then
        warn "Panel(s) not detected now: ${missing[*]} (ok if installing outside a GUI session)"
    fi
}

print_detection() {
    local pkg_count
    pkg_count=$(zenbook-deps-list | wc -l)
    kv "OS" "${ZENBOOK_OS_PRETTY}"
    kv "Desktop" "${ZENBOOK_DE} / ${ZENBOOK_SESSION}"
    kv "Profile" "${ZENBOOK_PROFILE:-unknown} (${ZENBOOK_PROFILE_LABEL:-unknown})"
    kv "Backend" "${ZENBOOK_BACKEND} ($(zenbook-backend-tool))"
    kv "Caps" "touch=${ZENBOOK_PROFILE_TOUCH:-none} windows=${ZENBOOK_PROFILE_WINDOWS:-none} mirror=${ZENBOOK_PROFILE_MIRROR:-none}"
    kv "Backlight" "${DEFAULT_BACKLIGHT}"
    kv "Packages" "${pkg_count} packages (${ZENBOOK_PKG_MANAGER})"
}

usage() {
    cat <<EOF
Usage: ./install.sh [--dry-run] [--backlight 0-3]

Detects OS/desktop/session and installs the Zenbook Duo helper.

Options:
  --dry-run           Show detection plan only
  --backlight N       Keyboard backlight 0-3 (default: 3)
  -h, --help          Show this help
EOF
}

if (( EUID == 0 )); then
    die "Run as your desktop user (./install.sh), not with sudo"
fi

TARGET_USER=${USER:-$(id -un)}
TARGET_UID=$(id -u)
TARGET_GROUP=$(id -gn)

while [[ $# -gt 0 ]]; do
    case "${1}" in
        --dry-run) DRY_RUN=true; shift ;;
        --backlight)
            [[ -n "${2:-}" ]] || die "--backlight requires 0-3"
            [[ "${2}" =~ ^[0-3]$ ]] || die "Invalid --backlight: ${2}"
            DEFAULT_BACKLIGHT=${2}
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: ${1} (try --help)" ;;
    esac
done

banner
validate_sources

zenbook-detect-os
zenbook-require-pkg-manager || die "Unsupported OS (need apt, dnf, or pacman)"
zenbook-detect-desktop || die "Desktop/session detection failed"
zenbook-load-profile

step "Detect environment"
print_detection

if [[ "${DRY_RUN}" == true ]]; then
    ok "Dry-run only — nothing was changed"
    printf '\n'
    exit 0
fi

step "Install packages (${ZENBOOK_PKG_MANAGER})"
zenbook-install-packages || die "Package installation failed"
ZENBOOK_BACKEND=$(zenbook-select-backend)
export ZENBOOK_BACKEND
zenbook-load-profile
ok "${ZENBOOK_BACKEND} via $(zenbook-backend-tool) · profile ${ZENBOOK_PROFILE}"

step "Install files"
install_tree
[[ -x "${INSTALL_ROOT}/lib/kbd-backlight" ]] || die "kbd-backlight binary missing after build"
/bin/bash -n "${INSTALL_LOCATION}" || die "Installed helper failed syntax check"
ok "${INSTALL_LOCATION}"

step "Autostart"
AUTOSTART_FILE=$(zenbook-write-autostart "${INSTALL_LOCATION}" "${AUTOSTART_DIR}" "${AUTOSTART_FILE}")
# Previous installs used a different desktop filename; keep a single autostart entry.
rm -f "${AUTOSTART_DIR}/zenbook-duo.desktop" 2>/dev/null || true
ok "${AUTOSTART_FILE#"${HOME}"/}"

step "USB/BT keyboard access"
zenbook-configure-udev-keyboard "${UDEV_RULE}" || die "udev rule install failed"
ok "udev uaccess rule installed (USB + Bluetooth hidraw)"
if ! lsusb 2>/dev/null | grep -qi 'Zenbook Duo Keyboard'; then
    warn "Keyboard not plugged in yet — replug or re-pair BT after install if needed"
fi
sudo rm -f /etc/udev/rules.d/70-zenbook-duo-keyboard.rules 2>/dev/null || true

step "Bluetooth HID-safe settings"
if zenbook-configure-bluez-gatt; then
    ok "BlueZ ExportClaimedServices kept read-only (BT keyboard HID)"
else
    warn "Could not update /etc/bluetooth/main.conf"
fi

step "Cleanup obsolete hooks"
zenbook-cleanup-obsolete-hooks "${TARGET_USER}" >/dev/null 2>&1 || die "Obsolete-hooks cleanup failed"
ok "obsolete services/sudoers cleaned"
probe_outputs

step "Start helper"
if session_can_start_helper; then
    runtime_dir=""
    if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "${XDG_RUNTIME_DIR}" ]]; then
        runtime_dir="${XDG_RUNTIME_DIR}/zenbook"
    else
        runtime_dir=/tmp/zenbook
    fi

    # Match the installed entrypoint and any lingering repo-path daemons.
    while read -r pid; do
        [[ -n "${pid}" && "${pid}" != "$$" ]] || continue
        kill "${pid}" 2>/dev/null || true
    done < <(
        pgrep -u "${TARGET_UID}" -f "^${INSTALL_LOCATION}( |$)" 2>/dev/null || true
        pgrep -u "${TARGET_UID}" -f "^${INSTALL_ROOT}/zenbook\\.sh( |$)" 2>/dev/null || true
    )
    sleep 0.6
    while read -r pid; do
        [[ -n "${pid}" && "${pid}" != "$$" ]] || continue
        kill -9 "${pid}" 2>/dev/null || true
    done < <(
        pgrep -u "${TARGET_UID}" -f "^${INSTALL_LOCATION}( |$)" 2>/dev/null || true
        pgrep -u "${TARGET_UID}" -f "^${INSTALL_ROOT}/zenbook\\.sh( |$)" 2>/dev/null || true
    )
    pkill -u "${TARGET_UID}" -f 'tee -a .*/zenbook/zenbook\\.log' 2>/dev/null || true

    { mkdir -p "${runtime_dir}" 2>/dev/null && chmod 700 "${runtime_dir}" 2>/dev/null; } || sudo install -d -o "${TARGET_USER}" -g "${TARGET_GROUP}" -m 0700 "${runtime_dir}"
    rm -f "${runtime_dir}/status" "${runtime_dir}/daemon.lock" "${runtime_dir}/detach-backlight.pid" 2>/dev/null || true
    sudo chown -R "${TARGET_USER}:${TARGET_GROUP}" "${runtime_dir}" 2>/dev/null || true
    nohup "${INSTALL_LOCATION}" >"${runtime_dir}/zenbook-session.log" 2>&1 &
    disown || true
    ok "running in ${ZENBOOK_DE} session"
else
    info "log out/in to start the helper"
fi

printf '\n%s%s %s%s  %s%s · %s/%s · %s%s\n\n' \
    "${C_GREEN}${C_BOLD}" "${S_OK}" "Done" "${C_RESET}" \
    "${C_DIM}" "${ZENBOOK_OS_ID}" "${ZENBOOK_DE}" "${ZENBOOK_SESSION}" "${ZENBOOK_BACKEND}" "${C_RESET}"
