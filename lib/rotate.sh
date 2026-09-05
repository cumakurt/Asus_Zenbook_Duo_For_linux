#!/bin/bash
# Accelerometer orientation watcher (in-process; no full script re-exec).

function zenbook-watch-rotate() {
    local orientation
    echo "$(date) - ROTATE - Watching"
    while true; do
        if ! command -v monitor-sensor >/dev/null 2>&1; then
            echo "$(date) - ROTATE - WARNING: monitor-sensor missing; retrying" >&2
            sleep 5
            continue
        fi
        while read -r orientation; do
            [[ -n "${orientation}" ]] || continue
            case "${orientation}" in
                left-up|right-up|bottom-up|normal)
                    zenbook-load-status
                    if [[ "${ROTATE_LOCK}" == true ]]; then
                        echo "$(date) - ROTATE - ignored (${orientation}); rotate-lock=true"
                        continue
                    fi
                    echo "$(date) - ROTATE - ${orientation}"
                    if zenbook-keyboard-attached; then
                        KEYBOARD_ATTACHED=true
                    else
                        KEYBOARD_ATTACHED=false
                    fi
                    zenbook-rotate-displays "${orientation}"
                    MONITOR_COUNT=$(zenbook-monitor-count)
                    zenbook-set-status
                    ;;
                *)
                    echo "$(date) - ROTATE - Ignoring unknown orientation: ${orientation}"
                    ;;
            esac
        done < <(
            monitor-sensor --accel 2>/dev/null |
                stdbuf -oL grep "Accelerometer orientation changed:" |
                stdbuf -oL awk '{print $4}'
        )
        echo "$(date) - ROTATE - sensor pipeline exited; restarting" >&2
        sleep 1
    done
}
