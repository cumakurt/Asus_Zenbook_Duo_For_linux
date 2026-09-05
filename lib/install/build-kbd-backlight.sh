#!/bin/bash
# Build the native keyboard backlight helper (no Python).

zenbook-build-kbd-backlight() {
    local src="${1}"
    local out="${2}"
    local cc

    [[ -f "${src}" ]] || {
        printf 'ERROR: missing source %s\n' "${src}" >&2
        return 1
    }

    cc=$(command -v cc || command -v gcc || command -v clang || true)
    if [[ -z "${cc}" ]]; then
        printf 'ERROR: no C compiler (cc/gcc/clang) found to build kbd-backlight\n' >&2
        return 1
    fi

    "${cc}" -O2 -Wall -Wextra -o "${out}" "${src}"
}
