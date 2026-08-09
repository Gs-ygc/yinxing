#!/system/bin/sh

MODDIR=${0%/*}
PATH="/data/adb/ksu/bin:/system/bin:/system/xbin:${PATH:-}"
export PATH
. "$MODDIR/bin/common.sh"

doze_marker="$STATE_DIR/doze_added_by_module"
home_marker="$STATE_DIR/home_previous_holder"
cleanup_source="$MODDIR/bin/uninstall-cleanup.sh"
cleanup_target="$CLEANUP_TARGET"

rm -f \
    "$STATE_DIR/guard.pid" \
    "$STATE_DIR/guard.boot_id" \
    "$STATE_DIR/last_repair" \
    "$STATE_DIR/last_repair.tmp."* \
    "$STATE_DIR/doze_added_by_module.tmp."* \
    "$STATE_DIR/home_previous_holder.tmp."*
rm -rf "$STATE_DIR/guard.lock"

if [ -f "$doze_marker" ] || [ -f "$home_marker" ]; then
    if ! install_cleanup_helper "$cleanup_source"; then
        log_event "uninstall_cleanup_schedule_failed"
        exit 1
    fi
else
    rm -f "$cleanup_target"
    rmdir "$STATE_DIR" 2>/dev/null || true
fi

log_event "module_uninstalled"
