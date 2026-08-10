#!/system/bin/sh

PACKAGE_NAME="com.yinxing.launcher"
ACCESSIBILITY_COMPONENT="com.yinxing.launcher/com.google.android.accessibility.selecttospeak.SelectToSpeakService"
HOME_COMPONENT="com.yinxing.launcher/.feature.home.MainActivity"
HOME_ROLE_NAME="android.app.role.HOME"
ANDROID_USER_ID="0"
STATE_DIR="${YINXING_GUARD_STATE_DIR:-/data/adb/yinxing_guard}"
LOG_TAG="YinxingGuard"
MODULE_VERSION="1.10.0-root-preview.17"
MARKER="$STATE_DIR/doze_added_by_module"
HOME_MARKER="$STATE_DIR/home_previous_holder"
HOME_STATE_MARKER="$STATE_DIR/home_takeover_state"
HOME_TRANSACTION_LOCK_DIR="$STATE_DIR/home_transaction.lock"
HOME_TRANSACTION_RECLAIM_DIR="$STATE_DIR/home_transaction.reclaim"
ACCESSIBILITY_MARKER="$STATE_DIR/accessibility_transaction"
SELF_PATH="$0"
MODULE_DIR="${YINXING_GUARD_TEST_MODULE_DIR:-/data/adb/modules/yinxing_guard}"
HOME_MARKER_SYNC_COMMAND="${YINXING_GUARD_HOME_MARKER_SYNC_COMMAND:-sync}"
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

path_exists() {
    [ -e "$1" ] || [ -L "$1" ]
}

read_marker_line() {
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
    case "$marker_output" in
        *"$line_feed"*) return 1 ;;
    esac
    printf '%s\n' "$marker_output"
}

cleanup_runtime_state() {
    runtime_cleanup_status=0
    rm -f \
        "$STATE_DIR/guard.pid" \
        "$STATE_DIR/guard.boot_id" \
        "$STATE_DIR/last_repair" \
        "$STATE_DIR/last_repair.tmp."* \
        "$STATE_DIR/accessibility_transaction.tmp."* \
        "$STATE_DIR/accessibility_binding_stall" \
        "$STATE_DIR/accessibility_binding_stall.tmp."* \
        "$STATE_DIR/home_foreground_evidence" \
        "$STATE_DIR/home_foreground_evidence.tmp."* \
        "$STATE_DIR/doze_added_by_module.tmp."* \
        "$STATE_DIR/home_previous_holder.tmp."* \
        "$STATE_DIR/home_takeover_state.tmp."* || runtime_cleanup_status=1
    rm -rf "$STATE_DIR/guard.lock" || runtime_cleanup_status=1
    return "$runtime_cleanup_status"
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

merge_accessibility_services() {
    current_services="$1"
    component="$2"
    case "$current_services" in
        null|NULL|"") current_services="" ;;
        *[![:space:]]*) ;;
        *) current_services="" ;;
    esac
    case ":$current_services:" in
        *":$component:"*) printf '%s\n' "$current_services" ;;
        "::") printf '%s\n' "$component" ;;
        *) printf '%s:%s\n' "$current_services" "$component" ;;
    esac
}

remove_accessibility_service() {
    current_services="$1"
    component="$2"
    case "$current_services" in
        null|NULL|"") current_services="" ;;
    esac
    printf '%s\n' "$current_services" | awk -v target="$component" -F: '
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

normalize_accessibility_enabled() {
    case "$1" in
        0|1) printf '%s\n' "$1" ;;
        null|NULL|"") printf '0\n' ;;
        *) return 1 ;;
    esac
}

cleanup_accessibility_transaction() {
    path_exists "$ACCESSIBILITY_MARKER" || return 0
    if ! accessibility_state="$(read_marker_line "$ACCESSIBILITY_MARKER")" || \
        ! parse_accessibility_transaction_state "$accessibility_state"; then
        log_event "uninstall_accessibility_transaction_invalid"
        return 1
    fi

    if ! observed_services="$(run_guard_command settings --user \
        "$ANDROID_USER_ID" get secure enabled_accessibility_services \
        2>/dev/null)"; then
        log_event "uninstall_accessibility_services_read_failed"
        return 1
    fi
    case "$observed_services" in
        null|NULL) observed_services="" ;;
    esac
    if ! confirmed_services="$(run_guard_command settings --user \
        "$ANDROID_USER_ID" get secure enabled_accessibility_services \
        2>/dev/null)"; then
        log_event "uninstall_accessibility_services_confirm_failed"
        return 1
    fi
    case "$confirmed_services" in
        null|NULL) confirmed_services="" ;;
    esac
    if [ "$confirmed_services" != "$observed_services" ]; then
        log_event "uninstall_accessibility_services_unstable"
        return 1
    fi
    if [ "$observed_services" = "$accessibility_original_services" ]; then
        :
    elif [ "$observed_services" = "$accessibility_primary_services" ] || \
        [ "$observed_services" = "$accessibility_alternate_services" ]; then
        if ! run_guard_command settings --user "$ANDROID_USER_ID" put secure \
            enabled_accessibility_services "$accessibility_original_services" \
            >/dev/null 2>&1; then
            log_event "uninstall_accessibility_services_restore_failed"
            return 1
        fi
        if ! restored_services="$(run_guard_command settings --user \
            "$ANDROID_USER_ID" get secure enabled_accessibility_services \
            2>/dev/null)"; then
            return 1
        fi
        case "$restored_services" in
            null|NULL) restored_services="" ;;
        esac
        [ "$restored_services" = "$accessibility_original_services" ] || \
            return 1
    else
        log_event "uninstall_accessibility_preserved_new_services"
    fi

    observed_enabled_raw="$(run_guard_command settings --user "$ANDROID_USER_ID" \
        get secure accessibility_enabled 2>/dev/null)" || return 1
    observed_enabled="$(normalize_accessibility_enabled \
        "$observed_enabled_raw")" || return 1
    confirmed_enabled_raw="$(run_guard_command settings --user \
        "$ANDROID_USER_ID" get secure accessibility_enabled 2>/dev/null)" || \
        return 1
    confirmed_enabled="$(normalize_accessibility_enabled \
        "$confirmed_enabled_raw")" || return 1
    if [ "$confirmed_enabled" != "$observed_enabled" ]; then
        log_event "uninstall_accessibility_enabled_unstable"
        return 1
    fi
    if [ "$observed_enabled" = "$accessibility_original_enabled" ]; then
        :
    elif [ "$observed_enabled" = "$accessibility_temporary_enabled" ]; then
        if ! run_guard_command settings --user "$ANDROID_USER_ID" put secure \
            accessibility_enabled "$accessibility_original_enabled" \
            >/dev/null 2>&1; then
            log_event "uninstall_accessibility_enabled_restore_failed"
            return 1
        fi
        restored_enabled_raw="$(run_guard_command settings --user \
            "$ANDROID_USER_ID" get secure accessibility_enabled \
            2>/dev/null)" || return 1
        restored_enabled="$(normalize_accessibility_enabled \
            "$restored_enabled_raw")" || return 1
        [ "$restored_enabled" = "$accessibility_original_enabled" ] || \
            return 1
    else
        log_event "uninstall_accessibility_preserved_new_enabled"
    fi

    rm -f "$ACCESSIBILITY_MARKER" 2>/dev/null || return 1
    run_guard_command "$HOME_MARKER_SYNC_COMMAND" -f "$STATE_DIR" \
        >/dev/null 2>&1 || return 1
    if path_exists "$ACCESSIBILITY_MARKER"; then
        return 1
    fi
    log_event "uninstall_accessibility_transaction_restored"
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

read_current_boot_id() {
    boot_id_file="${YINXING_GUARD_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"
    boot_id="$(cat "$boot_id_file" 2>/dev/null || true)"
    if [ -z "$boot_id" ]; then
        boot_id="$(awk '/^btime / { print $2; exit }' /proc/stat 2>/dev/null || true)"
    fi
    if [ -z "$boot_id" ]; then
        boot_id="$(run_guard_command getprop ro.runtime.firstboot 2>/dev/null || true)"
    fi
    boot_id="$(printf '%s' "$boot_id" | tr -c 'A-Za-z0-9._-' '_')"
    [ -n "$boot_id" ] || boot_id=unknown
    printf '%s\n' "$boot_id"
}

process_start_time() {
    process_pid="$1"
    process_proc_root="${YINXING_GUARD_PROC_ROOT:-/proc}"
    process_stat="$(cat "$process_proc_root/$process_pid/stat" 2>/dev/null || true)"
    [ -n "$process_stat" ] || return 1
    process_start="$(printf '%s\n' "$process_stat" | \
        awk '{ sub(/^.*\) /, ""); print $20; exit }')"
    case "$process_start" in
        ''|*[!0-9]*) return 1 ;;
        *) printf '%s\n' "$process_start" ;;
    esac
}

home_transaction_owner_is_active() {
    home_lock_pid="$(cat "$HOME_TRANSACTION_LOCK_DIR/pid" 2>/dev/null || true)"
    home_lock_boot="$(cat "$HOME_TRANSACTION_LOCK_DIR/boot_id" 2>/dev/null || true)"
    case "$home_lock_pid" in
        ''|*[!0-9]*) return 2 ;;
    esac
    kill -0 "$home_lock_pid" 2>/dev/null || return 1
    [ -n "$home_lock_boot" ] || return 0
    [ "$home_lock_boot" = "$(read_current_boot_id)" ] || return 1
    home_expected_start="$(cat "$HOME_TRANSACTION_LOCK_DIR/start_time" \
        2>/dev/null || true)"
    case "$home_expected_start" in
        '') return 0 ;;
        *[!0-9]*) return 0 ;;
    esac
    home_actual_start="$(process_start_time "$home_lock_pid" 2>/dev/null || true)"
    [ -n "$home_actual_start" ] || return 0
    [ "$home_expected_start" = "$home_actual_start" ]
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
    mkdir -p "$STATE_DIR" 2>/dev/null || return 1
    home_lock_attempt_limit="${YINXING_GUARD_HOME_LOCK_ATTEMPTS:-5}"
    case "$home_lock_attempt_limit" in
        ''|*[!0-9]*|0) home_lock_attempt_limit=5 ;;
    esac
    home_lock_attempt=0
    while [ "$home_lock_attempt" -lt "$home_lock_attempt_limit" ]; do
        if [ -L "$HOME_TRANSACTION_LOCK_DIR" ] || \
            [ -L "$HOME_TRANSACTION_RECLAIM_DIR" ]; then
            log_event "uninstall_home_lock_invalid"
            return 1
        fi
        if [ -d "$HOME_TRANSACTION_RECLAIM_DIR" ]; then
            home_reclaim_pid="$(cat "$HOME_TRANSACTION_RECLAIM_DIR/pid" \
                2>/dev/null || true)"
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
            home_lock_boot="$(read_current_boot_id)"
            home_lock_start="$(process_start_time "$$" 2>/dev/null || true)"
            if ! printf '%s\n' "$$" > "$HOME_TRANSACTION_LOCK_DIR/pid" \
                    2>/dev/null || \
                ! printf '%s\n' "$home_lock_boot" > \
                    "$HOME_TRANSACTION_LOCK_DIR/boot_id" 2>/dev/null || \
                { [ -n "$home_lock_start" ] && \
                    ! printf '%s\n' "$home_lock_start" > \
                        "$HOME_TRANSACTION_LOCK_DIR/start_time" 2>/dev/null; }; then
                release_home_transaction_lock
                rm -f "$HOME_TRANSACTION_LOCK_DIR/boot_id" \
                    "$HOME_TRANSACTION_LOCK_DIR/start_time" 2>/dev/null || true
                rmdir "$HOME_TRANSACTION_LOCK_DIR" 2>/dev/null || true
                return 1
            fi
            return 0
        fi
        [ -d "$HOME_TRANSACTION_LOCK_DIR" ] || return 1
        home_transaction_owner_is_active
        home_owner_status=$?
        case "$home_owner_status" in
            0)
                log_event "uninstall_home_lock_busy"
                return 1
                ;;
            2)
                if [ "$home_lock_attempt" -lt $((home_lock_attempt_limit - 1)) ]; then
                    home_lock_attempt=$((home_lock_attempt + 1))
                    sleep 1
                    continue
                fi
                ;;
        esac
        if mkdir "$HOME_TRANSACTION_RECLAIM_DIR" 2>/dev/null; then
            if ! printf '%s\n' "$$" > "$HOME_TRANSACTION_RECLAIM_DIR/pid" \
                    2>/dev/null; then
                release_home_transaction_reclaim
                return 1
            fi
            home_transaction_owner_is_active
            home_checked_status=$?
            case "$home_checked_status" in
                0)
                    release_home_transaction_reclaim
                    log_event "uninstall_home_lock_busy"
                    return 1
                    ;;
                2)
                    sleep 1
                    home_transaction_owner_is_active
                    home_checked_status=$?
                    if [ "$home_checked_status" -eq 0 ]; then
                        release_home_transaction_reclaim
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
    return 1
}

valid_home_holder() {
    [ "$1" != "$PACKAGE_NAME" ] && valid_android_package_name "$1"
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

write_home_takeover_state() {
    takeover_state="$1"
    valid_home_takeover_state "$takeover_state" || return 1
    mkdir -p "$STATE_DIR" 2>/dev/null || return 1
    if path_exists "$HOME_STATE_MARKER" && \
        { [ -L "$HOME_STATE_MARKER" ] || [ ! -f "$HOME_STATE_MARKER" ]; }; then
        return 1
    fi
    state_tmp="$HOME_STATE_MARKER.tmp.$$"
    rm -f "$state_tmp" 2>/dev/null || true
    if ! { printf '%s\n' "$takeover_state" > "$state_tmp"; } 2>/dev/null || \
        ! chmod 0600 "$state_tmp" 2>/dev/null || \
        ! mv -f "$state_tmp" "$HOME_STATE_MARKER" 2>/dev/null; then
        rm -f "$state_tmp" 2>/dev/null || true
        return 1
    fi
    if ! published_state="$(read_marker_line "$HOME_STATE_MARKER")" || \
        [ "$published_state" != "$takeover_state" ]; then
        return 1
    fi
    run_guard_command "$HOME_MARKER_SYNC_COMMAND" -f \
        "$HOME_STATE_MARKER" "$STATE_DIR" >/dev/null 2>&1 || return 1
    synced_state="$(read_marker_line "$HOME_STATE_MARKER")" || return 1
    [ "$synced_state" = "$takeover_state" ]
}

clear_home_evidence() {
    if path_exists "$HOME_MARKER"; then
        marker_holder="$(read_marker_line "$HOME_MARKER")" || return 1
        [ "$marker_holder" = none ] || valid_home_holder "$marker_holder" || return 1
    fi
    if path_exists "$HOME_STATE_MARKER"; then
        marker_state="$(read_marker_line "$HOME_STATE_MARKER")" || return 1
        [ "$marker_state" = released ] || return 1
    fi
    if path_exists "$HOME_MARKER"; then
        rm -f "$HOME_MARKER" 2>/dev/null || return 1
        run_guard_command "$HOME_MARKER_SYNC_COMMAND" -f "$STATE_DIR" \
            >/dev/null 2>&1 || return 1
    fi
    if path_exists "$HOME_STATE_MARKER"; then
        rm -f "$HOME_STATE_MARKER" 2>/dev/null || return 1
        run_guard_command "$HOME_MARKER_SYNC_COMMAND" -f "$STATE_DIR" \
            >/dev/null 2>&1 || return 1
    fi
    return 0
}

release_home_evidence() {
    write_home_takeover_state released || return 1
    clear_home_evidence
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
        *"$line_feed") resolver_output=${resolver_output%"$line_feed"} ;;
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
    printf '%s\n' "$resolver_package/$resolver_class"
}

home_resolver_state() {
    if ! resolved_component="$(read_home_resolved_component)"; then
        printf 'unknown\n'
        return 1
    fi
    case "$resolved_component" in
        none) printf 'none\n' ;;
        "$HOME_COMPONENT"|"$PACKAGE_NAME/$PACKAGE_NAME.feature.home.MainActivity")
            printf 'target\n'
            ;;
        *) printf 'other\n' ;;
    esac
}

home_resolver_matches_holder() {
    expected_holder="$1"
    if ! resolved_component="$(read_home_resolved_component)"; then
        return 1
    fi
    if [ "$expected_holder" = "none" ]; then
        if [ "$resolved_component" = "none" ]; then
            return 0
        fi
        [ "$resolved_component" != "none" ] || return 1
        resolved_package=${resolved_component%%/*}
        [ "$resolved_package" != "$PACKAGE_NAME" ]
        return $?
    fi
    [ "$resolved_component" != "none" ] || return 1
    resolved_package=${resolved_component%%/*}
    [ "$resolved_package" = "$expected_holder" ]
}

home_route_safe_for_release() {
    home_resolver_matches_holder none || {
        log_event "uninstall_home_release_route_unconfirmed"
        return 1
    }
    return 0
}

released_home_evidence_is_safe() {
    if ! released_current_home="$(read_home_role_holder)"; then
        log_event "uninstall_home_released_role_query_failed"
        return 1
    fi
    if [ "$released_current_home" = "$PACKAGE_NAME" ]; then
        return 0
    fi
    home_route_safe_for_release
}

release_home_evidence_after_check() {
    release_expected_holder="$1"
    release_route_mode="$2"
    case "$release_route_mode" in
        safe|exact) ;;
        *) return 1 ;;
    esac
    if ! release_retry_state="$(read_marker_line "$HOME_STATE_MARKER")"; then
        return 1
    fi
    case "$release_retry_state" in
        owned|pending\|*) ;;
        *) return 1 ;;
    esac
    if ! release_before_holder="$(read_home_role_holder)"; then
        log_event "uninstall_home_release_holder_query_failed"
        return 1
    fi
    if [ "$release_route_mode" = safe ]; then
        [ "$release_before_holder" != "$PACKAGE_NAME" ] || return 1
        home_route_safe_for_release || return 1
    else
        [ "$release_before_holder" = "$release_expected_holder" ] || return 1
        home_resolver_matches_holder "$release_expected_holder" || return 1
    fi
    if ! write_home_takeover_state released; then
        write_home_takeover_state "$release_retry_state" || \
            log_event "uninstall_home_release_state_restore_failed"
        return 1
    fi
    if ! release_after_holder="$(read_home_role_holder)" || \
        [ "$release_after_holder" != "$release_before_holder" ]; then
        log_event "uninstall_home_release_holder_changed"
        write_home_takeover_state "$release_retry_state" || \
            log_event "uninstall_home_release_state_restore_failed"
        return 1
    fi
    if [ "$release_route_mode" = safe ]; then
        home_route_safe_for_release || {
            write_home_takeover_state "$release_retry_state" || \
                log_event "uninstall_home_release_state_restore_failed"
            return 1
        }
    else
        home_resolver_matches_holder "$release_expected_holder" || {
            write_home_takeover_state "$release_retry_state" || \
                log_event "uninstall_home_release_state_restore_failed"
            return 1
        }
    fi
    if ! release_after_route_holder="$(read_home_role_holder)" || \
        [ "$release_after_route_holder" != "$release_before_holder" ]; then
        log_event "uninstall_home_release_holder_changed_after_route"
        write_home_takeover_state "$release_retry_state" || \
            log_event "uninstall_home_release_state_restore_failed"
        return 1
    fi
    clear_home_evidence
}

retry_home_restore_route_locked() {
    restore_holder="$1"
    [ "$restore_holder" != "none" ] || return 1
    if ! run_guard_command cmd package set-home-activity --user "$ANDROID_USER_ID" \
        "$restore_holder" >/dev/null 2>&1; then
        log_event "uninstall_home_restore_route_set_failed"
        return 1
    fi
    if ! retry_confirmed_holder="$(read_home_role_holder)" || \
        [ "$retry_confirmed_holder" != "$restore_holder" ]; then
        log_event "uninstall_home_restore_route_holder_unconfirmed"
        return 1
    fi
    home_resolver_matches_holder "$restore_holder"
}

cleanup_home_role_locked() {
    if ! path_exists "$HOME_MARKER" && ! path_exists "$HOME_STATE_MARKER"; then
        return 0
    fi
    original_home=""
    takeover_state=""
    if path_exists "$HOME_MARKER"; then
        if ! original_home="$(read_marker_line "$HOME_MARKER")" || \
            { [ "$original_home" != none ] && ! valid_home_holder "$original_home"; }; then
            log_event "uninstall_home_marker_invalid"
            return 1
        fi
    fi
    if path_exists "$HOME_STATE_MARKER"; then
        if ! takeover_state="$(read_marker_line "$HOME_STATE_MARKER")" || \
            ! valid_home_takeover_state "$takeover_state"; then
            log_event "uninstall_home_state_marker_invalid"
            return 1
        fi
    fi
    case "$takeover_state" in
        owned|pending\|*)
            if [ -z "$original_home" ]; then
                log_event "uninstall_home_state_without_marker"
                return 1
            fi
            ;;
        released)
            released_home_evidence_is_safe || return 1
            clear_home_evidence || return 1
            log_event "uninstall_home_released_state_cleared"
            return 0
            ;;
        "")
            release_home_evidence || return 1
            log_event "uninstall_home_unarmed_marker_cleared"
            return 0
            ;;
    esac
    previous_home="$original_home"
    pending_boot=""
    case "$takeover_state" in
        owned) ;;
        pending\|*)
            pending_remainder=${takeover_state#pending|}
            pending_boot=${pending_remainder%%|*}
            previous_home=${pending_remainder#*|}
            ;;
        *) return 1 ;;
    esac
    if ! current_home="$(read_home_role_holder)"; then
        log_event "uninstall_home_query_failed"
        return 1
    fi

    if [ "$current_home" != "$PACKAGE_NAME" ]; then
        sleep 1
        if ! confirmed_new_home="$(read_home_role_holder)"; then
            log_event "uninstall_home_preserve_confirm_failed"
            return 1
        fi
        if [ "$confirmed_new_home" != "$PACKAGE_NAME" ]; then
            if [ "$confirmed_new_home" != "$current_home" ]; then
                log_event "uninstall_home_preserve_unstable"
                return 1
            fi
            if [ "$confirmed_new_home" = "$previous_home" ] && \
                ! home_resolver_matches_holder "$previous_home"; then
                if [ "$previous_home" = "none" ] || \
                    ! retry_route_state="$(home_resolver_state)" || \
                    [ "$retry_route_state" != target ] || \
                    ! retry_home_restore_route_locked "$previous_home"; then
                    log_event "uninstall_home_preserve_route_unconfirmed"
                    return 1
                fi
            fi
            if [ -n "$pending_boot" ] && \
                [ "$pending_boot" = "$(read_current_boot_id)" ]; then
                log_event "uninstall_home_pending_same_boot"
                return 1
            fi
            if [ "$confirmed_new_home" != "$previous_home" ]; then
                home_route_safe_for_release || return 1
            fi
            release_home_evidence_after_check "$confirmed_new_home" safe || return 1
            log_event "uninstall_home_preserved_new_choice"
            return 0
        fi
        current_home="$confirmed_new_home"
    fi

    if [ "$previous_home" = "none" ]; then
        if ! current_before_remove="$(read_home_role_holder)"; then
            log_event "uninstall_home_pre_remove_query_failed"
            return 1
        fi
        if [ "$current_before_remove" != "$PACKAGE_NAME" ]; then
            if [ -n "$pending_boot" ] && \
                [ "$pending_boot" = "$(read_current_boot_id)" ]; then
                log_event "uninstall_home_pending_same_boot"
                return 1
            fi
            home_route_safe_for_release || return 1
            release_home_evidence_after_check "$current_before_remove" safe || return 1
            log_event "uninstall_home_preserved_new_choice"
            return 0
        fi
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
        if ! home_route_safe_for_release; then
            log_event "uninstall_home_remove_route_unconfirmed"
            return 1
        fi
    else
        if ! run_guard_command pm path --user "$ANDROID_USER_ID" "$previous_home" \
            >/dev/null 2>&1; then
            log_event "uninstall_home_previous_missing"
            return 1
        fi
        if ! current_before_restore="$(read_home_role_holder)"; then
            log_event "uninstall_home_pre_restore_query_failed"
            return 1
        fi
        if [ "$current_before_restore" != "$PACKAGE_NAME" ]; then
            if [ -n "$pending_boot" ] && \
                [ "$pending_boot" = "$(read_current_boot_id)" ]; then
                log_event "uninstall_home_pending_same_boot"
                return 1
            fi
            home_route_safe_for_release || return 1
            release_home_evidence_after_check "$current_before_restore" safe || return 1
            log_event "uninstall_home_preserved_new_choice"
            return 0
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
        if ! home_resolver_matches_holder "$previous_home"; then
            log_event "uninstall_home_restore_route_unconfirmed"
            return 1
        fi
    fi

    if [ -n "$pending_boot" ] && \
        [ "$pending_boot" = "$(read_current_boot_id)" ]; then
        log_event "uninstall_home_pending_compensated_same_boot"
        return 1
    fi
    release_home_evidence_after_check "$previous_home" exact || return 1
    log_event "uninstall_home_cleanup_complete"
    return 0
}

cleanup_home_role() {
    if ! path_exists "$HOME_MARKER" && ! path_exists "$HOME_STATE_MARKER"; then
        return 0
    fi
    if ! acquire_home_transaction_lock; then
        log_event "uninstall_home_lock_failed"
        return 1
    fi
    if cleanup_home_role_locked; then
        home_cleanup_status=0
    else
        home_cleanup_status=$?
    fi
    release_home_transaction_lock || home_cleanup_status=1
    return "$home_cleanup_status"
}

cleanup_doze() {
    path_exists "$MARKER" || return 0
    if ! marker_value="$(read_marker_line "$MARKER")" || \
        ! valid_doze_marker_value "$marker_value"; then
        log_event "uninstall_marker_invalid"
        return 1
    fi
    marker_kind="$marker_value"
    marker_boot=""
    case "$marker_value" in
        pending\|*)
            marker_kind=pending
            marker_boot=${marker_value#pending|}
            ;;
    esac
    if ! doze_output="$(run_guard_command cmd deviceidle whitelist 2>/dev/null)"; then
        log_event "uninstall_doze_query_deferred"
        return 1
    fi
    if printf '%s\n' "$doze_output" | tr ',[:space:]' '\n' | \
        grep -Fx "$PACKAGE_NAME" >/dev/null 2>&1; then
        run_guard_command cmd deviceidle whitelist "-$PACKAGE_NAME" \
            >/dev/null 2>&1
        doze_remove_status=$?
        if ! doze_after_remove="$(run_guard_command cmd deviceidle whitelist \
            2>/dev/null)"; then
            log_event "uninstall_doze_remove_confirmation_deferred"
            return 1
        fi
        if printf '%s\n' "$doze_after_remove" | tr ',[:space:]' '\n' | \
            grep -Fx "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_event "uninstall_doze_remove_unconfirmed"
            return 1
        fi
        [ "$doze_remove_status" -eq 0 ] || \
            log_event "uninstall_doze_removed_after_error"
    elif [ "$marker_kind" = pending ] && \
        [ "$marker_boot" = "$(read_current_boot_id)" ]; then
        log_event "uninstall_doze_pending_same_boot"
        return 1
    fi
    rm -f "$MARKER" || return 1
    run_guard_command "$HOME_MARKER_SYNC_COMMAND" -f "$STATE_DIR" \
        >/dev/null 2>&1 || return 1
    if [ "$marker_kind" = pending ]; then
        log_event "uninstall_doze_pending_resolved"
    else
        log_event "uninstall_doze_cleanup_complete"
    fi
    return 0
}

cleanup_transaction() {
    if ! acquire_home_transaction_lock; then
        log_event "uninstall_transaction_lock_failed"
        return 1
    fi

    cleanup_failed=0
    cleanup_accessibility_transaction || cleanup_failed=1
    cleanup_home_role_locked || cleanup_failed=1
    cleanup_doze || cleanup_failed=1

    if [ "$cleanup_failed" -ne 0 ] || path_exists "$ACCESSIBILITY_MARKER" || \
        path_exists "$HOME_MARKER" || path_exists "$HOME_STATE_MARKER" || \
        path_exists "$MARKER"; then
        release_home_transaction_lock || cleanup_failed=1
        return 1
    fi

    cleanup_runtime_state || cleanup_failed=1
    if ! release_home_transaction_lock; then
        cleanup_failed=1
    fi
    if [ "$cleanup_failed" -eq 0 ]; then
        rmdir "$STATE_DIR" 2>/dev/null || true
    fi
    return "$cleanup_failed"
}

if [ -d "$MODULE_DIR" ] && [ ! -f "$MODULE_DIR/remove" ]; then
    exit 0
fi

if ! cleanup_transaction; then
    exit 1
fi
log_event "uninstall_cleanup_complete"
rm -f "$SELF_PATH"
exit 0
