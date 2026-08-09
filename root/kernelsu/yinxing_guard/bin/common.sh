#!/system/bin/sh

PACKAGE_NAME="com.yinxing.launcher"
ACCESSIBILITY_COMPONENT="com.yinxing.launcher/com.google.android.accessibility.selecttospeak.SelectToSpeakService"
HOME_COMPONENT="com.yinxing.launcher/.feature.home.MainActivity"
HOME_ROLE_NAME="android.app.role.HOME"
ANDROID_USER_ID="0"
STATE_DIR="${YINXING_GUARD_STATE_DIR:-/data/adb/yinxing_guard}"
HOME_PREVIOUS_HOLDER_MARKER="$STATE_DIR/home_previous_holder"
HOME_TAKEOVER_STATE_MARKER="$STATE_DIR/home_takeover_state"
HOME_TRANSACTION_LOCK_DIR="$STATE_DIR/home_transaction.lock"
HOME_TRANSACTION_RECLAIM_DIR="$STATE_DIR/home_transaction.reclaim"
ACCESSIBILITY_TRANSACTION_MARKER="$STATE_DIR/accessibility_transaction"
DOZE_OWNERSHIP_MARKER="$STATE_DIR/doze_added_by_module"
MODULE_STATE_DIR="${YINXING_GUARD_MODULE_STATE_DIR:-/data/adb/modules/yinxing_guard}"
LOG_TAG="YinxingGuard"
MODULE_VERSION="1.10.0-root-preview.14"
GUARD_OWNER_ACTIVE_STATUS=76
CLEANUP_TARGET="${YINXING_GUARD_TEST_CLEANUP_TARGET:-/data/adb/boot-completed.d/yinxing-guard-uninstall-cleanup.sh}"
GUARD_COMMAND_TIMEOUT_SECONDS="${YINXING_GUARD_COMMAND_TIMEOUT_SECONDS:-2}"
HOME_MARKER_LINK_COMMAND="${YINXING_GUARD_HOME_MARKER_LINK_COMMAND:-ln}"
HOME_MARKER_SYNC_COMMAND="${YINXING_GUARD_HOME_MARKER_SYNC_COMMAND:-sync}"
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

module_is_active() {
    [ -d "$MODULE_STATE_DIR" ] && \
        [ ! -e "$MODULE_STATE_DIR/disable" ] && \
        [ ! -e "$MODULE_STATE_DIR/remove" ]
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
        if ! module_is_active; then
            log_event "accessibility_service_rebind_module_inactive"
            return 1
        fi
        confirm_state="$(accessibility_service_binding_state)"
        if ! module_is_active; then
            log_event "accessibility_service_rebind_module_inactive"
            return 1
        fi
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
                module_is_active || return 1
                sleep "$confirm_seconds"
                module_is_active || return 1
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

valid_accessibility_services_snapshot() {
    services_snapshot="$1"
    [ "${#services_snapshot}" -le 8192 ] || return 1
    line_feed='
'
    case "$services_snapshot" in
        *'|'*|*"$line_feed"*) return 1 ;;
    esac
    return 0
}

parse_accessibility_transaction_state() {
    accessibility_transaction_state="$1"
    case "$accessibility_transaction_state" in
        pending\|*\|*\|*\|*\|*) ;;
        *) return 1 ;;
    esac
    accessibility_transaction_remainder=${accessibility_transaction_state#pending|}
    accessibility_original_enabled=${accessibility_transaction_remainder%%|*}
    accessibility_transaction_remainder=${accessibility_transaction_remainder#*|}
    accessibility_temporary_enabled=${accessibility_transaction_remainder%%|*}
    accessibility_transaction_remainder=${accessibility_transaction_remainder#*|}
    accessibility_original_services=${accessibility_transaction_remainder%%|*}
    accessibility_transaction_remainder=${accessibility_transaction_remainder#*|}
    accessibility_primary_services=${accessibility_transaction_remainder%%|*}
    accessibility_alternate_services=${accessibility_transaction_remainder#*|}
    case "$accessibility_alternate_services" in
        *'|'*) return 1 ;;
    esac
    case "$accessibility_original_enabled:$accessibility_temporary_enabled" in
        0:1|1:1) ;;
        *) return 1 ;;
    esac
    valid_accessibility_services_snapshot "$accessibility_original_services" || \
        return 1
    case "$accessibility_original_services" in
        null|NULL) return 1 ;;
        ""|*[![:space:]]*) ;;
        *) return 1 ;;
    esac
    valid_accessibility_services_snapshot "$accessibility_primary_services" || \
        return 1
    valid_accessibility_services_snapshot "$accessibility_alternate_services" || \
        return 1
    case "$accessibility_alternate_services" in
        null|NULL) return 1 ;;
    esac
    expected_primary_services="$(merge_accessibility_services \
        "$accessibility_original_services" "$ACCESSIBILITY_COMPONENT")"
    [ "$expected_primary_services" = "$accessibility_primary_services" ] || \
        return 1
    expected_alternate_services="$(remove_accessibility_service \
        "$accessibility_primary_services" "$ACCESSIBILITY_COMPONENT")"
    [ "$expected_alternate_services" = "$accessibility_alternate_services" ]
}

read_accessibility_transaction() {
    [ ! -L "$ACCESSIBILITY_TRANSACTION_MARKER" ] && \
        [ -f "$ACCESSIBILITY_TRANSACTION_MARKER" ] || return 1
    if ! accessibility_marker_output="$(
        cat "$ACCESSIBILITY_TRANSACTION_MARKER" 2>/dev/null
        accessibility_marker_status=$?
        printf '|'
        exit "$accessibility_marker_status"
    )"; then
        return 1
    fi
    case "$accessibility_marker_output" in
        *'|') accessibility_marker_output=${accessibility_marker_output%|} ;;
        *) return 1 ;;
    esac
    line_feed='
'
    case "$accessibility_marker_output" in
        *"$line_feed")
            accessibility_marker_output=${accessibility_marker_output%"$line_feed"}
            ;;
        *) return 1 ;;
    esac
    case "$accessibility_marker_output" in
        *"$line_feed"*) return 1 ;;
    esac
    parse_accessibility_transaction_state "$accessibility_marker_output" || return 1
    printf '%s\n' "$accessibility_marker_output"
}

write_accessibility_transaction() {
    accessibility_original_enabled_value="$1"
    accessibility_temporary_enabled_value="$2"
    accessibility_original_services_value="$3"
    accessibility_primary_services_value="$4"
    accessibility_alternate_services_value="$5"
    accessibility_state_value="pending|$accessibility_original_enabled_value|$accessibility_temporary_enabled_value|$accessibility_original_services_value|$accessibility_primary_services_value|$accessibility_alternate_services_value"
    parse_accessibility_transaction_state "$accessibility_state_value" || return 1
    ensure_state_dir || return 1
    if [ -e "$ACCESSIBILITY_TRANSACTION_MARKER" ] || \
        [ -L "$ACCESSIBILITY_TRANSACTION_MARKER" ]; then
        log_event "accessibility_transaction_already_present"
        return 1
    fi
    accessibility_marker_tmp="$ACCESSIBILITY_TRANSACTION_MARKER.tmp.$$"
    rm -f "$accessibility_marker_tmp" 2>/dev/null || true
    if ! { printf '%s\n' "$accessibility_state_value" > \
            "$accessibility_marker_tmp"; } 2>/dev/null || \
        ! chmod 0600 "$accessibility_marker_tmp" 2>/dev/null || \
        ! mv -f "$accessibility_marker_tmp" \
            "$ACCESSIBILITY_TRANSACTION_MARKER" 2>/dev/null; then
        rm -f "$accessibility_marker_tmp" 2>/dev/null || true
        log_event "accessibility_transaction_write_failed"
        return 1
    fi
    if ! published_accessibility_state="$(read_accessibility_transaction)" || \
        [ "$published_accessibility_state" != "$accessibility_state_value" ]; then
        log_event "accessibility_transaction_changed"
        return 1
    fi
    if ! run_guard_command "$HOME_MARKER_SYNC_COMMAND" -f \
        "$ACCESSIBILITY_TRANSACTION_MARKER" "$STATE_DIR" \
        >/dev/null 2>&1; then
        log_event "accessibility_transaction_sync_failed"
        return 1
    fi
    if ! synced_accessibility_state="$(read_accessibility_transaction)" || \
        [ "$synced_accessibility_state" != "$accessibility_state_value" ]; then
        log_event "accessibility_transaction_changed"
        return 1
    fi
    return 0
}

clear_accessibility_transaction() {
    if [ ! -e "$ACCESSIBILITY_TRANSACTION_MARKER" ] && \
        [ ! -L "$ACCESSIBILITY_TRANSACTION_MARKER" ]; then
        return 0
    fi
    read_accessibility_transaction >/dev/null || return 1
    rm -f "$ACCESSIBILITY_TRANSACTION_MARKER" 2>/dev/null || return 1
    run_guard_command "$HOME_MARKER_SYNC_COMMAND" -f "$STATE_DIR" \
        >/dev/null 2>&1 || return 1
    [ ! -e "$ACCESSIBILITY_TRANSACTION_MARKER" ] && \
        [ ! -L "$ACCESSIBILITY_TRANSACTION_MARKER" ]
}

normalize_accessibility_enabled() {
    case "$1" in
        0|1) printf '%s\n' "$1" ;;
        null|NULL|"") printf '0\n' ;;
        *) return 1 ;;
    esac
}

restore_accessibility_transaction() {
    accessibility_state="$(read_accessibility_transaction)" || {
        log_event "accessibility_transaction_invalid"
        return 1
    }
    parse_accessibility_transaction_state "$accessibility_state" || return 1

    if ! observed_services="$(run_guard_command settings --user \
        "$ANDROID_USER_ID" get secure enabled_accessibility_services \
        2>/dev/null)"; then
        log_event "accessibility_transaction_services_read_failed"
        return 1
    fi
    case "$observed_services" in
        null|NULL) observed_services="" ;;
    esac
    if ! confirmed_services="$(run_guard_command settings --user \
        "$ANDROID_USER_ID" get secure enabled_accessibility_services \
        2>/dev/null)"; then
        log_event "accessibility_transaction_services_confirm_failed"
        return 1
    fi
    case "$confirmed_services" in
        null|NULL) confirmed_services="" ;;
    esac
    if [ "$confirmed_services" != "$observed_services" ]; then
        log_event "accessibility_transaction_services_unstable"
        return 1
    fi
    if [ "$observed_services" = "$accessibility_original_services" ]; then
        :
    elif [ "$observed_services" = "$accessibility_primary_services" ] || \
        [ "$observed_services" = "$accessibility_alternate_services" ]; then
        if ! run_guard_command settings --user "$ANDROID_USER_ID" put secure \
            enabled_accessibility_services "$accessibility_original_services" \
            >/dev/null 2>&1; then
            log_event "accessibility_transaction_services_restore_failed"
            return 1
        fi
        if ! restored_services="$(run_guard_command settings --user \
            "$ANDROID_USER_ID" get secure enabled_accessibility_services \
            2>/dev/null)"; then
            log_event "accessibility_transaction_services_restore_unreadable"
            return 1
        fi
        case "$restored_services" in
            null|NULL) restored_services="" ;;
        esac
        if [ "$restored_services" != "$accessibility_original_services" ]; then
            log_event "accessibility_transaction_services_restore_unconfirmed"
            return 1
        fi
    else
        log_event "accessibility_transaction_preserved_new_services"
    fi

    observed_enabled_raw="$(run_guard_command settings --user "$ANDROID_USER_ID" \
        get secure accessibility_enabled 2>/dev/null)" || {
        log_event "accessibility_transaction_enabled_read_failed"
        return 1
    }
    observed_enabled="$(normalize_accessibility_enabled \
        "$observed_enabled_raw")" || {
        log_event "accessibility_transaction_enabled_invalid"
        return 1
    }
    confirmed_enabled_raw="$(run_guard_command settings --user \
        "$ANDROID_USER_ID" get secure accessibility_enabled 2>/dev/null)" || {
        log_event "accessibility_transaction_enabled_confirm_failed"
        return 1
    }
    confirmed_enabled="$(normalize_accessibility_enabled \
        "$confirmed_enabled_raw")" || {
        log_event "accessibility_transaction_enabled_invalid"
        return 1
    }
    if [ "$confirmed_enabled" != "$observed_enabled" ]; then
        log_event "accessibility_transaction_enabled_unstable"
        return 1
    fi
    if [ "$observed_enabled" = "$accessibility_original_enabled" ]; then
        :
    elif [ "$observed_enabled" = "$accessibility_temporary_enabled" ]; then
        if ! run_guard_command settings --user "$ANDROID_USER_ID" put secure \
            accessibility_enabled "$accessibility_original_enabled" \
            >/dev/null 2>&1; then
            log_event "accessibility_transaction_enabled_restore_failed"
            return 1
        fi
        restored_enabled_raw="$(run_guard_command settings --user \
            "$ANDROID_USER_ID" get secure accessibility_enabled \
            2>/dev/null)" || return 1
        restored_enabled="$(normalize_accessibility_enabled \
            "$restored_enabled_raw")" || return 1
        if [ "$restored_enabled" != "$accessibility_original_enabled" ]; then
            log_event "accessibility_transaction_enabled_restore_unconfirmed"
            return 1
        fi
    else
        log_event "accessibility_transaction_preserved_new_enabled"
    fi

    clear_accessibility_transaction || {
        log_event "accessibility_transaction_clear_failed"
        return 1
    }
    log_event "accessibility_transaction_restored"
    return 0
}

restore_accessibility_after_interrupted_rebind() {
    temporary_services="$1"
    original_services="$2"
    temporary_enabled="$3"
    original_enabled="$4"

    if [ -e "$ACCESSIBILITY_TRANSACTION_MARKER" ] || \
        [ -L "$ACCESSIBILITY_TRANSACTION_MARKER" ]; then
        restore_accessibility_transaction
        return $?
    fi

    if ! observed_services="$(run_guard_command settings --user "$ANDROID_USER_ID" \
        get secure enabled_accessibility_services 2>/dev/null)"; then
        log_event "accessibility_service_rebind_compensation_read_failed"
        return 1
    fi
    case "$observed_services" in
        null|NULL) observed_services="" ;;
    esac
    if [ "$observed_services" != "$original_services" ] && \
        [ "$observed_services" != "$temporary_services" ]; then
        log_event "accessibility_service_rebind_preserved_new_choice"
    elif [ "$observed_services" = "$temporary_services" ] && \
        [ "$temporary_services" != "$original_services" ]; then
        if ! run_guard_command settings --user "$ANDROID_USER_ID" put secure \
            enabled_accessibility_services "$original_services" \
            >/dev/null 2>&1; then
            log_event "accessibility_service_rebind_compensation_write_failed"
            return 1
        fi
        if ! restored_services="$(run_guard_command settings --user "$ANDROID_USER_ID" \
            get secure enabled_accessibility_services 2>/dev/null)"; then
            log_event "accessibility_service_rebind_compensation_confirm_failed"
            return 1
        fi
        case "$restored_services" in
            null|NULL) restored_services="" ;;
        esac
        if [ "$restored_services" != "$original_services" ]; then
            log_event "accessibility_service_rebind_compensation_unconfirmed"
            return 1
        fi
    fi

    if ! observed_enabled="$(run_guard_command settings --user "$ANDROID_USER_ID" \
        get secure accessibility_enabled 2>/dev/null)"; then
        log_event "accessibility_service_rebind_enabled_compensation_read_failed"
        return 1
    fi
    case "$observed_enabled" in
        null|NULL|"") observed_enabled=0 ;;
    esac
    if [ "$observed_enabled" != "$original_enabled" ]; then
        if [ "$observed_enabled" != "$temporary_enabled" ]; then
            log_event "accessibility_service_rebind_preserved_enabled_choice"
            return 0
        fi
        if ! run_guard_command settings --user "$ANDROID_USER_ID" put secure \
            accessibility_enabled "$original_enabled" >/dev/null 2>&1; then
            log_event "accessibility_service_rebind_enabled_compensation_write_failed"
            return 1
        fi
        if ! restored_enabled="$(run_guard_command settings --user "$ANDROID_USER_ID" \
            get secure accessibility_enabled 2>/dev/null)" || \
            [ "$restored_enabled" != "$original_enabled" ]; then
            log_event "accessibility_service_rebind_enabled_compensation_unconfirmed"
            return 1
        fi
    fi
    log_event "accessibility_service_rebind_compensated"
    return 0
}

rebind_accessibility_service() {
    current="$1"
    merged="$2"
    original_enabled="$3"

    case ":$current:" in
        *":$ACCESSIBILITY_COMPONENT:"*) ;;
        *) return 0 ;;
    esac

    without="$(remove_accessibility_service "$current" "$ACCESSIBILITY_COMPONENT")"
    module_is_active || return 1
    if ! temporary_enabled="$(run_guard_command settings --user "$ANDROID_USER_ID" \
        get secure accessibility_enabled 2>/dev/null)"; then
        log_event "accessibility_service_rebind_enabled_read_failed"
        return 1
    fi
    case "$temporary_enabled" in
        null|NULL|"") temporary_enabled=0 ;;
    esac
    module_is_active || return 1
    if [ "$temporary_enabled" != 1 ]; then
        log_event "accessibility_service_rebind_enabled_changed"
        return 1
    fi
    if ! run_guard_command settings --user "$ANDROID_USER_ID" put secure \
        enabled_accessibility_services "$without" >/dev/null 2>&1; then
        if ! restore_accessibility_after_interrupted_rebind "$without" "$current" \
            "$temporary_enabled" "$original_enabled"; then
            log_event "accessibility_service_rebind_compensation_failed"
        fi
        log_event "accessibility_service_rebind_remove_failed"
        return 1
    fi
    if ! module_is_active; then
        restore_accessibility_after_interrupted_rebind "$without" "$current" \
            "$temporary_enabled" "$original_enabled" || \
            log_event "accessibility_service_rebind_compensation_failed"
        return 1
    fi
    sleep 1
    if ! module_is_active; then
        restore_accessibility_after_interrupted_rebind "$without" "$current" \
            "$temporary_enabled" "$original_enabled" || \
            log_event "accessibility_service_rebind_compensation_failed"
        return 1
    fi
    if ! pre_restore_services="$(run_guard_command settings --user \
        "$ANDROID_USER_ID" get secure enabled_accessibility_services \
        2>/dev/null)"; then
        restore_accessibility_after_interrupted_rebind "$without" "$current" \
            "$temporary_enabled" "$original_enabled" || \
            log_event "accessibility_service_rebind_compensation_failed"
        log_event "accessibility_service_rebind_pre_restore_read_failed"
        return 1
    fi
    case "$pre_restore_services" in
        null|NULL) pre_restore_services="" ;;
    esac
    module_is_active || {
        restore_accessibility_after_interrupted_rebind "$without" "$current" \
            "$temporary_enabled" "$original_enabled" || \
            log_event "accessibility_service_rebind_compensation_failed"
        return 1
    }
    if ! confirmed_pre_restore_services="$(run_guard_command settings --user \
        "$ANDROID_USER_ID" get secure enabled_accessibility_services \
        2>/dev/null)"; then
        restore_accessibility_after_interrupted_rebind "$without" "$current" \
            "$temporary_enabled" "$original_enabled" || \
            log_event "accessibility_service_rebind_compensation_failed"
        log_event "accessibility_service_rebind_pre_restore_confirm_failed"
        return 1
    fi
    case "$confirmed_pre_restore_services" in
        null|NULL) confirmed_pre_restore_services="" ;;
    esac
    if [ "$pre_restore_services" != "$without" ] || \
        [ "$confirmed_pre_restore_services" != "$without" ]; then
        restore_accessibility_after_interrupted_rebind "$without" "$current" \
            "$temporary_enabled" "$original_enabled" || \
            log_event "accessibility_service_rebind_compensation_failed"
        log_event "accessibility_service_rebind_preserved_new_choice"
        return 1
    fi
    module_is_active || {
        restore_accessibility_after_interrupted_rebind "$without" "$current" \
            "$temporary_enabled" "$original_enabled" || \
            log_event "accessibility_service_rebind_compensation_failed"
        return 1
    }
    if ! run_guard_command settings --user "$ANDROID_USER_ID" put secure \
        enabled_accessibility_services "$merged" >/dev/null 2>&1; then
        if ! restore_accessibility_after_interrupted_rebind "$without" "$current" \
            "$temporary_enabled" "$original_enabled"; then
            log_event "accessibility_service_rebind_compensation_failed"
        fi
        log_event "accessibility_service_rebind_restore_failed"
        return 1
    fi
    if ! module_is_active; then
        restore_accessibility_after_interrupted_rebind "$without" "$current" \
            "$temporary_enabled" "$original_enabled" || \
            log_event "accessibility_service_rebind_compensation_failed"
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

valid_android_package_name() {
    package_value="$1"
    package_has_separator=0
    [ -n "$package_value" ] || return 1
    [ "${#package_value}" -le 223 ] || return 1

    while :; do
        case "$package_value" in
            *.*)
                package_segment=${package_value%%.*}
                package_value=${package_value#*.}
                package_has_separator=1
                [ -n "$package_value" ] || return 1
                ;;
            *)
                package_segment=$package_value
                package_value=""
                ;;
        esac
        case "$package_segment" in
            [A-Za-z]*) ;;
            *) return 1 ;;
        esac
        case "$package_segment" in
            *[!A-Za-z0-9_]*) return 1 ;;
        esac
        [ -n "$package_value" ] || break
    done
    [ "$package_has_separator" -eq 1 ]
}

valid_home_holder() {
    [ "$1" != "$PACKAGE_NAME" ] && valid_android_package_name "$1"
}

read_home_role_holder() {
    if ! home_output="$(
        run_guard_command cmd role get-role-holders \
            --user "$ANDROID_USER_ID" "$HOME_ROLE_NAME" 2>/dev/null
        home_status=$?
        printf '|'
        exit "$home_status"
    )"; then
        return 1
    fi
    case "$home_output" in
        *'|') home_output=${home_output%|} ;;
        *) return 1 ;;
    esac
    if [ -z "$home_output" ]; then
        printf 'none\n'
        return 0
    fi
    line_feed='
'
    case "$home_output" in
        *"$line_feed")
            home_output=${home_output%"$line_feed"}
            [ -n "$home_output" ] || return 1
            ;;
    esac
    valid_android_package_name "$home_output" || return 1
    printf '%s\n' "$home_output"
}

read_home_resolved_component() {
    if ! resolver_output="$(
        run_guard_command cmd package resolve-activity \
            --brief --components --user "$ANDROID_USER_ID" \
            -a android.intent.action.MAIN \
            -c android.intent.category.HOME 2>/dev/null
        resolver_status=$?
        printf '|'
        exit "$resolver_status"
    )"; then
        printf 'unknown\n'
        return 1
    fi
    case "$resolver_output" in
        *'|') resolver_output=${resolver_output%|} ;;
        *)
            printf 'unknown\n'
            return 1
            ;;
    esac

    line_feed='
'
    case "$resolver_output" in
        *"$line_feed")
            resolver_output=${resolver_output%"$line_feed"}
            ;;
        *)
            printf 'unknown\n'
            return 1
            ;;
    esac
    case "$resolver_output" in
        ''|*"$line_feed"*|*'|'*|*null*|*NULL*)
            printf 'unknown\n'
            return 1
            ;;
        'No activity found')
            printf 'none\n'
            return 0
            ;;
    esac

    resolver_package=${resolver_output%%/*}
    resolver_class=${resolver_output#*/}
    [ "$resolver_output" != "$resolver_package" ] || {
        printf 'unknown\n'
        return 1
    }
    case "$resolver_class" in
        ''|*/*|*[!A-Za-z0-9_.\$]*)
            printf 'unknown\n'
            return 1
            ;;
    esac
    valid_android_package_name "$resolver_package" || {
        printf 'unknown\n'
        return 1
    }
    case "$resolver_package/$resolver_class" in
        "$PACKAGE_NAME/.feature.home.MainActivity"|\
        "$PACKAGE_NAME/$PACKAGE_NAME.feature.home.MainActivity")
            printf 'target\n'
            ;;
        *)
            printf 'other\n'
            ;;
    esac
}

home_resolver_state() {
    read_home_resolved_component
}

read_home_holder_marker() {
    marker_path="$1"
    [ ! -L "$marker_path" ] && [ -f "$marker_path" ] || return 1
    if ! marker_output="$(
        cat "$marker_path" 2>/dev/null
        marker_status=$?
        printf '|'
        exit "$marker_status"
    )"; then
        return 1
    fi
    case "$marker_output" in
        *'|') marker_output=${marker_output%|} ;;
        *) return 1 ;;
    esac
    line_feed='
'
    case "$marker_output" in
        *"$line_feed") marker_output=${marker_output%"$line_feed"} ;;
        *) return 1 ;;
    esac
    if [ "$marker_output" != "none" ] && ! valid_home_holder "$marker_output"; then
        return 1
    fi
    printf '%s\n' "$marker_output"
}

read_home_previous_holder() {
    read_home_holder_marker "$HOME_PREVIOUS_HOLDER_MARKER"
}

valid_home_takeover_state() {
    case "$1" in
        owned|released) return 0 ;;
        pending\|*\|*)
            pending_remainder=${1#pending|}
            pending_boot_id=${pending_remainder%%|*}
            pending_holder=${pending_remainder#*|}
            [ -n "$pending_boot_id" ] || return 1
            case "$pending_boot_id" in
                *[!A-Za-z0-9._-]*) return 1 ;;
            esac
            [ "${#pending_boot_id}" -le 128 ] || return 1
            [ "$pending_holder" = none ] || valid_home_holder "$pending_holder"
            ;;
        *) return 1 ;;
    esac
}

read_home_takeover_state() {
    [ ! -L "$HOME_TAKEOVER_STATE_MARKER" ] && \
        [ -f "$HOME_TAKEOVER_STATE_MARKER" ] || return 1
    if ! state_output="$(
        cat "$HOME_TAKEOVER_STATE_MARKER" 2>/dev/null
        state_status=$?
        printf '|'
        exit "$state_status"
    )"; then
        return 1
    fi
    case "$state_output" in
        *'|') state_output=${state_output%|} ;;
        *) return 1 ;;
    esac
    line_feed='
'
    case "$state_output" in
        *"$line_feed") state_output=${state_output%"$line_feed"} ;;
        *) return 1 ;;
    esac
    case "$state_output" in
        *"$line_feed"*) return 1 ;;
    esac
    valid_home_takeover_state "$state_output" || return 1
    printf '%s\n' "$state_output"
}

write_home_takeover_state() {
    takeover_state="$1"
    valid_home_takeover_state "$takeover_state" || return 1
    ensure_state_dir || return 1
    if [ -e "$HOME_TAKEOVER_STATE_MARKER" ] || \
        [ -L "$HOME_TAKEOVER_STATE_MARKER" ]; then
        if [ -L "$HOME_TAKEOVER_STATE_MARKER" ] || \
            [ ! -f "$HOME_TAKEOVER_STATE_MARKER" ]; then
            log_event "home_role_state_marker_invalid"
            return 1
        fi
    fi
    state_tmp="$HOME_TAKEOVER_STATE_MARKER.tmp.$$"
    rm -f "$state_tmp" 2>/dev/null || true
    if ! { printf '%s\n' "$takeover_state" > "$state_tmp"; } 2>/dev/null || \
        ! chmod 0600 "$state_tmp" 2>/dev/null || \
        ! mv -f "$state_tmp" "$HOME_TAKEOVER_STATE_MARKER" 2>/dev/null; then
        rm -f "$state_tmp" 2>/dev/null || true
        log_event "home_role_state_marker_write_failed"
        return 1
    fi
    if ! published_state="$(read_home_takeover_state)" || \
        [ "$published_state" != "$takeover_state" ]; then
        log_event "home_role_state_marker_changed"
        return 1
    fi
    if ! run_guard_command "$HOME_MARKER_SYNC_COMMAND" -f \
        "$HOME_TAKEOVER_STATE_MARKER" "$STATE_DIR" >/dev/null 2>&1; then
        log_event "home_role_state_marker_sync_failed"
        return 1
    fi
    if ! synced_state="$(read_home_takeover_state)" || \
        [ "$synced_state" != "$takeover_state" ]; then
        log_event "home_role_state_marker_changed"
        return 1
    fi
    return 0
}

home_pending_boot_id() {
    pending_state="$1"
    pending_remainder=${pending_state#pending|}
    printf '%s\n' "${pending_remainder%%|*}"
}

home_pending_holder() {
    pending_state="$1"
    pending_remainder=${pending_state#pending|}
    printf '%s\n' "${pending_remainder#*|}"
}

cleanup_helper_ready() {
    helper_source="${1:-${CLEANUP_SOURCE:-}}"
    [ -n "$helper_source" ] && \
        [ ! -L "$helper_source" ] && \
        [ -f "$helper_source" ] && \
        [ ! -L "$CLEANUP_TARGET" ] && \
        [ -f "$CLEANUP_TARGET" ] && \
        [ -x "$CLEANUP_TARGET" ] && \
        cmp -s "$helper_source" "$CLEANUP_TARGET"
}

home_role_state() {
    if ! home_holder="$(read_home_role_holder)"; then
        printf 'unknown\n'
        return 0
    fi
    case "$home_holder" in
        "$PACKAGE_NAME")
            if ! home_resolver="$(home_resolver_state)"; then
                printf 'unknown\n'
                return 0
            fi
            case "$home_resolver" in
                target) printf 'owned\n' ;;
                other) printf 'other\n' ;;
                none) printf 'none\n' ;;
                *) printf 'unknown\n' ;;
            esac
            ;;
        none) printf 'none\n' ;;
        *) printf 'other\n' ;;
    esac
}

repair_owned_home_route_locked() {
    owned_route_state="$1"
    case "$owned_route_state" in
        target)
            return 0
            ;;
        other|none)
            ;;
        *)
            log_event "home_route_unknown"
            return 1
            ;;
    esac
    module_is_active || return 1
    if ! route_current_holder="$(read_home_role_holder)" || \
        [ "$route_current_holder" != "$PACKAGE_NAME" ]; then
        log_event "home_route_holder_changed_before_set"
        return 1
    fi
    if ! run_guard_command cmd package set-home-activity --user "$ANDROID_USER_ID" \
        "$HOME_COMPONENT" >/dev/null 2>&1; then
        log_event "home_route_set_failed"
        return 1
    fi
    module_is_active || return 1
    if ! route_confirmed_holder="$(read_home_role_holder)" || \
        [ "$route_confirmed_holder" != "$PACKAGE_NAME" ]; then
        log_event "home_route_holder_unconfirmed"
        return 1
    fi
    if ! route_confirmed_state="$(home_resolver_state)" || \
        [ "$route_confirmed_state" != target ]; then
        log_event "home_route_unconfirmed"
        return 1
    fi
    module_is_active || return 1
    log_event "home_route_repaired"
    return 0
}

record_home_holder_marker() {
    holder_value="$1"
    holder_marker="$2"
    holder_event="$3"
    if [ "$holder_value" != "none" ] && ! valid_home_holder "$holder_value"; then
        log_event "${holder_event}_holder_invalid"
        return 1
    fi
    ensure_state_dir || return 1

    if [ ! -e "$holder_marker" ] && [ ! -L "$holder_marker" ]; then
        marker_tmp="$holder_marker.tmp.$$"
        rm -f "$marker_tmp" 2>/dev/null || true
        if ! { printf '%s\n' "$holder_value" > "$marker_tmp"; } 2>/dev/null || \
            ! chmod 0600 "$marker_tmp" 2>/dev/null; then
            rm -f "$marker_tmp" 2>/dev/null || true
            log_event "${holder_event}_write_failed"
            return 1
        fi
        run_guard_command "$HOME_MARKER_LINK_COMMAND" "$marker_tmp" \
            "$holder_marker" \
            >/dev/null 2>&1 || true
        rm -f "$marker_tmp" 2>/dev/null || true
    fi

    if ! saved_holder_before_sync="$(read_home_holder_marker "$holder_marker")"; then
        log_event "${holder_event}_invalid"
        return 1
    fi
    if ! run_guard_command "$HOME_MARKER_SYNC_COMMAND" -f \
        "$holder_marker" "$STATE_DIR" \
        >/dev/null 2>&1; then
        log_event "${holder_event}_sync_failed"
        return 1
    fi
    if ! saved_holder_after_sync="$(read_home_holder_marker "$holder_marker")" || \
        [ "$saved_holder_before_sync" != "$saved_holder_after_sync" ]; then
        log_event "${holder_event}_changed"
        return 1
    fi
    return 0
}

record_home_previous_holder() {
    record_home_holder_marker "$1" "$HOME_PREVIOUS_HOLDER_MARKER" "home_role_marker"
}

home_transaction_owner_is_active() {
    home_lock_pid="$(cat "$HOME_TRANSACTION_LOCK_DIR/pid" 2>/dev/null || true)"
    home_lock_boot="$(cat "$HOME_TRANSACTION_LOCK_DIR/boot_id" 2>/dev/null || true)"
    case "$home_lock_pid" in
        ''|*[!0-9]*) return 2 ;;
    esac
    kill -0 "$home_lock_pid" 2>/dev/null || return 1
    [ -n "$home_lock_boot" ] || return 0
    [ "$home_lock_boot" = "$(current_guard_boot_id)" ] || return 1
    home_lock_identity="$(guard_owner_identity_state \
        "$HOME_TRANSACTION_LOCK_DIR" "$home_lock_pid")"
    case "$home_lock_identity" in
        match|unknown) return 0 ;;
        *) return 1 ;;
    esac
}

release_home_transaction_reclaim() {
    if [ -f "$HOME_TRANSACTION_RECLAIM_DIR/pid" ] && \
        [ "$(cat "$HOME_TRANSACTION_RECLAIM_DIR/pid" 2>/dev/null)" = "$$" ]; then
        rm -f "$HOME_TRANSACTION_RECLAIM_DIR/pid"
        rmdir "$HOME_TRANSACTION_RECLAIM_DIR" 2>/dev/null || true
    fi
}

release_home_transaction_lock() {
    home_unlock_status=0
    if [ -f "$HOME_TRANSACTION_LOCK_DIR/pid" ] && \
        [ "$(cat "$HOME_TRANSACTION_LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then
        rm -f "$HOME_TRANSACTION_LOCK_DIR/pid" \
            "$HOME_TRANSACTION_LOCK_DIR/boot_id" \
            "$HOME_TRANSACTION_LOCK_DIR/start_time" || home_unlock_status=1
        rmdir "$HOME_TRANSACTION_LOCK_DIR" 2>/dev/null || home_unlock_status=1
    fi
    return "$home_unlock_status"
}

acquire_home_transaction_lock() {
    ensure_state_dir || return 1
    home_lock_attempt_limit="${YINXING_GUARD_HOME_LOCK_ATTEMPTS:-5}"
    case "$home_lock_attempt_limit" in
        ''|*[!0-9]*|0) home_lock_attempt_limit=5 ;;
    esac
    home_lock_attempt=0
    while [ "$home_lock_attempt" -lt "$home_lock_attempt_limit" ]; do
        if [ -L "$HOME_TRANSACTION_LOCK_DIR" ] || \
            [ -L "$HOME_TRANSACTION_RECLAIM_DIR" ]; then
            log_event "home_transaction_lock_invalid"
            return 1
        fi

        if [ -d "$HOME_TRANSACTION_RECLAIM_DIR" ]; then
            home_reclaim_pid="$(cat "$HOME_TRANSACTION_RECLAIM_DIR/pid" 2>/dev/null || true)"
            case "$home_reclaim_pid" in
                ''|*[!0-9]*) ;;
                *)
                    if kill -0 "$home_reclaim_pid" 2>/dev/null; then
                        home_lock_attempt=$((home_lock_attempt + 1))
                        sleep 1
                        continue
                    fi
                    ;;
            esac
            rm -rf "$HOME_TRANSACTION_RECLAIM_DIR" 2>/dev/null || return 1
        fi

        if mkdir "$HOME_TRANSACTION_LOCK_DIR" 2>/dev/null; then
            if [ -d "$HOME_TRANSACTION_RECLAIM_DIR" ]; then
                rmdir "$HOME_TRANSACTION_LOCK_DIR" 2>/dev/null || true
                home_lock_attempt=$((home_lock_attempt + 1))
                sleep 1
                continue
            fi
            home_lock_boot="$(current_guard_boot_id)"
            home_lock_start="$(process_start_time "$$" 2>/dev/null || true)"
            if ! printf '%s\n' "$$" > \
                    "$HOME_TRANSACTION_LOCK_DIR/pid" 2>/dev/null || \
                ! printf '%s\n' "$home_lock_boot" > \
                    "$HOME_TRANSACTION_LOCK_DIR/boot_id" 2>/dev/null || \
                { [ -n "$home_lock_start" ] && \
                    ! printf '%s\n' "$home_lock_start" > \
                        "$HOME_TRANSACTION_LOCK_DIR/start_time" 2>/dev/null; }; then
                release_home_transaction_lock
                rm -f "$HOME_TRANSACTION_LOCK_DIR/boot_id" \
                    "$HOME_TRANSACTION_LOCK_DIR/start_time" 2>/dev/null || true
                rmdir "$HOME_TRANSACTION_LOCK_DIR" 2>/dev/null || true
                log_event "home_transaction_lock_write_failed"
                return 1
            fi
            return 0
        fi

        if [ ! -d "$HOME_TRANSACTION_LOCK_DIR" ]; then
            log_event "home_transaction_lock_invalid"
            return 1
        fi
        home_transaction_owner_is_active
        home_owner_status=$?
        case "$home_owner_status" in
            0)
                log_event "home_transaction_lock_busy"
                return 1
                ;;
            2)
                if [ "$home_lock_attempt" -ge $((home_lock_attempt_limit - 1)) ]; then
                    :
                else
                    home_lock_attempt=$((home_lock_attempt + 1))
                    sleep 1
                    continue
                fi
                ;;
        esac

        if mkdir "$HOME_TRANSACTION_RECLAIM_DIR" 2>/dev/null; then
            if ! printf '%s\n' "$$" > \
                    "$HOME_TRANSACTION_RECLAIM_DIR/pid" 2>/dev/null; then
                release_home_transaction_reclaim
                return 1
            fi
            home_transaction_owner_is_active
            home_checked_status=$?
            case "$home_checked_status" in
                0)
                    release_home_transaction_reclaim
                    log_event "home_transaction_lock_busy"
                    return 1
                    ;;
                2)
                    sleep 1
                    home_transaction_owner_is_active
                    home_checked_status=$?
                    if [ "$home_checked_status" -eq 0 ]; then
                        release_home_transaction_reclaim
                        log_event "home_transaction_lock_busy"
                        return 1
                    fi
                    ;;
            esac
            rm -rf "$HOME_TRANSACTION_LOCK_DIR" 2>/dev/null || {
                release_home_transaction_reclaim
                return 1
            }
            release_home_transaction_reclaim
            home_lock_attempt=$((home_lock_attempt + 1))
            continue
        fi

        home_lock_attempt=$((home_lock_attempt + 1))
        sleep 1
    done
    log_event "home_transaction_lock_retry"
    return 1
}

clear_released_home_evidence() {
    home_previous_exists=0
    home_state_exists=0
    if [ -e "$HOME_PREVIOUS_HOLDER_MARKER" ] || \
        [ -L "$HOME_PREVIOUS_HOLDER_MARKER" ]; then
        read_home_previous_holder >/dev/null || return 1
        home_previous_exists=1
    fi
    if [ -e "$HOME_TAKEOVER_STATE_MARKER" ] || \
        [ -L "$HOME_TAKEOVER_STATE_MARKER" ]; then
        home_clear_state="$(read_home_takeover_state)" || return 1
        [ "$home_clear_state" = released ] || return 1
        home_state_exists=1
    fi
    if [ "$home_previous_exists" -eq 1 ]; then
        rm -f "$HOME_PREVIOUS_HOLDER_MARKER" 2>/dev/null || return 1
        run_guard_command "$HOME_MARKER_SYNC_COMMAND" -f "$STATE_DIR" \
            >/dev/null 2>&1 || return 1
    fi
    if [ "$home_state_exists" -eq 1 ]; then
        rm -f "$HOME_TAKEOVER_STATE_MARKER" 2>/dev/null || return 1
        run_guard_command "$HOME_MARKER_SYNC_COMMAND" -f "$STATE_DIR" \
            >/dev/null 2>&1 || return 1
    fi
    return 0
}

rollback_home_after_inactive_takeover() {
    if ! rollback_state="$(read_home_takeover_state)"; then
        log_event "home_role_inactive_rollback_state_invalid"
        return 1
    fi
    case "$rollback_state" in
        pending\|*) ;;
        *)
            log_event "home_role_inactive_rollback_state_not_pending"
            return 1
            ;;
    esac
    rollback_previous_home="$(home_pending_holder "$rollback_state")"
    if ! read_home_previous_holder >/dev/null; then
        log_event "home_role_inactive_rollback_marker_invalid"
        return 1
    fi
    if ! rollback_current_home="$(read_home_role_holder)"; then
        log_event "home_role_inactive_rollback_query_failed"
        return 1
    fi
    if [ "$rollback_current_home" != "$PACKAGE_NAME" ]; then
        sleep 1
        if ! rollback_confirmed_home="$(read_home_role_holder)" || \
            [ "$rollback_confirmed_home" != "$rollback_current_home" ]; then
            log_event "home_role_inactive_preserve_unconfirmed"
            return 1
        fi
        if ! write_home_takeover_state released; then
            log_event "home_role_inactive_release_failed"
            return 1
        fi
        log_event "home_role_inactive_rollback_preserved_new_choice_released"
        return 0
    fi

    if [ "$rollback_previous_home" = "none" ]; then
        if ! run_guard_command cmd role remove-role-holder --user "$ANDROID_USER_ID" \
            "$HOME_ROLE_NAME" "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_event "home_role_inactive_remove_failed"
            return 1
        fi
        if ! rollback_confirmed_home="$(read_home_role_holder)" || \
            [ "$rollback_confirmed_home" = "$PACKAGE_NAME" ]; then
            log_event "home_role_inactive_remove_unconfirmed"
            return 1
        fi
    else
        if ! run_guard_command pm path --user "$ANDROID_USER_ID" "$rollback_previous_home" \
            >/dev/null 2>&1; then
            log_event "home_role_inactive_previous_missing"
            return 1
        fi
        if ! rollback_current_home="$(read_home_role_holder)"; then
            log_event "home_role_inactive_pre_restore_query_failed"
            return 1
        fi
        if [ "$rollback_current_home" != "$PACKAGE_NAME" ]; then
            write_home_takeover_state released || return 1
            log_event "home_role_inactive_rollback_preserved_new_choice_released"
            return 0
        fi
        if ! run_guard_command cmd package set-home-activity --user "$ANDROID_USER_ID" \
            "$rollback_previous_home" >/dev/null 2>&1; then
            log_event "home_role_inactive_restore_failed"
            return 1
        fi
        if ! rollback_confirmed_home="$(read_home_role_holder)" || \
            [ "$rollback_confirmed_home" != "$rollback_previous_home" ]; then
            log_event "home_role_inactive_restore_unconfirmed"
            return 1
        fi
    fi

    if ! write_home_takeover_state released; then
        log_event "home_role_inactive_rollback_state_release_failed"
        return 1
    fi
    log_event "home_role_inactive_rollback_complete_state_released"
    return 0
}

repair_home_role_locked() {
    if ! current_home_holder="$(read_home_role_holder)"; then
        log_event "home_role_query_failed"
        return 1
    fi

    home_previous_present=0
    home_state_present=0
    saved_home_holder=""
    saved_takeover_state=""
    if [ -e "$HOME_PREVIOUS_HOLDER_MARKER" ] || \
        [ -L "$HOME_PREVIOUS_HOLDER_MARKER" ]; then
        if ! saved_home_holder="$(read_home_previous_holder)"; then
            log_event "home_role_marker_invalid"
            return 1
        fi
        home_previous_present=1
    fi
    if [ -e "$HOME_TAKEOVER_STATE_MARKER" ] || \
        [ -L "$HOME_TAKEOVER_STATE_MARKER" ]; then
        if ! saved_takeover_state="$(read_home_takeover_state)"; then
            log_event "home_role_state_marker_invalid"
            return 1
        fi
        home_state_present=1
    fi

    case "$saved_takeover_state" in
        owned|pending\|*)
            if [ "$home_previous_present" -ne 1 ]; then
                log_event "home_role_state_without_marker"
                return 1
            fi
            ;;
        released)
            if ! clear_released_home_evidence; then
                log_event "home_role_released_evidence_clear_failed"
                return 1
            fi
            home_previous_present=0
            home_state_present=0
            saved_home_holder=""
            saved_takeover_state=""
            if ! current_home_holder="$(read_home_role_holder)"; then
                log_event "home_role_post_release_query_failed"
                return 1
            fi
            ;;
        "")
            if [ "$home_previous_present" -eq 1 ]; then
                if ! clear_released_home_evidence; then
                    log_event "home_role_unarmed_marker_clear_failed"
                    return 1
                fi
                home_previous_present=0
                saved_home_holder=""
            fi
            ;;
    esac

    if [ "$current_home_holder" = "$PACKAGE_NAME" ]; then
        if ! current_home_resolver="$(home_resolver_state)"; then
            log_event "home_route_query_failed"
            return 1
        fi
        if [ "$current_home_resolver" != target ]; then
            repair_owned_home_route_locked "$current_home_resolver" || return 1
        fi
        case "$saved_takeover_state" in
            owned) return 0 ;;
            pending\|*)
                cleanup_helper_ready "${CLEANUP_SOURCE:-}" || return 1
                module_is_active || return 1
                pending_state_before_promotion="$saved_takeover_state"
                write_home_takeover_state owned || return 1
                if ! module_is_active; then
                    write_home_takeover_state "$pending_state_before_promotion" && \
                        rollback_home_after_inactive_takeover || \
                        log_event "home_role_inactive_rollback_failed"
                    return 1
                fi
                return 0
                ;;
            "") return 0 ;;
        esac
    fi

    case "$saved_takeover_state" in
        pending\|*)
            pending_boot="$(home_pending_boot_id "$saved_takeover_state")"
            if [ "$pending_boot" = "$(current_guard_boot_id)" ]; then
                log_event "home_role_pending_same_boot"
                return 1
            fi
            if ! write_home_takeover_state released || \
                ! clear_released_home_evidence; then
                log_event "home_role_pending_expire_failed"
                return 1
            fi
            saved_takeover_state=""
            home_previous_present=0
            if ! current_home_holder="$(read_home_role_holder)"; then
                log_event "home_role_post_pending_query_failed"
                return 1
            fi
            [ "$current_home_holder" = "$PACKAGE_NAME" ] && return 0
            ;;
    esac
    if ! cleanup_helper_ready "${CLEANUP_SOURCE:-}"; then
        log_event "home_role_cleanup_helper_unavailable"
        return 1
    fi
    if ! module_is_active; then
        log_event "home_role_skipped_module_inactive"
        return 1
    fi
    if [ "$home_previous_present" -ne 1 ]; then
        record_home_previous_holder "$current_home_holder" || return 1
        home_previous_present=1
    fi
    if ! refreshed_home_holder="$(read_home_role_holder)"; then
        log_event "home_role_pre_set_query_failed"
        return 1
    fi
    if [ "$refreshed_home_holder" = "$PACKAGE_NAME" ]; then
        if [ -z "$saved_takeover_state" ]; then
            clear_released_home_evidence || return 1
        fi
        return 0
    fi
    if [ "$refreshed_home_holder" != "$current_home_holder" ]; then
        log_event "home_role_changed_before_set"
        return 1
    fi
    takeover_boot_id="$(current_guard_boot_id)"
    if ! write_home_takeover_state \
        "pending|$takeover_boot_id|$refreshed_home_holder"; then
        log_event "home_role_pending_state_failed"
        return 1
    fi
    if ! module_is_active; then
        write_home_takeover_state released || true
        return 1
    fi
    if ! post_publish_home_holder="$(read_home_role_holder)"; then
        log_event "home_role_post_publish_query_failed"
        return 1
    fi
    if [ "$post_publish_home_holder" != "$refreshed_home_holder" ]; then
        if ! write_home_takeover_state released || \
            ! clear_released_home_evidence; then
            log_event "home_role_post_publish_release_failed"
            return 1
        fi
        log_event "home_role_changed_after_state_publish"
        return 1
    fi
    if ! module_is_active; then
        write_home_takeover_state released || true
        return 1
    fi
    if ! run_guard_command cmd package set-home-activity --user "$ANDROID_USER_ID" \
        "$HOME_COMPONENT" >/dev/null 2>&1; then
        log_event "home_role_set_failed"
        return 1
    fi
    if ! module_is_active; then
        rollback_home_after_inactive_takeover || \
            log_event "home_role_inactive_rollback_failed"
        return 1
    fi
    if ! confirmed_home_holder="$(read_home_role_holder)"; then
        if ! module_is_active; then
            rollback_home_after_inactive_takeover || \
                log_event "home_role_inactive_rollback_failed"
        fi
        log_event "home_role_confirm_failed"
        return 1
    fi
    if [ "$confirmed_home_holder" != "$PACKAGE_NAME" ]; then
        log_event "home_role_unconfirmed"
        return 1
    fi
    if ! confirmed_home_resolver="$(home_resolver_state)" || \
        [ "$confirmed_home_resolver" != target ]; then
        log_event "home_route_unconfirmed"
        return 1
    fi
    if ! module_is_active; then
        rollback_home_after_inactive_takeover || \
            log_event "home_role_inactive_rollback_failed"
        return 1
    fi
    if ! write_home_takeover_state owned; then
        log_event "home_role_owned_state_failed"
        return 1
    fi
    if ! module_is_active; then
        write_home_takeover_state \
            "pending|$takeover_boot_id|$refreshed_home_holder" && \
            rollback_home_after_inactive_takeover || \
            log_event "home_role_inactive_rollback_failed"
        return 1
    fi
    log_event "home_role_repaired"
    return 0
}

repair_home_role() {
    if ! acquire_home_transaction_lock; then
        log_event "home_role_transaction_lock_failed"
        return 1
    fi
    if repair_home_role_locked; then
        home_repair_status=0
    else
        home_repair_status=$?
    fi
    if ! release_home_transaction_lock; then
        log_event "home_role_transaction_unlock_failed"
        home_repair_status=1
    fi
    return "$home_repair_status"
}

install_cleanup_helper() {
    source_path="$1"
    cleanup_dir=${CLEANUP_TARGET%/*}
    temp_path="$CLEANUP_TARGET.tmp.$$"

    if [ -L "$CLEANUP_TARGET" ] || [ -d "$CLEANUP_TARGET" ]; then
        log_event "uninstall_cleanup_target_invalid"
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
    cleanup_helper_ready "$source_path"
}

repair_accessibility() {
    if [ -e "$ACCESSIBILITY_TRANSACTION_MARKER" ] || \
        [ -L "$ACCESSIBILITY_TRANSACTION_MARKER" ]; then
        restore_accessibility_transaction || return 1
        module_is_active || return 1
    fi
    if ! run_guard_command pm path --user "$ANDROID_USER_ID" "$PACKAGE_NAME" >/dev/null 2>&1; then
        log_event "package_missing"
        return 1
    fi
    module_is_active || return 1

    if ! run_guard_command pm enable --user "$ANDROID_USER_ID" "$PACKAGE_NAME" >/dev/null 2>&1; then
        log_event "package_enable_failed"
        return 1
    fi
    module_is_active || return 1
    if ! run_guard_command pm enable --user "$ANDROID_USER_ID" "$ACCESSIBILITY_COMPONENT" >/dev/null 2>&1; then
        log_event "service_enable_failed"
        return 1
    fi
    module_is_active || return 1

    if ! current="$(run_guard_command settings --user "$ANDROID_USER_ID" get secure enabled_accessibility_services 2>/dev/null)"; then
        log_event "accessibility_services_read_failed"
        return 1
    fi
    case "$current" in
        null|NULL|"") current="" ;;
        *[![:space:]]*) ;;
        *) current="" ;;
    esac
    module_is_active || return 1
    if ! enabled="$(run_guard_command settings --user "$ANDROID_USER_ID" get secure accessibility_enabled 2>/dev/null)"; then
        log_event "accessibility_enabled_read_failed"
        return 1
    fi
    case "$enabled" in
        0|1) ;;
        null|NULL|"") enabled=0 ;;
        *)
            log_event "accessibility_enabled_invalid"
            return 1
            ;;
    esac
    module_is_active || return 1

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
    accessibility_alternate="$(remove_accessibility_service \
        "$merged" "$ACCESSIBILITY_COMPONENT")"
    accessibility_transaction_started=0
    accessibility_changed=0
    if [ "$merged" != "$current" ] || [ "$enabled" != "1" ]; then
        if ! write_accessibility_transaction "$enabled" 1 "$current" \
            "$merged" "$accessibility_alternate"; then
            log_event "accessibility_transaction_start_failed"
            return 1
        fi
        accessibility_transaction_started=1
    fi
    if [ "$merged" != "$current" ]; then
        if ! run_guard_command settings --user "$ANDROID_USER_ID" put secure \
            enabled_accessibility_services "$merged" >/dev/null 2>&1; then
            restore_accessibility_after_interrupted_rebind "$merged" "$current" \
                "$enabled" "$enabled" || \
                log_event "accessibility_repair_compensation_failed"
            log_event "accessibility_services_write_failed"
            return 1
        fi
        if ! module_is_active; then
            restore_accessibility_after_interrupted_rebind "$merged" "$current" \
                "$enabled" "$enabled" || \
                log_event "accessibility_repair_compensation_failed"
            return 1
        fi
        accessibility_changed=1
    fi

    if [ "$enabled" != "1" ]; then
        if ! run_guard_command settings --user "$ANDROID_USER_ID" put secure \
            accessibility_enabled 1 >/dev/null 2>&1; then
            restore_accessibility_after_interrupted_rebind "$merged" "$current" \
                1 "$enabled" || \
                log_event "accessibility_repair_compensation_failed"
            log_event "accessibility_enabled_write_failed"
            return 1
        fi
        if ! module_is_active; then
            restore_accessibility_after_interrupted_rebind "$merged" "$current" \
                1 "$enabled" || \
                log_event "accessibility_repair_compensation_failed"
            return 1
        fi
        accessibility_changed=1
    fi

    if [ "$accessibility_changed" -eq 1 ]; then
        log_event "accessibility_repaired"
    fi

    binding_state="$(accessibility_service_binding_state)"
    if ! module_is_active; then
        if [ "$accessibility_transaction_started" -eq 1 ]; then
            restore_accessibility_after_interrupted_rebind "$merged" "$current" \
                1 "$enabled" || \
                log_event "accessibility_repair_compensation_failed"
        fi
        return 1
    fi
    case "$binding_state" in
        crashed)
            if [ "$accessibility_transaction_started" -eq 0 ]; then
                if ! write_accessibility_transaction "$enabled" 1 "$current" \
                    "$merged" "$accessibility_alternate"; then
                    log_event "accessibility_transaction_start_failed"
                    return 1
                fi
                accessibility_transaction_started=1
            fi
            if ! rebind_accessibility_service "$current" "$merged" "$enabled"; then
                if [ "$accessibility_transaction_started" -eq 1 ]; then
                    restore_accessibility_after_interrupted_rebind "$merged" "$current" \
                        1 "$enabled" || \
                        log_event "accessibility_repair_compensation_failed"
                fi
                return 1
            fi
            ;;
        unbound)
            if [ "$target_was_fully_enabled" -eq 1 ]; then
                if [ "$accessibility_transaction_started" -eq 0 ]; then
                    if ! write_accessibility_transaction "$enabled" 1 \
                        "$current" "$merged" "$accessibility_alternate"; then
                        log_event "accessibility_transaction_start_failed"
                        return 1
                    fi
                    accessibility_transaction_started=1
                fi
                if ! rebind_accessibility_service "$current" "$merged" "$enabled"; then
                    if [ "$accessibility_transaction_started" -eq 1 ]; then
                        restore_accessibility_after_interrupted_rebind \
                            "$merged" "$current" 1 "$enabled" || \
                            log_event "accessibility_repair_compensation_failed"
                    fi
                    return 1
                fi
            fi
            ;;
    esac
    if ! module_is_active; then
        if [ "$accessibility_transaction_started" -eq 1 ]; then
            restore_accessibility_after_interrupted_rebind "$merged" "$current" \
                1 "$enabled" || \
                log_event "accessibility_repair_compensation_failed"
        fi
        return 1
    fi
    if [ "$accessibility_transaction_started" -eq 1 ]; then
        clear_accessibility_transaction || {
            log_event "accessibility_transaction_clear_failed"
            return 1
        }
    fi
    return 0
}

valid_doze_marker_value() {
    case "$1" in
        added) return 0 ;;
        pending\|*)
            pending_boot_id=${1#pending|}
            [ -n "$pending_boot_id" ] || return 1
            case "$pending_boot_id" in
                *[!A-Za-z0-9._-]*) return 1 ;;
            esac
            [ "${#pending_boot_id}" -le 128 ]
            ;;
        *) return 1 ;;
    esac
}

read_doze_ownership_marker() {
    [ ! -L "$DOZE_OWNERSHIP_MARKER" ] && \
        [ -f "$DOZE_OWNERSHIP_MARKER" ] || return 1
    if ! doze_marker_output="$(
        cat "$DOZE_OWNERSHIP_MARKER" 2>/dev/null
        doze_marker_status=$?
        printf '|'
        exit "$doze_marker_status"
    )"; then
        return 1
    fi
    case "$doze_marker_output" in
        *'|') doze_marker_output=${doze_marker_output%|} ;;
        *) return 1 ;;
    esac
    line_feed='
'
    case "$doze_marker_output" in
        *"$line_feed") doze_marker_output=${doze_marker_output%"$line_feed"} ;;
        *) return 1 ;;
    esac
    case "$doze_marker_output" in
        *"$line_feed"*) return 1 ;;
    esac
    valid_doze_marker_value "$doze_marker_output" || return 1
    printf '%s\n' "$doze_marker_output"
}

write_doze_ownership_marker() {
    doze_marker_value="$1"
    valid_doze_marker_value "$doze_marker_value" || return 1
    ensure_state_dir || return 1
    if [ -e "$DOZE_OWNERSHIP_MARKER" ] || [ -L "$DOZE_OWNERSHIP_MARKER" ]; then
        if [ -L "$DOZE_OWNERSHIP_MARKER" ] || \
            [ ! -f "$DOZE_OWNERSHIP_MARKER" ]; then
            log_event "doze_marker_invalid"
            return 1
        fi
    fi

    doze_marker_tmp="$DOZE_OWNERSHIP_MARKER.tmp.$$"
    rm -f "$doze_marker_tmp" 2>/dev/null || true
    if ! { printf '%s\n' "$doze_marker_value" > "$doze_marker_tmp"; } 2>/dev/null || \
        ! chmod 0600 "$doze_marker_tmp" 2>/dev/null || \
        ! mv -f "$doze_marker_tmp" "$DOZE_OWNERSHIP_MARKER" 2>/dev/null; then
        rm -f "$doze_marker_tmp" 2>/dev/null || true
        log_event "doze_marker_write_failed"
        return 1
    fi
    if ! published_doze_value="$(read_doze_ownership_marker)" || \
        [ "$published_doze_value" != "$doze_marker_value" ]; then
        log_event "doze_marker_changed"
        return 1
    fi
    if ! run_guard_command "$HOME_MARKER_SYNC_COMMAND" -f \
        "$DOZE_OWNERSHIP_MARKER" "$STATE_DIR" >/dev/null 2>&1; then
        log_event "doze_marker_sync_failed"
        return 1
    fi
    if ! synced_doze_value="$(read_doze_ownership_marker)" || \
        [ "$synced_doze_value" != "$doze_marker_value" ]; then
        log_event "doze_marker_changed"
        return 1
    fi
    return 0
}

doze_contains_package() {
    if ! output="$(run_guard_command cmd deviceidle whitelist 2>/dev/null)"; then
        log_event "doze_whitelist_read_failed"
        return 2
    fi
    printf '%s\n' "$output" | tr ',[:space:]' '\n' | grep -Fx "$PACKAGE_NAME" >/dev/null 2>&1
}

current_guard_boot_id() {
    boot_id_file="${YINXING_GUARD_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"
    sanitize_boot_id "$(read_boot_id_from "$boot_id_file")"
}

clear_doze_ownership_marker() {
    if [ ! -e "$DOZE_OWNERSHIP_MARKER" ] && \
        [ ! -L "$DOZE_OWNERSHIP_MARKER" ]; then
        return 0
    fi
    read_doze_ownership_marker >/dev/null || return 1
    rm -f "$DOZE_OWNERSHIP_MARKER" 2>/dev/null || return 1
    run_guard_command "$HOME_MARKER_SYNC_COMMAND" -f "$STATE_DIR" \
        >/dev/null 2>&1 || return 1
    [ ! -e "$DOZE_OWNERSHIP_MARKER" ] && \
        [ ! -L "$DOZE_OWNERSHIP_MARKER" ]
}

repair_keepalive_locked() {
    module_is_active || return 1
    state_ready=1
    if ! ensure_state_dir; then
        state_ready=0
    fi

    doze_marker_present=0
    doze_marker_value=""
    if [ -e "$DOZE_OWNERSHIP_MARKER" ] || [ -L "$DOZE_OWNERSHIP_MARKER" ]; then
        if ! doze_marker_value="$(read_doze_ownership_marker)"; then
            log_event "doze_marker_invalid"
            return 1
        fi
        doze_marker_present=1
    fi

    doze_contains_package
    doze_status=$?
    module_is_active || return 1

    if [ "$doze_marker_present" -eq 1 ]; then
        case "$doze_status" in
            0)
                if [ "$doze_marker_value" != added ]; then
                    write_doze_ownership_marker added || {
                        log_event "doze_marker_promote_failed"
                        return 1
                    }
                    module_is_active || return 1
                fi
                ;;
            1)
                case "$doze_marker_value" in
                    pending\|*)
                        doze_pending_boot=${doze_marker_value#pending|}
                        if [ "$doze_pending_boot" = "$(current_guard_boot_id)" ]; then
                            log_event "doze_pending_same_boot"
                            return 1
                        fi
                        ;;
                esac
                if ! clear_doze_ownership_marker; then
                    log_event "doze_stale_marker_clear_failed"
                    return 1
                fi
                doze_marker_present=0
                doze_marker_value=""
                module_is_active || return 1
                ;;
            *)
                log_event "doze_whitelist_state_unresolved"
                return 1
                ;;
        esac
    fi

    if [ "$doze_marker_present" -eq 0 ] && [ "$doze_status" -eq 1 ]; then
        if [ "$state_ready" -ne 1 ]; then
            log_event "doze_whitelist_skipped_no_state"
        elif ! cleanup_helper_ready "${CLEANUP_SOURCE:-}"; then
            log_event "doze_whitelist_skipped_no_cleanup"
        else
            module_is_active || return 1
            doze_boot_id="$(current_guard_boot_id)"
            if ! write_doze_ownership_marker "pending|$doze_boot_id"; then
                log_event "doze_pending_marker_failed"
                return 1
            fi
            if ! module_is_active; then
                clear_doze_ownership_marker || \
                    log_event "doze_pending_marker_clear_failed"
                return 1
            fi

            doze_contains_package
            doze_status_after_marker=$?
            case "$doze_status_after_marker" in
                0)
                    clear_doze_ownership_marker || {
                        log_event "doze_pending_marker_clear_failed"
                        return 1
                    }
                    log_event "doze_whitelist_appeared_before_add"
                    ;;
                1)
                    module_is_active || return 1
                    run_guard_command cmd deviceidle whitelist "+$PACKAGE_NAME" \
                        >/dev/null 2>&1
                    doze_add_status=$?
                    doze_contains_package
                    doze_status_after_add=$?
                    case "$doze_status_after_add" in
                        0)
                            if ! write_doze_ownership_marker added; then
                                log_event "doze_marker_promote_failed"
                                return 1
                            fi
                            if ! module_is_active; then
                                log_event "doze_add_completed_after_module_inactive"
                                return 1
                            fi
                            [ "$doze_add_status" -eq 0 ] || \
                                log_event "doze_whitelist_applied_after_error"
                            ;;
                        1)
                            log_event "doze_whitelist_unconfirmed"
                            return 1
                            ;;
                        *)
                            log_event "doze_whitelist_confirmation_unknown"
                            return 1
                            ;;
                    esac
                    ;;
                *)
                    log_event "doze_whitelist_requery_failed"
                    return 1
                    ;;
            esac
        fi
    elif [ "$doze_status" -ne 0 ] && [ "$doze_status" -ne 1 ]; then
        log_event "doze_whitelist_optional_query_failed"
    fi

    module_is_active || return 1
    run_guard_command cmd appops set --user "$ANDROID_USER_ID" "$PACKAGE_NAME" RUN_IN_BACKGROUND allow \
        >/dev/null 2>&1 || log_event "background_appop_unsupported"
    module_is_active || return 1
    run_guard_command cmd appops set --user "$ANDROID_USER_ID" "$PACKAGE_NAME" RUN_ANY_IN_BACKGROUND allow \
        >/dev/null 2>&1 || log_event "any_background_appop_unsupported"
    module_is_active || return 1
    return 0
}

repair_keepalive() {
    if ! acquire_home_transaction_lock; then
        log_event "doze_transaction_lock_failed"
        return 1
    fi
    if repair_keepalive_locked; then
        doze_repair_status=0
    else
        doze_repair_status=$?
    fi
    if ! release_home_transaction_lock; then
        log_event "doze_transaction_unlock_failed"
        doze_repair_status=1
    fi
    return "$doze_repair_status"
}

repair_state() {
    module_is_active || return 1
    if ! acquire_home_transaction_lock; then
        log_event "repair_transaction_lock_failed"
        return 1
    fi
    repair_accessibility
    repair_state_status=$?
    if [ "$repair_state_status" -eq 0 ]; then
        module_is_active || repair_state_status=1
    fi
    if [ "$repair_state_status" -eq 0 ]; then
        repair_home_role_locked
        repair_state_status=$?
    fi
    if [ "$repair_state_status" -eq 0 ]; then
        module_is_active || repair_state_status=1
    fi
    if [ "$repair_state_status" -eq 0 ]; then
        repair_keepalive_locked
        repair_state_status=$?
    fi
    if [ "$repair_state_status" -eq 0 ]; then
        module_is_active || repair_state_status=1
    fi
    if ! release_home_transaction_lock; then
        log_event "repair_transaction_unlock_failed"
        repair_state_status=1
    fi
    return "$repair_state_status"
}

launch_home() {
    if ! module_is_active; then
        log_event "home_launch_skipped_module_inactive"
        return 1
    fi
    run_guard_command am start --user "$ANDROID_USER_ID" -n "$HOME_COMPONENT" >/dev/null 2>&1 || {
        log_event "home_launch_failed"
        return 1
    }
    if ! module_is_active; then
        log_event "home_launch_completed_after_module_inactive"
        return 1
    fi
    log_event "home_launched"
    return 0
}
