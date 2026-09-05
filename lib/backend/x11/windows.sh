#!/bin/bash
# X11 window relocation helpers for the bottom panel (wmctrl + EWMH WMs).

# Save windows whose centre point is on the bottom output before it is disabled.
# Window managers may relocate windows after a RandR output disappears; wmctrl
# makes the behaviour deterministic for ordinary, non-sticky windows.
function zenbook-save-bottom-windows() {
    : > "${BOTTOM_WINDOWS_STATE}"

    if ! command -v wmctrl >/dev/null 2>&1; then
        echo "$(date) - WINDOW - wmctrl not installed; relying on the window manager to relocate windows"
        return 0
    fi

    local geometry bw bh bx by
    geometry=$(zenbook-output-geometry "${BOTTOM_OUTPUT}")
    if [[ ! "${geometry}" =~ ^([0-9]+)x([0-9]+)([+-][0-9]+)([+-][0-9]+)$ ]]; then
        return 0
    fi

    bw=${BASH_REMATCH[1]}
    bh=${BASH_REMATCH[2]}
    bx=$(( ${BASH_REMATCH[3]} ))
    by=$(( ${BASH_REMATCH[4]} ))

    while read -r wid desktop wx wy ww wh host title; do
        [[ "${desktop}" == "-1" ]] && continue
        [[ "${wx}" =~ ^-?[0-9]+$ ]] || continue
        [[ "${wy}" =~ ^-?[0-9]+$ ]] || continue
        [[ "${ww}" =~ ^[0-9]+$ ]] || continue
        [[ "${wh}" =~ ^[0-9]+$ ]] || continue

        local cx cy relx rely maxv maxh fullscreen state
        cx=$((wx + ww / 2))
        cy=$((wy + wh / 2))
        if (( cx >= bx && cx < bx + bw && cy >= by && cy < by + bh )); then
            relx=$((wx - bx))
            rely=$((wy - by))
            maxv=0
            maxh=0
            fullscreen=0
            if command -v xprop >/dev/null 2>&1; then
                state=$(xprop -id "${wid}" _NET_WM_STATE 2>/dev/null || true)
                [[ "${state}" == *"_NET_WM_STATE_MAXIMIZED_VERT"* ]] && maxv=1
                [[ "${state}" == *"_NET_WM_STATE_MAXIMIZED_HORZ"* ]] && maxh=1
                [[ "${state}" == *"_NET_WM_STATE_FULLSCREEN"* ]] && fullscreen=1
            fi
            printf '%s %d %d %d %d %d %d %d\n' \
                "${wid}" "${relx}" "${rely}" "${ww}" "${wh}" "${maxv}" "${maxh}" "${fullscreen}" >> "${BOTTOM_WINDOWS_STATE}"
        fi
    done < <(wmctrl -lG 2>/dev/null)
}

function zenbook-move-saved-windows-to-top() {
    [ -s "${BOTTOM_WINDOWS_STATE}" ] || return 0
    command -v wmctrl >/dev/null 2>&1 || return 0

    # Give the window manager a brief moment to process the RandR screen-size change first.
    sleep 0.25

    local geometry tw th tx ty
    geometry=$(zenbook-output-geometry "${TOP_OUTPUT}")
    if [[ ! "${geometry}" =~ ^([0-9]+)x([0-9]+)([+-][0-9]+)([+-][0-9]+)$ ]]; then
        rm -f "${BOTTOM_WINDOWS_STATE}"
        return 0
    fi

    tw=${BASH_REMATCH[1]}
    th=${BASH_REMATCH[2]}
    tx=$(( ${BASH_REMATCH[3]} ))
    ty=$(( ${BASH_REMATCH[4]} ))

    while read -r wid relx rely ww wh maxv maxh fullscreen; do
        local maxx maxy nx ny
        maxx=$((tw - ww))
        maxy=$((th - wh))
        (( maxx < 0 )) && maxx=0
        (( maxy < 0 )) && maxy=0
        (( relx < 0 )) && relx=0
        (( rely < 0 )) && rely=0
        (( relx > maxx )) && relx=${maxx}
        (( rely > maxy )) && rely=${maxy}
        nx=$((tx + relx))
        ny=$((ty + rely))

        # Maximized/fullscreen windows ignore normal move requests. Temporarily
        # drop those states, move the window, then restore the original state.
        (( fullscreen == 1 )) && wmctrl -ir "${wid}" -b remove,fullscreen >/dev/null 2>&1 || true
        (( maxv == 1 )) && wmctrl -ir "${wid}" -b remove,maximized_vert >/dev/null 2>&1 || true
        (( maxh == 1 )) && wmctrl -ir "${wid}" -b remove,maximized_horz >/dev/null 2>&1 || true
        wmctrl -ir "${wid}" -e "0,${nx},${ny},-1,-1" >/dev/null 2>&1 || true
        (( maxv == 1 )) && wmctrl -ir "${wid}" -b add,maximized_vert >/dev/null 2>&1 || true
        (( maxh == 1 )) && wmctrl -ir "${wid}" -b add,maximized_horz >/dev/null 2>&1 || true
        (( fullscreen == 1 )) && wmctrl -ir "${wid}" -b add,fullscreen >/dev/null 2>&1 || true
    done < "${BOTTOM_WINDOWS_STATE}"

    rm -f "${BOTTOM_WINDOWS_STATE}"
}
