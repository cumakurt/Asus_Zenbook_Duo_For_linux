#!/bin/bash
# Operating system and package-manager detection.

zenbook-detect-os() {
    local id="" like="" pretty=""
    local candidate

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id=${ID:-}
        like=${ID_LIKE:-}
        pretty=${PRETTY_NAME:-${NAME:-$id}}
    else
        id=unknown
        like=""
        pretty=unknown
    fi

    ZENBOOK_OS_ID=${id,,}
    ZENBOOK_OS_LIKE=${like,,}
    ZENBOOK_OS_PRETTY=${pretty}

    ZENBOOK_PKG_MANAGER=""
    for candidate in "${ZENBOOK_OS_ID}" ${ZENBOOK_OS_LIKE}; do
        case "${candidate}" in
            debian|ubuntu|kali|linuxmint|pop|elementary|raspbian|devuan)
                ZENBOOK_PKG_MANAGER=apt
                break
                ;;
            fedora|rhel|centos|rocky|almalinux|nobara)
                ZENBOOK_PKG_MANAGER=dnf
                break
                ;;
            arch|manjaro|endeavouros|garuda|artix)
                ZENBOOK_PKG_MANAGER=pacman
                break
                ;;
        esac
    done

    if [[ -z "${ZENBOOK_PKG_MANAGER}" ]]; then
        if command -v apt-get >/dev/null 2>&1; then
            ZENBOOK_PKG_MANAGER=apt
        elif command -v dnf >/dev/null 2>&1; then
            ZENBOOK_PKG_MANAGER=dnf
        elif command -v pacman >/dev/null 2>&1; then
            ZENBOOK_PKG_MANAGER=pacman
        fi
    fi

    export ZENBOOK_OS_ID ZENBOOK_OS_LIKE ZENBOOK_OS_PRETTY ZENBOOK_PKG_MANAGER
}

zenbook-require-pkg-manager() {
    if [[ -z "${ZENBOOK_PKG_MANAGER:-}" ]]; then
        printf 'Unsupported OS for automatic package install (ID=%s LIKE=%s). Supported managers: apt, dnf, pacman.\n' \
            "${ZENBOOK_OS_ID:-unknown}" "${ZENBOOK_OS_LIKE:-}" >&2
        return 1
    fi
    return 0
}
