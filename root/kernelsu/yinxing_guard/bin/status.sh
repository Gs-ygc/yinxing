#!/system/bin/sh

MODDIR=${0%/*}
CLEANUP_SOURCE="$MODDIR/uninstall-cleanup.sh"
. "$MODDIR/common.sh"

MODULE_DIR="${YINXING_GUARD_TEST_MODULE_DIR:-/data/adb/modules/yinxing_guard}"
BOOT_ID_FILE="${YINXING_GUARD_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"
CURRENT_BOOT_ID="$(read_boot_id_from "$BOOT_ID_FILE")"
LOCK_BOOT_ID="$(sanitize_boot_id "$CURRENT_BOOT_ID")"
LOCK_DIR="$STATE_DIR/guard.lock/$LOCK_BOOT_ID"

emit_status() {
    printf '%s=%s\n' "$1" "$2"
}

module_state() {
    if [ ! -d "$MODULE_DIR" ]; then
        printf 'missing\n'
    elif [ -f "$MODULE_DIR/remove" ]; then
        printf 'removing\n'
    elif [ -f "$MODULE_DIR/disable" ]; then
        printf 'disabled\n'
    else
        printf 'active\n'
    fi
}

guard_state() {
    if [ ! -d "$MODULE_DIR" ]; then
        printf 'missing\n'
        return
    fi
    if [ ! -f "$LOCK_DIR/pid" ]; then
        printf 'missing\n'
        return
    fi
    guard_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    case "$guard_pid" in
        ''|*[!0-9]*)
            printf 'unknown\n'
            ;;
        *)
            if kill -0 "$guard_pid" 2>/dev/null; then
                if [ "$(guard_owner_identity_state "$LOCK_DIR" "$guard_pid")" = "mismatch" ]; then
                    printf 'stale\n'
                else
                    printf 'running\n'
                fi
            else
                printf 'stale\n'
            fi
            ;;
    esac
}

package_enabled_state() {
    if ! disabled_packages="$(run_guard_command pm list packages -d --user "$ANDROID_USER_ID" "$PACKAGE_NAME" 2>/dev/null)"; then
        printf 'unknown\n'
        return
    fi
    if printf '%s\n' "$disabled_packages" | grep -Fx "package:$PACKAGE_NAME" >/dev/null 2>&1; then
        printf 'disabled\n'
    else
        printf 'enabled\n'
    fi
}

component_enabled_state() {
    if ! package_dump="$(run_guard_command pm dump "$PACKAGE_NAME" 2>/dev/null)"; then
        printf 'unknown\n'
        return
    fi
    component_class="${ACCESSIBILITY_COMPONENT#*/}"
    if ! printf '%s\n' "$package_dump" | grep -F "$component_class" >/dev/null 2>&1; then
        printf 'unknown\n'
        return
    fi
    disabled_components="$(printf '%s\n' "$package_dump" | sed -n '/disabledComponents:/,/enabledComponents:/p')"
    if printf '%s\n' "$disabled_components" | grep -F "$component_class" >/dev/null 2>&1; then
        printf 'disabled\n'
    else
        printf 'enabled\n'
    fi
}

accessibility_state() {
    if [ ! -d "$MODULE_DIR" ] || \
        ! run_guard_command pm path --user "$ANDROID_USER_ID" "$PACKAGE_NAME" >/dev/null 2>&1; then
        printf 'missing\n'
        return
    fi
    package_state="$(package_enabled_state)"
    case "$package_state" in
        disabled)
            printf 'disabled\n'
            return
            ;;
        unknown)
            printf 'unknown\n'
            return
            ;;
    esac
    component_state="$(component_enabled_state)"
    case "$component_state" in
        disabled)
            printf 'disabled\n'
            return
            ;;
        unknown)
            printf 'unknown\n'
            return
            ;;
    esac
    if ! current_services="$(run_guard_command settings --user "$ANDROID_USER_ID" get secure enabled_accessibility_services 2>/dev/null)" || \
        ! enabled_state="$(run_guard_command settings --user "$ANDROID_USER_ID" get secure accessibility_enabled 2>/dev/null)"; then
        printf 'unknown\n'
        return
    fi
    case ":$current_services:" in
        *":$ACCESSIBILITY_COMPONENT:"*)
            if [ "$enabled_state" = "1" ]; then
                case "$(accessibility_service_binding_state)" in
                    crashed|unbound) printf 'stale\n' ;;
                    binding)
                        if accessibility_binding_stall_is_persistent; then
                            printf 'stale\n'
                        else
                            printf 'enabled\n'
                        fi
                        ;;
                    *) printf 'enabled\n' ;;
                esac
            else
                printf 'disabled\n'
            fi
            ;;
        *)
            printf 'disabled\n'
            ;;
    esac
}

doze_state() {
    if [ ! -d "$MODULE_DIR" ]; then
        printf 'unknown\n'
        return
    fi
    doze_contains_package
    doze_status=$?
    case "$doze_status" in
        2)
            printf 'unknown\n'
            ;;
        0)
            if [ "$(read_doze_ownership_marker 2>/dev/null || true)" = "added" ]; then
                printf 'owned\n'
            else
                printf 'present\n'
            fi
            ;;
        *)
            printf 'absent\n'
            ;;
    esac
}

cleanup_state() {
    if cleanup_helper_ready "$CLEANUP_SOURCE"; then
        printf 'ready\n'
    elif [ -e "$CLEANUP_TARGET" ] || [ -L "$CLEANUP_TARGET" ]; then
        printf 'invalid\n'
    else
        printf 'missing\n'
    fi
}

last_repair_state() {
    last_repair="$(cat "$STATE_DIR/last_repair" 2>/dev/null || true)"
    case "$last_repair" in
        ok|failed) printf '%s\n' "$last_repair" ;;
        *) printf 'unknown\n' ;;
    esac
}

module_value="$(module_state)"
guard_value="$(guard_state)"
accessibility_value="$(accessibility_state)"
if [ "$module_value" = "missing" ]; then
    home_value="unknown"
    home_foreground_value="unknown"
else
    home_value="$(home_role_state)"
    if [ "$home_value" = "owned" ]; then
        home_foreground_value="$(home_foreground_evidence_state)"
    else
        home_foreground_value="unknown"
    fi
fi
doze_value="$(doze_state)"
cleanup_value="$(cleanup_state)"
last_repair_value="$(last_repair_state)"

emit_status schema 3
emit_status version "$MODULE_VERSION"
emit_status module "$module_value"
emit_status guard "$guard_value"
emit_status accessibility "$accessibility_value"
emit_status home "$home_value"
emit_status home_foreground "$home_foreground_value"
emit_status doze "$doze_value"
emit_status cleanup "$cleanup_value"
emit_status last_repair "$last_repair_value"
exit 0
