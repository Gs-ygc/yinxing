#!/system/bin/sh

PACKAGE_NAME="com.yinxing.launcher"
ACCESSIBILITY_COMPONENT="com.yinxing.launcher/com.google.android.accessibility.selecttospeak.SelectToSpeakService"
HOME_COMPONENT="com.yinxing.launcher/.feature.home.MainActivity"
ANDROID_USER_ID="0"
STATE_DIR="${YINXING_GUARD_STATE_DIR:-/data/adb/yinxing_guard}"
LOG_TAG="YinxingGuard"
MODULE_VERSION="1.10.0-root-preview.1"
CLEANUP_TARGET="${YINXING_GUARD_TEST_CLEANUP_TARGET:-/data/adb/boot-completed.d/yinxing-guard-uninstall-cleanup.sh}"

log_event() {
    message="$1"
    if command -v log >/dev/null 2>&1; then
        log -t "$LOG_TAG" -- "version=$MODULE_VERSION $message" 2>/dev/null || true
    fi
}

merge_accessibility_services() {
    current="$1"
    component="$2"

    case "$current" in
        null|NULL|"") current="" ;;
        *[![:space:]]*) ;;
        *) current="" ;;
    esac

    case ":$current:" in
        *":$component:"*)
            printf '%s\n' "$current"
            ;;
        "::")
            printf '%s\n' "$component"
            ;;
        *)
            printf '%s:%s\n' "$current" "$component"
            ;;
    esac
}

ensure_state_dir() {
    mkdir -p "$STATE_DIR" 2>/dev/null || {
        log_event "state_dir_unavailable"
        return 1
    }
}

read_boot_id_from() {
    boot_id_file="$1"
    boot_id="$(cat "$boot_id_file" 2>/dev/null || true)"
    if [ -z "$boot_id" ]; then
        boot_id="$(awk '/^btime / { print $2; exit }' /proc/stat 2>/dev/null || true)"
    fi
    if [ -z "$boot_id" ]; then
        boot_id="$(getprop ro.runtime.firstboot 2>/dev/null || true)"
    fi
    [ -n "$boot_id" ] || boot_id="unknown"
    printf '%s\n' "$boot_id"
}

sanitize_boot_id() {
    sanitized="$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"
    [ -n "$sanitized" ] || sanitized="unknown"
    printf '%s\n' "$sanitized"
}

record_repair_result() {
    result="$1"
    case "$result" in
        ok|failed) ;;
        *)
            log_event "repair_result_invalid"
            return 1
            ;;
    esac
    ensure_state_dir || return 1
    temp_path="$STATE_DIR/last_repair.tmp.$$"
    rm -f "$temp_path"
    if ! printf '%s\n' "$result" > "$temp_path" 2>/dev/null || \
        ! chmod 0600 "$temp_path" 2>/dev/null || \
        ! mv -f "$temp_path" "$STATE_DIR/last_repair" 2>/dev/null; then
        rm -f "$temp_path"
        log_event "repair_result_write_failed"
        return 1
    fi
    return 0
}

install_cleanup_helper() {
    source_path="$1"
    cleanup_dir=${CLEANUP_TARGET%/*}
    temp_path="$CLEANUP_TARGET.tmp.$$"

    if [ -d "$CLEANUP_TARGET" ]; then
        log_event "uninstall_cleanup_target_is_directory"
        return 1
    fi
    if ! mkdir -p "$cleanup_dir" 2>/dev/null; then
        log_event "uninstall_cleanup_dir_failed"
        return 1
    fi
    rm -f "$temp_path"
    if ! cp "$source_path" "$temp_path" 2>/dev/null || \
        ! chmod 0755 "$temp_path" 2>/dev/null || \
        ! mv -f "$temp_path" "$CLEANUP_TARGET" 2>/dev/null; then
        rm -f "$temp_path"
        log_event "uninstall_cleanup_schedule_failed"
        return 1
    fi
    return 0
}

repair_accessibility() {
    if ! pm path --user "$ANDROID_USER_ID" "$PACKAGE_NAME" >/dev/null 2>&1; then
        log_event "package_missing"
        return 1
    fi

    pm enable --user "$ANDROID_USER_ID" "$PACKAGE_NAME" >/dev/null 2>&1 || \
        log_event "package_enable_failed"
    pm enable --user "$ANDROID_USER_ID" "$ACCESSIBILITY_COMPONENT" >/dev/null 2>&1 || \
        log_event "service_enable_failed"

    if ! current="$(settings --user "$ANDROID_USER_ID" get secure enabled_accessibility_services 2>/dev/null)"; then
        log_event "accessibility_services_read_failed"
        return 1
    fi
    if ! enabled="$(settings --user "$ANDROID_USER_ID" get secure accessibility_enabled 2>/dev/null)"; then
        log_event "accessibility_enabled_read_failed"
        return 1
    fi

    merged="$(merge_accessibility_services "$current" "$ACCESSIBILITY_COMPONENT")"
    accessibility_changed=0
    if [ "$merged" != "$current" ]; then
        settings --user "$ANDROID_USER_ID" put secure enabled_accessibility_services "$merged" || {
            log_event "accessibility_services_write_failed"
            return 1
        }
        accessibility_changed=1
    fi

    if [ "$enabled" != "1" ]; then
        settings --user "$ANDROID_USER_ID" put secure accessibility_enabled 1 || {
            log_event "accessibility_enabled_write_failed"
            return 1
        }
        accessibility_changed=1
    fi

    if [ "$accessibility_changed" -eq 1 ]; then
        log_event "accessibility_repaired"
    fi
    return 0
}

doze_contains_package() {
    if ! output="$(cmd deviceidle whitelist 2>/dev/null)"; then
        log_event "doze_whitelist_read_failed"
        return 2
    fi
    printf '%s\n' "$output" | tr ',[:space:]' '\n' | grep -Fx "$PACKAGE_NAME" >/dev/null 2>&1
}

repair_keepalive() {
    state_ready=1
    if ! ensure_state_dir; then
        state_ready=0
    fi

    doze_contains_package
    doze_status=$?
    if [ "$doze_status" -eq 1 ]; then
        if [ "$state_ready" -ne 1 ]; then
            log_event "doze_whitelist_skipped_no_state"
        elif [ ! -f "$CLEANUP_TARGET" ] || [ ! -x "$CLEANUP_TARGET" ]; then
            log_event "doze_whitelist_skipped_no_cleanup"
        elif cmd deviceidle whitelist "+$PACKAGE_NAME" >/dev/null 2>&1; then
            marker_tmp="$STATE_DIR/doze_added_by_module.tmp.$$"
            rm -f "$marker_tmp"
            if ! printf 'added\n' > "$marker_tmp" 2>/dev/null || \
                ! mv -f "$marker_tmp" "$STATE_DIR/doze_added_by_module" 2>/dev/null; then
                rm -f "$marker_tmp"
                log_event "doze_marker_write_failed"
                cmd deviceidle whitelist "-$PACKAGE_NAME" >/dev/null 2>&1 || \
                    log_event "doze_rollback_failed"
            fi
        else
            log_event "doze_whitelist_failed"
        fi
    fi

    cmd appops set --user "$ANDROID_USER_ID" "$PACKAGE_NAME" RUN_IN_BACKGROUND allow \
        >/dev/null 2>&1 || log_event "background_appop_unsupported"
    cmd appops set --user "$ANDROID_USER_ID" "$PACKAGE_NAME" RUN_ANY_IN_BACKGROUND allow \
        >/dev/null 2>&1 || log_event "any_background_appop_unsupported"
    return 0
}

repair_state() {
    repair_accessibility || return 1
    repair_keepalive
    return 0
}

launch_home() {
    am start --user "$ANDROID_USER_ID" -n "$HOME_COMPONENT" >/dev/null 2>&1 || {
        log_event "home_launch_failed"
        return 1
    }
    log_event "home_launched"
    return 0
}
