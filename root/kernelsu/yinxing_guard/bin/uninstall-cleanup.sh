#!/system/bin/sh

PACKAGE_NAME="com.yinxing.launcher"
HOME_ROLE_NAME="android.app.role.HOME"
ANDROID_USER_ID="0"
STATE_DIR="${YINXING_GUARD_STATE_DIR:-/data/adb/yinxing_guard}"
LOG_TAG="YinxingGuard"
MODULE_VERSION="1.10.0-root-preview.13"
MARKER="$STATE_DIR/doze_added_by_module"
HOME_MARKER="$STATE_DIR/home_previous_holder"
SELF_PATH="$0"
MODULE_DIR="${YINXING_GUARD_TEST_MODULE_DIR:-/data/adb/modules/yinxing_guard}"
GUARD_COMMAND_TIMEOUT_SECONDS="${YINXING_GUARD_COMMAND_TIMEOUT_SECONDS:-2}"
case "$GUARD_COMMAND_TIMEOUT_SECONDS" in
    ''|*[!0-9]*) GUARD_COMMAND_TIMEOUT_SECONDS=2 ;;
esac
if ! [ "$GUARD_COMMAND_TIMEOUT_SECONDS" -gt 0 ] 2>/dev/null; then
    GUARD_COMMAND_TIMEOUT_SECONDS=2
fi
GUARD_BUSYBOX_BIN="${YINXING_GUARD_BUSYBOX_BIN:-/data/adb/ksu/bin/busybox}"
if [ ! -x "$GUARD_BUSYBOX_BIN" ]; then
    GUARD_BUSYBOX_BIN="$(command -v busybox 2>/dev/null || true)"
fi

run_guard_command() {
    [ -n "$GUARD_BUSYBOX_BIN" ] || return 127

    "$GUARD_BUSYBOX_BIN" setsid \
        "$GUARD_BUSYBOX_BIN" sh -c '
            guard_busybox_bin=$1
            guard_timeout_seconds=$2
            shift 2
            "$guard_busybox_bin" timeout -k 1 "$guard_timeout_seconds" "$@"
            guard_command_status=$?
            if [ "$guard_command_status" -ne 0 ]; then
                "$guard_busybox_bin" kill -KILL "-$$" >/dev/null 2>&1 || true
            fi
            exit "$guard_command_status"
        ' yinxing-guard-command "$GUARD_BUSYBOX_BIN" "$GUARD_COMMAND_TIMEOUT_SECONDS" "$@"
}

log_event() {
    if command -v log >/dev/null 2>&1; then
        log -t "$LOG_TAG" -- "version=$MODULE_VERSION $1" >/dev/null 2>&1 || true
    fi
}

cleanup_runtime_state() {
    rm -f \
        "$STATE_DIR/guard.pid" \
        "$STATE_DIR/guard.boot_id" \
        "$STATE_DIR/last_repair" \
        "$STATE_DIR/last_repair.tmp."* \
        "$STATE_DIR/doze_added_by_module.tmp."* \
        "$STATE_DIR/home_previous_holder.tmp."*
    rm -rf "$STATE_DIR/guard.lock"
    rmdir "$STATE_DIR" 2>/dev/null || true
}

valid_home_holder() {
    case "$1" in
        ''|none|.*|*.|*..*|*[!A-Za-z0-9_.]*) return 1 ;;
        *.*) [ "$1" != "$PACKAGE_NAME" ] ;;
        *) return 1 ;;
    esac
}

read_home_role_holder() {
    if ! home_output="$(run_guard_command cmd role get-role-holders \
        --user "$ANDROID_USER_ID" "$HOME_ROLE_NAME" 2>/dev/null)"; then
        return 1
    fi
    if [ -z "$home_output" ]; then
        printf 'none\n'
        return 0
    fi
    case "$home_output" in
        *[!A-Za-z0-9_.]*|.*|*.|*..*) return 1 ;;
    esac
    case "$home_output" in
        *.*) printf '%s\n' "$home_output" ;;
        *) return 1 ;;
    esac
}

cleanup_home_role() {
    if [ -L "$HOME_MARKER" ]; then
        log_event "uninstall_home_marker_invalid"
        return 1
    fi
    [ -e "$HOME_MARKER" ] || return 0
    if [ ! -f "$HOME_MARKER" ]; then
        log_event "uninstall_home_marker_invalid"
        return 1
    fi

    previous_home="$(cat "$HOME_MARKER" 2>/dev/null || true)"
    if [ "$previous_home" != "none" ] && ! valid_home_holder "$previous_home"; then
        log_event "uninstall_home_marker_invalid"
        return 1
    fi
    if ! current_home="$(read_home_role_holder)"; then
        log_event "uninstall_home_query_failed"
        return 1
    fi

    if [ "$current_home" != "$PACKAGE_NAME" ]; then
        rm -f "$HOME_MARKER" || return 1
        log_event "uninstall_home_preserved_new_choice"
        return 0
    fi

    if [ "$previous_home" = "none" ]; then
        if ! run_guard_command cmd role remove-role-holder --user "$ANDROID_USER_ID" \
            "$HOME_ROLE_NAME" "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_event "uninstall_home_remove_failed"
            return 1
        fi
        if ! confirmed_home="$(read_home_role_holder)" || \
            [ "$confirmed_home" = "$PACKAGE_NAME" ]; then
            log_event "uninstall_home_remove_unconfirmed"
            return 1
        fi
    else
        if ! run_guard_command pm path --user "$ANDROID_USER_ID" "$previous_home" \
            >/dev/null 2>&1; then
            log_event "uninstall_home_previous_missing"
            return 1
        fi
        if ! run_guard_command cmd package set-home-activity --user "$ANDROID_USER_ID" \
            "$previous_home" >/dev/null 2>&1; then
            log_event "uninstall_home_restore_failed"
            return 1
        fi
        if ! confirmed_home="$(read_home_role_holder)" || \
            [ "$confirmed_home" != "$previous_home" ]; then
            log_event "uninstall_home_restore_unconfirmed"
            return 1
        fi
    fi

    rm -f "$HOME_MARKER" || return 1
    log_event "uninstall_home_cleanup_complete"
    return 0
}

cleanup_doze() {
    [ -e "$MARKER" ] || return 0
    if [ ! -f "$MARKER" ] || [ "$(cat "$MARKER" 2>/dev/null)" != "added" ]; then
        log_event "uninstall_marker_invalid"
        return 1
    fi
    if ! run_guard_command cmd deviceidle whitelist "-$PACKAGE_NAME" >/dev/null 2>&1; then
        log_event "uninstall_doze_cleanup_deferred"
        return 1
    fi
    rm -f "$MARKER" || return 1
    log_event "uninstall_doze_cleanup_complete"
    return 0
}

if [ -d "$MODULE_DIR" ] && [ ! -f "$MODULE_DIR/remove" ]; then
    exit 0
fi

cleanup_failed=0
cleanup_home_role || cleanup_failed=1
cleanup_doze || cleanup_failed=1

if [ "$cleanup_failed" -ne 0 ] || [ -e "$HOME_MARKER" ] || [ -e "$MARKER" ]; then
    exit 1
fi

cleanup_runtime_state
log_event "uninstall_cleanup_complete"
rm -f "$SELF_PATH"
exit 0
