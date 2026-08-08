#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/common.sh"

BOOT_WAIT_SECONDS=${YINXING_GUARD_BOOT_WAIT_SECONDS:-5}
BOOT_WAIT_MAX_CYCLES=${YINXING_GUARD_BOOT_WAIT_MAX_CYCLES:-120}
HEALTH_INTERVAL_SECONDS=${YINXING_GUARD_INTERVAL_SECONDS:-60}
MAX_CYCLES=${YINXING_GUARD_MAX_CYCLES:-0}
PID_FILE="$STATE_DIR/guard.pid"
BOOT_MARKER_FILE="$STATE_DIR/guard.boot_id"
BOOT_ID_FILE=${YINXING_GUARD_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}

number_or_default() {
    value="$1"
    fallback="$2"
    case "$value" in
        ''|*[!0-9]*) printf '%s\n' "$fallback" ;;
        *) printf '%s\n' "$value" ;;
    esac
}

BOOT_WAIT_SECONDS="$(number_or_default "$BOOT_WAIT_SECONDS" 5)"
BOOT_WAIT_MAX_CYCLES="$(number_or_default "$BOOT_WAIT_MAX_CYCLES" 120)"
HEALTH_INTERVAL_SECONDS="$(number_or_default "$HEALTH_INTERVAL_SECONDS" 60)"
MAX_CYCLES="$(number_or_default "$MAX_CYCLES" 0)"

read_boot_id() {
    boot_id="$(cat "$BOOT_ID_FILE" 2>/dev/null || true)"
    if [ -z "$boot_id" ]; then
        boot_id="$(awk '/^btime / { print $2; exit }' /proc/stat 2>/dev/null || true)"
    fi
    if [ -z "$boot_id" ]; then
        boot_id="$(getprop ro.runtime.firstboot 2>/dev/null || true)"
    fi
    [ -n "$boot_id" ] || boot_id="unknown"
    printf '%s\n' "$boot_id"
}

CURRENT_BOOT_ID="$(read_boot_id)"

release_lock() {
    if [ -f "$PID_FILE" ] && [ "$(cat "$PID_FILE" 2>/dev/null)" = "$$" ]; then
        rm -f "$PID_FILE" "$BOOT_MARKER_FILE"
    fi
}

acquire_lock() {
    if [ -f "$PID_FILE" ]; then
        previous_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        previous_boot_id="$(cat "$BOOT_MARKER_FILE" 2>/dev/null || true)"
        case "$previous_pid" in
            ''|*[!0-9]*) ;;
            *)
                if [ "$previous_boot_id" = "$CURRENT_BOOT_ID" ] && \
                    kill -0 "$previous_pid" 2>/dev/null; then
                    log_event "guard_already_running"
                    return 1
                fi
                ;;
        esac
    fi

    printf '%s\n' "$CURRENT_BOOT_ID" > "$BOOT_MARKER_FILE" || {
        log_event "guard_boot_marker_write_failed"
        return 1
    }
    printf '%s\n' "$$" > "$PID_FILE" || {
        log_event "guard_pid_write_failed"
        rm -f "$BOOT_MARKER_FILE"
        return 1
    }
    return 0
}

wait_for_boot() {
    attempts=0
    while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
        if [ "$attempts" -ge "$BOOT_WAIT_MAX_CYCLES" ]; then
            log_event "boot_wait_timeout"
            return 1
        fi
        sleep "$BOOT_WAIT_SECONDS"
        attempts=$((attempts + 1))
    done
    return 0
}

run_health_cycle() {
    if ! repair_state; then
        log_event "repair_cycle_failed"
    fi
}

ensure_state_dir || exit 1
acquire_lock || exit 0
trap release_lock EXIT INT TERM

wait_for_boot || exit 1
run_health_cycle
launch_home || true

cycles=0
while [ "$MAX_CYCLES" -eq 0 ] || [ "$cycles" -lt "$MAX_CYCLES" ]; do
    sleep "$HEALTH_INTERVAL_SECONDS"
    run_health_cycle
    cycles=$((cycles + 1))
done
