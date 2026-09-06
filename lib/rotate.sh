#!/bin/bash
# Accelerometer orientation watcher (in-process; no full script re-exec).

# shellcheck disable=SC2016
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
                    if zenbook-keyboard-attached; then
                        echo "$(date) - ROTATE - ignored (${orientation}); keyboard is docked"
                        continue
                    fi
                    # Debounce to filter out mechanical jolts during magnetic keyboard attach/detach
                    sleep 0.35
                    if zenbook-keyboard-attached; then
                        echo "$(date) - ROTATE - ignored (${orientation}); keyboard docked during debounce"
                        continue
                    fi
                    echo "$(date) - ROTATE - ${orientation}"
                    KEYBOARD_ATTACHED=false
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
