#!/bin/bash
# ASUS Zenbook Duo helper uninstaller.
# Author: Cuma KURT — https://github.com/cumakurt/Asus_Zenbook_Duo_For_linux
# License: GPL-3.0-or-later
# Removes only this application's installed artifacts (not shared system packages).

set -Eeuo pipefail

INSTALL_ROOT=/usr/local/lib/zenbook
INSTALL_LOCATION=/usr/local/bin/zenbook
AUTOSTART_DIR="${HOME}/.config/autostart"
AUTOSTART_FILE="${AUTOSTART_DIR}/zenbook.desktop"
UDEV_RULE=/etc/udev/rules.d/70-zenbook-keyboard.rules
DRY_RUN=false
ASSUME_YES=false
STEP_TOTAL=6
STEP_CURRENT=0
REMOVED=0
SKIPPED=0

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SOURCE_LIB="${SCRIPT_DIR}/lib"

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
    C_RESET= C_BOLD= C_DIM= C_RED= C_GREEN= C_YELLOW= C_BLUE= C_CYAN=
    S_OK='OK'
    S_WARN='!'
    S_ERR='ERR'
    S_BULLET='-'
fi

banner() {
    printf '\n%s%s Zenbook Duo%s %suninstaller%s\n' \
        "${C_BOLD}" "${C_CYAN}" "${C_RESET}" "${C_DIM}" "${C_RESET}"
    printf '  %sCuma KURT%s · %sGPL-3.0%s\n' \
        "${C_DIM}" "${C_RESET}" "${C_DIM}" "${C_RESET}"
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

mark_removed() {
    REMOVED=$((REMOVED + 1))
    ok "removed $*"
}

mark_skip() {
    SKIPPED=$((SKIPPED + 1))
    info "absent $*"
}

usage() {
    cat <<EOF
Usage: ./uninstall.sh [--yes] [--dry-run]

Safely removes Zenbook Duo helper install artifacts only:
  • running helper processes
  • /usr/local/bin/zenbook and /usr/local/lib/zenbook
  • XDG autostart entry
  • udev keyboard uaccess rule
  • runtime state (~/XDG or /tmp/zenbook)
  • obsolete systemd units and zenbook sudoers snippets

Does NOT remove shared packages (gcc, wmctrl, xrandr, …) or this source tree.

Options:
  --yes               Do not ask for confirmation
  --dry-run           Show what would be removed
  -h, --help          Show this help
EOF
}

# shellcheck source=/dev/null
. "${SOURCE_LIB}/install/cleanup.sh"

if (( EUID == 0 )); then
    die "Run as your desktop user (./uninstall.sh), not with sudo"
fi

TARGET_USER=${USER:-$(id -un)}
TARGET_UID=$(id -u)

while [[ $# -gt 0 ]]; do
    case "${1}" in
        --yes|-y) ASSUME_YES=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: ${1} (try --help)" ;;
    esac
done

banner

if [[ "${DRY_RUN}" == true ]]; then
    info "Dry-run — no changes will be made"
elif [[ "${ASSUME_YES}" != true ]]; then
    printf '\n  This will remove the installed Zenbook Duo helper from this system.\n'
    printf '  Shared packages and the project source directory stay untouched.\n\n'
    read -r -p "  Continue? [y/N] " answer
    case "${answer}" in
        y|Y|yes|YES) ;;
        *) info "Aborted"; exit 0 ;;
    esac
    printf '\n'
fi

run() {
    if [[ "${DRY_RUN}" == true ]]; then
        info "would run: $*"
        return 0
    fi
    "$@"
}

remove_path() {
    local path="${1}"
    local need_sudo="${2:-0}"

    if [[ ! -e "${path}" && ! -L "${path}" ]]; then
        mark_skip "${path}"
        return 0
    fi

    if [[ "${DRY_RUN}" == true ]]; then
        info "would remove ${path}"
        REMOVED=$((REMOVED + 1))
        return 0
    fi

    if [[ "${need_sudo}" == 1 ]]; then
        sudo rm -rf -- "${path}"
    else
        rm -rf -- "${path}"
    fi
    mark_removed "${path}"
}

# --- 1. Stop helper -----------------------------------------------------------
step "Stop helper processes"
if [[ "${DRY_RUN}" == true ]]; then
    info "would stop zenbook helper processes for uid ${TARGET_UID}"
else
    killed=0
    while read -r pid; do
        [[ -n "${pid}" && "${pid}" != "$$" ]] || continue
        kill "${pid}" 2>/dev/null || true
        killed=$((killed + 1))
    done < <(
        pgrep -u "${TARGET_UID}" -f "^${INSTALL_LOCATION}( |$)" 2>/dev/null || true
        pgrep -u "${TARGET_UID}" -f "^${INSTALL_ROOT}/zenbook\\.sh( |$)" 2>/dev/null || true
    )
    # Allow children to exit.
    sleep 0.3
    if (( killed > 0 )); then
        ok "stopped ${killed} process(es)"
    else
        info "no running helper"
    fi
fi

# --- 2. Autostart -------------------------------------------------------------
step "Remove autostart"
remove_path "${AUTOSTART_FILE}" 0
remove_path "${AUTOSTART_DIR}/zenbook-duo.desktop" 0

# --- 3. Udev ------------------------------------------------------------------
step "Remove udev rule"
for rule in "${UDEV_RULE}" /etc/udev/rules.d/70-zenbook-duo-keyboard.rules; do
    if [[ -e "${rule}" || -L "${rule}" ]]; then
        if [[ "${DRY_RUN}" == true ]]; then
            info "would remove ${rule}"
            REMOVED=$((REMOVED + 1))
        else
            sudo rm -f -- "${rule}"
            mark_removed "${rule}"
        fi
    else
        mark_skip "${rule}"
    fi
done
if [[ "${DRY_RUN}" != true ]]; then
    sudo udevadm control --reload-rules >/dev/null 2>&1 || true
    sudo udevadm trigger --subsystem-match=usb --action=add >/dev/null 2>&1 || true
fi

# --- 4. Installed files -------------------------------------------------------
step "Remove installed files"
# Symlink first, then tree.
if [[ -L "${INSTALL_LOCATION}" || -e "${INSTALL_LOCATION}" ]]; then
    # Only remove if it points at our tree or is our known path.
    if [[ -L "${INSTALL_LOCATION}" ]]; then
        target=$(readlink -f -- "${INSTALL_LOCATION}" 2>/dev/null || true)
        if [[ "${target}" == "${INSTALL_ROOT}/zenbook.sh" || "${INSTALL_LOCATION}" == /usr/local/bin/zenbook ]]; then
            remove_path "${INSTALL_LOCATION}" 1
        else
            warn "skip ${INSTALL_LOCATION} (unexpected target: ${target:-unknown})"
            SKIPPED=$((SKIPPED + 1))
        fi
    elif [[ "${INSTALL_LOCATION}" == /usr/local/bin/zenbook ]]; then
        remove_path "${INSTALL_LOCATION}" 1
    else
        warn "skip ${INSTALL_LOCATION}"
        SKIPPED=$((SKIPPED + 1))
    fi
else
    mark_skip "${INSTALL_LOCATION}"
fi

if [[ -e "${INSTALL_ROOT}" || -L "${INSTALL_ROOT}" ]]; then
    remove_path "${INSTALL_ROOT}" 1
else
    mark_skip "${INSTALL_ROOT}"
fi

# --- 5. Runtime state ---------------------------------------------------------
step "Remove runtime state"
runtime_paths=()
if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    runtime_paths+=("${XDG_RUNTIME_DIR}/zenbook")
fi
runtime_paths+=("/tmp/zenbook")

for path in "${runtime_paths[@]}"; do
    # Refuse to delete if path is not clearly ours.
    case "${path}" in
        */zenbook) ;;
        *) warn "skip unexpected runtime path ${path}"; continue ;;
    esac
    if [[ -e "${path}" || -L "${path}" ]]; then
        if [[ "${DRY_RUN}" == true ]]; then
            info "would remove ${path}"
            REMOVED=$((REMOVED + 1))
        else
            rm -rf -- "${path}" 2>/dev/null || sudo rm -rf -- "${path}"
            mark_removed "${path}"
        fi
    else
        mark_skip "${path}"
    fi
done

# --- 6. Obsolete system hooks -------------------------------------------------
step "Remove obsolete hooks"
if [[ "${DRY_RUN}" == true ]]; then
    info "would clean obsolete systemd units and sudoers.d snippets"
else
    if zenbook-cleanup-obsolete-hooks "${TARGET_USER}" >/dev/null 2>&1; then
        ok "obsolete systemd/sudoers cleaned"
    else
        warn "obsolete-hooks cleanup reported an issue; check /etc/sudoers backups if present"
    fi
fi

printf '\n%s%s %s%s  removed=%s  skipped=%s\n\n' \
    "${C_GREEN}${C_BOLD}" "${S_OK}" "Uninstall complete" "${C_RESET}" \
    "${REMOVED}" "${SKIPPED}"

if [[ "${DRY_RUN}" == true ]]; then
    info "Re-run without --dry-run to apply"
    printf '\n'
fi
