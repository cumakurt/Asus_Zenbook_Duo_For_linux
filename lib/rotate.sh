#!/bin/bash
# Accelerometer orientation watcher (in-process; no full script re-exec).

# shellcheck disable=SC2016
function zenbook-watch-rotate() {
    local orientation="" pending="" next_orient
    echo "$(date) - ROTATE - Watching"
    while true; do
        if ! command -v monitor-sensor >/dev/null 2>&1; then
            echo "$(date) - ROTATE - WARNING: monitor-sensor missing; retrying" >&2
            sleep 5
            continue
        fi
        pending=""
        while true; do
            if [[ -z "${pending}" ]]; then
                if ! read -r orientation; then
                    break
                fi
                case "${orientation}" in
                    left-up|right-up|bottom-up|normal)
                        pending="${orientation}"
                        ;;
                    *)
                        echo "$(date) - ROTATE - Ignoring unknown orientation: ${orientation}"
                        continue
                        ;;
                esac
            fi

            # Quiet window: absorb transitional events, keep the latest.
            while read -r -t 0.35 next_orient; do
                case "${next_orient}" in
                    left-up|right-up|bottom-up|normal)
                        pending="${next_orient}"
                        ;;
                esac
            done

            orientation="${pending}"
            pending=""

            zenbook-load-status
            if [[ "${ROTATE_LOCK}" == true ]]; then
                echo "$(date) - ROTATE - ignored (${orientation}); rotate-lock=true"
                continue
            fi
            if zenbook-keyboard-attached; then
                echo "$(date) - ROTATE - ignored (${orientation}); keyboard is docked"
                continue
            fi

            echo "$(date) - ROTATE - ${orientation}"
            KEYBOARD_ATTACHED=false
            zenbook-rotate-displays "${orientation}"
            MONITOR_COUNT=$(zenbook-monitor-count)
            zenbook-set-status

            # Fold events that queued during the slow layout apply.
            while read -r -t 0.05 next_orient; do
                case "${next_orient}" in
                    left-up|right-up|bottom-up|normal)
                        pending="${next_orient}"
                        ;;
                esac
            done
        done < <(
            monitor-sensor --accel 2>/dev/null |
                stdbuf -oL grep "Accelerometer orientation changed:" |
                stdbuf -oL awk '{print $4}'
        )
        echo "$(date) - ROTATE - sensor pipeline exited; restarting" >&2
        sleep 1
    done
}
