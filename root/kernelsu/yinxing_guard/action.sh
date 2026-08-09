#!/system/bin/sh

MODDIR=${0%/*}
PATH="/data/adb/ksu/bin:/system/bin:/system/xbin:${PATH:-}"
export PATH
CLEANUP_SOURCE="$MODDIR/bin/uninstall-cleanup.sh"
. "$MODDIR/bin/common.sh"

if ! module_is_active; then
    log_event "action_module_inactive"
    exit 1
fi
install_cleanup_helper "$CLEANUP_SOURCE" || exit 1
cleanup_helper_ready "$CLEANUP_SOURCE" || exit 1
module_is_active || exit 1
if ! repair_state; then
    record_repair_result failed || true
    exit 1
fi
record_repair_result ok || true
launch_home
