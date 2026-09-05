#!/bin/bash
# XDG autostart entry generation from detected desktop environment.

zenbook-write-autostart() {
    local exec_path="${1}"
    local autostart_dir="${2:-${HOME}/.config/autostart}"
    local autostart_file="${3:-${autostart_dir}/zenbook.desktop}"
    local only_show_in="${ZENBOOK_ONLY_SHOW_IN:-}"
    local comment

    mkdir -p "${autostart_dir}"

    comment="ASUS Zenbook Duo helper (${ZENBOOK_PROFILE:-unknown}: ${ZENBOOK_DE:-unknown}/${ZENBOOK_SESSION:-unknown}, backend=${ZENBOOK_BACKEND:-unknown})"

    {
        printf '%s\n' '[Desktop Entry]'
        printf '%s\n' 'Type=Application'
        printf '%s\n' 'Version=1.0'
        printf '%s\n' 'Name=Zenbook Helper'
        printf 'Comment=%s\n' "${comment}"
        printf 'Exec=%s\n' "${exec_path}"
        printf '%s\n' 'Terminal=false'
        if [[ -n "${only_show_in}" ]]; then
            printf 'OnlyShowIn=%s;\n' "${only_show_in}"
        fi
        case "${ZENBOOK_DE}" in
            mate) printf '%s\n' 'X-MATE-Autostart-enabled=true' ;;
            gnome|budgie|pantheon|unity) printf '%s\n' 'X-GNOME-Autostart-enabled=true' ;;
            kde) printf '%s\n' 'X-KDE-autostart-after=panel' ;;
            xfce) printf '%s\n' 'X-XFCE-Autostart-Override=true' ;;
        esac
        printf '%s\n' 'Hidden=false'
    } > "${autostart_file}"

    chmod 0644 "${autostart_file}"
    printf '%s\n' "${autostart_file}"
}
