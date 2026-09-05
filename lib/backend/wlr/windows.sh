#!/bin/bash
# Wayland compositors do not expose wmctrl-compatible window moves.

function zenbook-save-bottom-windows() {
    : > "${BOTTOM_WINDOWS_STATE}"
    return 0
}

function zenbook-move-saved-windows-to-top() {
    rm -f "${BOTTOM_WINDOWS_STATE}"
    return 0
}
