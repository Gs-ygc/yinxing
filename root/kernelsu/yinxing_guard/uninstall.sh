#!/system/bin/sh

MODDIR=${0%/*}
PATH="/data/adb/ksu/bin:/system/bin:/system/xbin:${PATH:-}"
export PATH
. "$MODDIR/bin/common.sh"

marker="$STATE_DIR/doze_added_by_module"
cleanup_source="$MODDIR/bin/uninstall-cleanup.sh"
cleanup_target="$CLEANUP_TARGET"

rm -f \
    "$STATE_DIR/guard.pid" \
    "$STATE_DIR/guard.boot_id" \
    "$STATE_DIR/last_repair"
rm -rf "$STATE_DIR/guard.lock"

if [ -f "$marker" ]; then
    install_cleanup_helper "$cleanup_source" || true
else
    rm -f "$cleanup_target"
    rmdir "$STATE_DIR" 2>/dev/null || true
fi

log_event "module_uninstalled"
