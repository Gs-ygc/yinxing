#!/system/bin/sh

PACKAGE_NAME="com.yinxing.launcher"
STATE_DIR="${YINXING_GUARD_STATE_DIR:-/data/adb/yinxing_guard}"
LOG_TAG="YinxingGuard"
MODULE_VERSION="1.10.0-root-preview.9"
MARKER="$STATE_DIR/doze_added_by_module"
SELF_PATH="$0"
MODULE_DIR="${YINXING_GUARD_TEST_MODULE_DIR:-/data/adb/modules/yinxing_guard}"

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
        "$STATE_DIR/doze_added_by_module.tmp."*
    rm -rf "$STATE_DIR/guard.lock"
    rmdir "$STATE_DIR" 2>/dev/null || true
}

if [ -d "$MODULE_DIR" ] && [ ! -f "$MODULE_DIR/remove" ]; then
    exit 0
fi

if [ ! -f "$MARKER" ]; then
    cleanup_runtime_state
    rm -f "$SELF_PATH"
    exit 0
fi

if [ "$(cat "$MARKER" 2>/dev/null)" != "added" ]; then
    log_event "uninstall_marker_invalid"
    exit 1
fi

if ! cmd deviceidle whitelist "-$PACKAGE_NAME" >/dev/null 2>&1; then
    log_event "uninstall_doze_cleanup_deferred"
    exit 1
fi

rm -f "$MARKER"
cleanup_runtime_state
log_event "uninstall_doze_cleanup_complete"
rm -f "$SELF_PATH"
exit 0
