#!/system/bin/sh

MODDIR=${0%/*}
PATH="/data/adb/ksu/bin:/system/bin:/system/xbin:${PATH:-}"
export PATH
. "$MODDIR/bin/common.sh"

marker="$STATE_DIR/doze_added_by_module"
if [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "added" ]; then
    cmd deviceidle whitelist "-$PACKAGE_NAME" >/dev/null 2>&1 || \
        log_event "doze_whitelist_remove_failed"
fi

rm -f "$marker" "$STATE_DIR/guard.pid" "$STATE_DIR/guard.boot_id"
rmdir "$STATE_DIR" 2>/dev/null || true
log_event "module_uninstalled"
