#!/system/bin/sh

MODDIR=${0%/*}
CLEANUP_SOURCE="$MODDIR/uninstall-cleanup.sh"
. "$MODDIR/common.sh"

BOOT_WAIT_SECONDS=${YINXING_GUARD_BOOT_WAIT_SECONDS:-5}
BOOT_WAIT_MAX_CYCLES=${YINXING_GUARD_BOOT_WAIT_MAX_CYCLES:-0}
HEALTH_INTERVAL_SECONDS=${YINXING_GUARD_INTERVAL_SECONDS:-60}
MAX_CYCLES=${YINXING_GUARD_MAX_CYCLES:-0}
BOOT_ID_FILE=${YINXING_GUARD_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}
LOCK_ATTEMPTS=${YINXING_GUARD_LOCK_ATTEMPTS:-5}

number_or_default() {
    value="$1"
    fallback="$2"
    case "$value" in
        ''|*[!0-9]*) printf '%s\n' "$fallback" ;;
        *) printf '%s\n' "$value" ;;
    esac
}

BOOT_WAIT_SECONDS="$(number_or_default "$BOOT_WAIT_SECONDS" 5)"
BOOT_WAIT_MAX_CYCLES="$(number_or_default "$BOOT_WAIT_MAX_CYCLES" 0)"
HEALTH_INTERVAL_SECONDS="$(number_or_default "$HEALTH_INTERVAL_SECONDS" 60)"
MAX_CYCLES="$(number_or_default "$MAX_CYCLES" 0)"
LOCK_ATTEMPTS="$(number_or_default "$LOCK_ATTEMPTS" 5)"
[ "$LOCK_ATTEMPTS" -gt 0 ] || LOCK_ATTEMPTS=5

read_boot_id() {
    read_boot_id_from "$BOOT_ID_FILE"
}

CURRENT_BOOT_ID="$(read_boot_id)"
LOCK_BOOT_ID="$(sanitize_boot_id "$CURRENT_BOOT_ID")"
LOCK_ROOT="$STATE_DIR/guard.lock"
LOCK_DIR="$LOCK_ROOT/$LOCK_BOOT_ID"
PID_FILE="$LOCK_DIR/pid"
BOOT_MARKER_FILE="$LOCK_DIR/boot_id"
START_TIME_FILE="$LOCK_DIR/start_time"
RECLAIM_DIR="$LOCK_DIR/reclaim"
RECLAIM_PID_FILE="$RECLAIM_DIR/pid"
LOCK_RETRYABLE=0
LOCK_OWNER_ACTIVE=0

release_lock() {
    if [ -f "$PID_FILE" ] && [ "$(cat "$PID_FILE" 2>/dev/null)" = "$$" ]; then
        rm -f "$PID_FILE" "$BOOT_MARKER_FILE" "$START_TIME_FILE"
        rmdir "$LOCK_DIR" 2>/dev/null || true
        rmdir "$LOCK_ROOT" 2>/dev/null || true
    fi
}

acquire_lock() {
    if ! mkdir -p "$LOCK_ROOT" 2>/dev/null; then
        log_event "guard_lock_root_failed"
        return 1
    fi
    attempts=0
    while [ "$attempts" -lt "$LOCK_ATTEMPTS" ]; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            if ! printf '%s\n' "$CURRENT_BOOT_ID" > "$BOOT_MARKER_FILE"; then
                rm -f "$PID_FILE" "$BOOT_MARKER_FILE" "$START_TIME_FILE"
                rmdir "$LOCK_DIR" 2>/dev/null || true
                rmdir "$LOCK_ROOT" 2>/dev/null || true
                log_event "guard_lock_write_failed"
                return 1
            fi
            owner_start_time="$(process_start_time "$$" 2>/dev/null || true)"
            if [ -n "$owner_start_time" ] && \
                ! printf '%s\n' "$owner_start_time" > "$START_TIME_FILE"; then
                rm -f "$PID_FILE" "$BOOT_MARKER_FILE" "$START_TIME_FILE"
                rmdir "$LOCK_DIR" 2>/dev/null || true
                rmdir "$LOCK_ROOT" 2>/dev/null || true
                log_event "guard_lock_write_failed"
                return 1
            fi
            if ! printf '%s\n' "$$" > "$PID_FILE"; then
                rm -f "$PID_FILE" "$BOOT_MARKER_FILE" "$START_TIME_FILE"
                rmdir "$LOCK_DIR" 2>/dev/null || true
                rmdir "$LOCK_ROOT" 2>/dev/null || true
                log_event "guard_lock_write_failed"
                return 1
            fi
            return 0
        fi

        reclaim_pid="$(cat "$RECLAIM_PID_FILE" 2>/dev/null || true)"
        case "$reclaim_pid" in
            ''|*[!0-9]*) ;;
            *)
                if kill -0 "$reclaim_pid" 2>/dev/null; then
                    attempts=$((attempts + 1))
                    sleep 1
                    continue
                fi
                rm -rf "$RECLAIM_DIR"
                ;;
        esac

        previous_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        case "$previous_pid" in
            ''|*[!0-9]*)
                # The owner may have created the directory but not written its PID yet.
                LOCK_RETRYABLE=1
                attempts=$((attempts + 1))
                sleep 1
                continue
                ;;
            *)
                if kill -0 "$previous_pid" 2>/dev/null; then
                    identity_state="$(guard_owner_identity_state "$LOCK_DIR" "$previous_pid")"
                    case "$identity_state" in
                        mismatch)
                            ;;
                        match|unknown)
                            LOCK_RETRYABLE=0
                            LOCK_OWNER_ACTIVE=1
                            log_event "guard_already_running"
                            return 1
                            ;;
                    esac
                fi
                ;;
        esac

        if mkdir "$RECLAIM_DIR" 2>/dev/null; then
            if ! printf '%s\n' "$$" > "$RECLAIM_PID_FILE" 2>/dev/null; then
                rm -rf "$RECLAIM_DIR"
                log_event "guard_reclaim_lock_write_failed"
                return 1
            fi
            checked_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
            case "$checked_pid" in
                ''|*[!0-9]*)
                    rm -rf "$RECLAIM_DIR"
                    LOCK_RETRYABLE=1
                    attempts=$((attempts + 1))
                    sleep 1
                    continue
                    ;;
                *)
                    if kill -0 "$checked_pid" 2>/dev/null; then
                        checked_identity="$(guard_owner_identity_state "$LOCK_DIR" "$checked_pid")"
                        case "$checked_identity" in
                            mismatch)
                                ;;
                            match|unknown)
                                rm -rf "$RECLAIM_DIR"
                                LOCK_RETRYABLE=0
                                LOCK_OWNER_ACTIVE=1
                                log_event "guard_already_running"
                                return 1
                                ;;
                        esac
                    fi
                    rm -rf "$LOCK_DIR"
                    attempts=$((attempts + 1))
                    continue
                    ;;
            esac
        fi

        attempts=$((attempts + 1))
        sleep 1
    done

    if [ "$LOCK_RETRYABLE" -eq 1 ]; then
        log_event "guard_lock_incomplete_retry"
        return 75
    fi
    log_event "guard_lock_busy"
    return 1
}

wait_for_boot() {
    attempts=0
    while [ "$(run_guard_command getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
        if [ "$BOOT_WAIT_MAX_CYCLES" -gt 0 ] && [ "$attempts" -ge "$BOOT_WAIT_MAX_CYCLES" ]; then
            log_event "boot_wait_timeout"
            return 1
        fi
        sleep "$BOOT_WAIT_SECONDS"
        attempts=$((attempts + 1))
    done
    return 0
}

run_health_cycle() {
    if ! module_is_active; then
        log_event "guard_module_inactive"
        return 2
    fi
    if ! cleanup_helper_ready "$CLEANUP_SOURCE"; then
        if ! install_cleanup_helper "$CLEANUP_SOURCE" || \
            ! cleanup_helper_ready "$CLEANUP_SOURCE"; then
            record_repair_result failed || true
            log_event "uninstall_cleanup_unavailable"
            return 1
        fi
    fi
    if ! repair_state; then
        record_repair_result failed || true
        log_event "repair_cycle_failed"
        return 1
    fi
    record_repair_result ok || true
    if [ "$HOME_LAUNCHED" -eq 0 ] && launch_home; then
        HOME_LAUNCHED=1
    fi
    return 0
}

module_is_active || exit 0
ensure_state_dir || exit 1
if ! acquire_lock; then
    # Keep an incomplete lock intact and let service.sh retry after its writer
    # has had time to finish publishing the owner PID.
    [ "$LOCK_RETRYABLE" -eq 1 ] && exit 75
    [ "$LOCK_OWNER_ACTIVE" -eq 1 ] && exit "$GUARD_OWNER_ACTIVE_STATUS"
    exit 0
fi
trap release_lock EXIT
trap 'exit 143' INT TERM

wait_for_boot || exit 1
module_is_active || exit 0
HOME_LAUNCHED=0
run_health_cycle

cycles=0
while [ "$MAX_CYCLES" -eq 0 ] || [ "$cycles" -lt "$MAX_CYCLES" ]; do
    sleep "$HEALTH_INTERVAL_SECONDS"
    module_is_active || break
    run_health_cycle
    cycles=$((cycles + 1))
done
