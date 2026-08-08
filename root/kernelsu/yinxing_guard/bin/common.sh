#!/system/bin/sh

PACKAGE_NAME="com.yinxing.launcher"
ACCESSIBILITY_COMPONENT="com.yinxing.launcher/com.google.android.accessibility.selecttospeak.SelectToSpeakService"
HOME_COMPONENT="com.yinxing.launcher/.feature.home.MainActivity"
ANDROID_USER_ID="0"
STATE_DIR="${YINXING_GUARD_STATE_DIR:-/data/adb/yinxing_guard}"
LOG_TAG="YinxingGuard"

log_event() {
    message="$1"
    if command -v log >/dev/null 2>&1; then
        log -t "$LOG_TAG" -- "$message" 2>/dev/null || true
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

repair_accessibility() {
    if ! pm path --user "$ANDROID_USER_ID" "$PACKAGE_NAME" >/dev/null 2>&1; then
        log_event "package_missing"
        return 1
    fi

    pm enable --user "$ANDROID_USER_ID" "$PACKAGE_NAME" >/dev/null 2>&1 || \
        log_event "package_enable_failed"
    pm enable --user "$ANDROID_USER_ID" "$ACCESSIBILITY_COMPONENT" >/dev/null 2>&1 || \
        log_event "service_enable_failed"

    current="$(settings --user "$ANDROID_USER_ID" get secure enabled_accessibility_services 2>/dev/null || true)"
    merged="$(merge_accessibility_services "$current" "$ACCESSIBILITY_COMPONENT")"
    accessibility_changed=0
    if [ "$merged" != "$current" ]; then
        settings --user "$ANDROID_USER_ID" put secure enabled_accessibility_services "$merged" || {
            log_event "accessibility_services_write_failed"
            return 1
        }
        accessibility_changed=1
    fi

    enabled="$(settings --user "$ANDROID_USER_ID" get secure accessibility_enabled 2>/dev/null || true)"
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
    output="$(cmd deviceidle whitelist 2>/dev/null || true)"
    printf '%s\n' "$output" | grep -Eq "(^|[[:space:],])${PACKAGE_NAME}([[:space:],]|$)"
}

repair_keepalive() {
    ensure_state_dir || true

    if ! doze_contains_package; then
        if cmd deviceidle whitelist "+$PACKAGE_NAME" >/dev/null 2>&1; then
            printf 'added\n' > "$STATE_DIR/doze_added_by_module" 2>/dev/null || \
                log_event "doze_marker_write_failed"
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
