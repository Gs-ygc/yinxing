#!/system/bin/sh

PACKAGE_NAME="com.yinxing.launcher"
ACCESSIBILITY_COMPONENT="com.yinxing.launcher/com.google.android.accessibility.selecttospeak.SelectToSpeakService"
HOME_COMPONENT="com.yinxing.launcher/.feature.home.MainActivity"
ANDROID_USER_ID="0"
STATE_DIR="${YINXING_GUARD_STATE_DIR:-/data/adb/yinxing_guard}"
LOG_TAG="YinxingGuard"
MODULE_VERSION="1.10.0-root-preview.13"
GUARD_OWNER_ACTIVE_STATUS=76
CLEANUP_TARGET="${YINXING_GUARD_TEST_CLEANUP_TARGET:-/data/adb/boot-completed.d/yinxing-guard-uninstall-cleanup.sh}"
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
    message="$1"
    if command -v log >/dev/null 2>&1; then
        log -t "$LOG_TAG" -- "version=$MODULE_VERSION $message" >/dev/null 2>&1 || true
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

process_start_time() {
    process_pid="$1"
    process_proc_root="${YINXING_GUARD_PROC_ROOT:-/proc}"
    process_stat="$(cat "$process_proc_root/$process_pid/stat" 2>/dev/null || true)"
    [ -n "$process_stat" ] || return 1
    process_start="$(printf '%s\n' "$process_stat" | awk '{ sub(/^.*\) /, ""); print $20; exit }')"
    case "$process_start" in
        ''|*[!0-9]*) return 1 ;;
        *) printf '%s\n' "$process_start" ;;
    esac
}

guard_owner_identity_state() {
    identity_lock_dir="$1"
    identity_pid="$2"
    identity_expected="$(cat "$identity_lock_dir/start_time" 2>/dev/null || true)"
    [ -n "$identity_expected" ] || {
        printf 'unknown\n'
        return 0
    }
    case "$identity_expected" in
        ''|*[!0-9]*)
            printf 'unknown\n'
            return 0
            ;;
    esac
    identity_actual="$(process_start_time "$identity_pid" 2>/dev/null || true)"
    [ -n "$identity_actual" ] || {
        printf 'unknown\n'
        return 0
    }
    if [ "$identity_expected" = "$identity_actual" ]; then
        printf 'match\n'
    else
        printf 'mismatch\n'
    fi
}

remove_accessibility_service() {
    current="$1"
    component="$2"

    case "$current" in
        null|NULL|"") current="" ;;
    esac

    printf '%s\n' "$current" | awk -v target="$component" -F: '
        {
            result = ""
            for (i = 1; i <= NF; i++) {
                if ($i == "" || $i == target) {
                    continue
                }
                if (result != "") {
                    result = result ":"
                }
                result = result $i
            }
            print result
        }
    '
}

accessibility_service_binding_state() {
    if ! accessibility_dump="$(run_guard_command dumpsys accessibility 2>/dev/null)"; then
        printf 'unknown\n'
        return 0
    fi
    if [ -z "$accessibility_dump" ]; then
        printf 'unknown\n'
        return 0
    fi

    printf '%s\n' "$accessibility_dump" | awk -v component="$ACCESSIBILITY_COMPONENT" '
        /^[[:space:]]*Bound services:/ { seen_bound = 1; section = "bound" }
        /^[[:space:]]*Enabled services:/ { section = "" }
        /^[[:space:]]*Binding services:/ { seen_binding = 1; section = "binding" }
        /^[[:space:]]*Crashed services:/ { seen_crashed = 1; section = "crashed" }
        /^[[:space:]]*Client list info:/ { section = "" }
        section != "" && index($0, component) {
            if (section == "bound") {
                bound = 1
            } else if (section == "binding") {
                binding = 1
            } else if (section == "crashed") {
                crashed = 1
            }
        }
        END {
            if (crashed) {
                print "crashed"
            } else if (binding) {
                print "binding"
            } else if (bound) {
                print "bound"
            } else if (seen_bound && seen_binding && seen_crashed) {
                print "unbound"
            } else {
                print "unknown"
            }
        }
    '
}

confirm_accessibility_service_rebind() {
    confirm_attempts="${YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS:-5}"
    case "$confirm_attempts" in
        ''|*[!0-9]*|0) confirm_attempts=5 ;;
    esac
    confirm_seconds="${YINXING_GUARD_REBIND_CONFIRM_SECONDS:-1}"
    case "$confirm_seconds" in
        ''|*[!0-9]*) confirm_seconds=1 ;;
    esac

    confirm_attempt=1
    while [ "$confirm_attempt" -le "$confirm_attempts" ]; do
        confirm_state="$(accessibility_service_binding_state)"
        case "$confirm_state" in
            bound|binding)
                log_event "accessibility_service_rebind_confirmed"
                return 0
                ;;
            unknown)
                log_event "accessibility_service_rebind_unverified"
                return 0
                ;;
            crashed|unbound)
                if [ "$confirm_attempt" -ge "$confirm_attempts" ]; then
                    log_event "accessibility_service_rebind_persisted"
                    return 1
                fi
                sleep "$confirm_seconds"
                ;;
            *)
                log_event "accessibility_service_rebind_unverified"
                return 0
                ;;
        esac
        confirm_attempt=$((confirm_attempt + 1))
    done
    return 1
}

rebind_accessibility_service() {
    current="$1"
    merged="$2"

    case ":$current:" in
        *":$ACCESSIBILITY_COMPONENT:"*) ;;
        *) return 0 ;;
    esac

    without="$(remove_accessibility_service "$current" "$ACCESSIBILITY_COMPONENT")"
    if ! run_guard_command settings --user "$ANDROID_USER_ID" put secure enabled_accessibility_services "$without"; then
        log_event "accessibility_service_rebind_remove_failed"
        return 1
    fi
    sleep 1
    if ! run_guard_command settings --user "$ANDROID_USER_ID" put secure enabled_accessibility_services "$merged"; then
        log_event "accessibility_service_rebind_restore_failed"
        return 1
    fi
    if ! run_guard_command settings --user "$ANDROID_USER_ID" put secure accessibility_enabled 1; then
        log_event "accessibility_service_rebind_enable_failed"
        return 1
    fi
    if ! confirm_accessibility_service_rebind; then
        return 1
    fi
    log_event "accessibility_service_rebound"
    return 0
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
        boot_id="$(run_guard_command getprop ro.runtime.firstboot 2>/dev/null || true)"
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
    if ! run_guard_command pm path --user "$ANDROID_USER_ID" "$PACKAGE_NAME" >/dev/null 2>&1; then
        log_event "package_missing"
        return 1
    fi

    if ! run_guard_command pm enable --user "$ANDROID_USER_ID" "$PACKAGE_NAME" >/dev/null 2>&1; then
        log_event "package_enable_failed"
        return 1
    fi
    if ! run_guard_command pm enable --user "$ANDROID_USER_ID" "$ACCESSIBILITY_COMPONENT" >/dev/null 2>&1; then
        log_event "service_enable_failed"
        return 1
    fi

    if ! current="$(run_guard_command settings --user "$ANDROID_USER_ID" get secure enabled_accessibility_services 2>/dev/null)"; then
        log_event "accessibility_services_read_failed"
        return 1
    fi
    if ! enabled="$(run_guard_command settings --user "$ANDROID_USER_ID" get secure accessibility_enabled 2>/dev/null)"; then
        log_event "accessibility_enabled_read_failed"
        return 1
    fi

    target_was_enabled=0
    case ":$current:" in
        *":$ACCESSIBILITY_COMPONENT:"*) target_was_enabled=1 ;;
    esac
    if [ "$target_was_enabled" -eq 1 ] && [ "$enabled" = "1" ]; then
        target_was_fully_enabled=1
    else
        target_was_fully_enabled=0
    fi

    merged="$(merge_accessibility_services "$current" "$ACCESSIBILITY_COMPONENT")"
    accessibility_changed=0
    if [ "$merged" != "$current" ]; then
        run_guard_command settings --user "$ANDROID_USER_ID" put secure enabled_accessibility_services "$merged" || {
            log_event "accessibility_services_write_failed"
            return 1
        }
        accessibility_changed=1
    fi

    if [ "$enabled" != "1" ]; then
        run_guard_command settings --user "$ANDROID_USER_ID" put secure accessibility_enabled 1 || {
            log_event "accessibility_enabled_write_failed"
            return 1
        }
        accessibility_changed=1
    fi

    if [ "$accessibility_changed" -eq 1 ]; then
        log_event "accessibility_repaired"
    fi

    binding_state="$(accessibility_service_binding_state)"
    case "$binding_state" in
        crashed)
            rebind_accessibility_service "$current" "$merged" || return 1
            ;;
        unbound)
            if [ "$target_was_fully_enabled" -eq 1 ]; then
                rebind_accessibility_service "$current" "$merged" || return 1
            fi
            ;;
    esac
    return 0
}

doze_contains_package() {
    if ! output="$(run_guard_command cmd deviceidle whitelist 2>/dev/null)"; then
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
        elif run_guard_command cmd deviceidle whitelist "+$PACKAGE_NAME" >/dev/null 2>&1; then
            marker_tmp="$STATE_DIR/doze_added_by_module.tmp.$$"
            rm -f "$marker_tmp"
            if ! printf 'added\n' > "$marker_tmp" 2>/dev/null || \
                ! mv -f "$marker_tmp" "$STATE_DIR/doze_added_by_module" 2>/dev/null; then
                rm -f "$marker_tmp"
                log_event "doze_marker_write_failed"
                run_guard_command cmd deviceidle whitelist "-$PACKAGE_NAME" >/dev/null 2>&1 || \
                    log_event "doze_rollback_failed"
            fi
        else
            log_event "doze_whitelist_failed"
        fi
    fi

    run_guard_command cmd appops set --user "$ANDROID_USER_ID" "$PACKAGE_NAME" RUN_IN_BACKGROUND allow \
        >/dev/null 2>&1 || log_event "background_appop_unsupported"
    run_guard_command cmd appops set --user "$ANDROID_USER_ID" "$PACKAGE_NAME" RUN_ANY_IN_BACKGROUND allow \
        >/dev/null 2>&1 || log_event "any_background_appop_unsupported"
    return 0
}

repair_state() {
    repair_accessibility || return 1
    repair_keepalive
    return 0
}

launch_home() {
    run_guard_command am start --user "$ANDROID_USER_ID" -n "$HOME_COMPONENT" >/dev/null 2>&1 || {
        log_event "home_launch_failed"
        return 1
    }
    log_event "home_launched"
    return 0
}
