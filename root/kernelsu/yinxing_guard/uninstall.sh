#!/system/bin/sh

MODDIR=${0%/*}
PATH="/data/adb/ksu/bin:/system/bin:/system/xbin:${PATH:-}"
export PATH
. "$MODDIR/bin/common.sh"

doze_marker="$STATE_DIR/doze_added_by_module"
accessibility_marker="$STATE_DIR/accessibility_transaction"
home_marker="$STATE_DIR/home_previous_holder"
home_takeover_state_marker="$STATE_DIR/home_takeover_state"
cleanup_source="$MODDIR/bin/uninstall-cleanup.sh"
cleanup_target="$CLEANUP_TARGET"

path_exists() {
    [ -e "$1" ] || [ -L "$1" ]
}

if ! acquire_home_transaction_lock; then
    log_event "uninstall_transaction_lock_failed"
    exit 1
fi

uninstall_status=0
rm -f \
    "$STATE_DIR/guard.pid" \
    "$STATE_DIR/guard.boot_id" \
    "$STATE_DIR/last_repair" \
    "$STATE_DIR/last_repair.tmp."* \
    "$STATE_DIR/accessibility_transaction.tmp."* \
    "$STATE_DIR/doze_added_by_module.tmp."* \
    "$STATE_DIR/home_previous_holder.tmp."* \
    "$STATE_DIR/home_takeover_state.tmp."* || uninstall_status=1
rm -rf "$STATE_DIR/guard.lock" || uninstall_status=1

if path_exists "$accessibility_marker" || path_exists "$doze_marker" || \
    path_exists "$home_marker" || path_exists "$home_takeover_state_marker"; then
    if ! install_cleanup_helper "$cleanup_source"; then
        log_event "uninstall_cleanup_schedule_failed"
        uninstall_status=1
    fi
else
    rm -f "$cleanup_target" || uninstall_status=1
fi

if ! release_home_transaction_lock; then
    uninstall_status=1
fi
if [ "$uninstall_status" -eq 0 ]; then
    rmdir "$STATE_DIR" 2>/dev/null || true
else
    exit 1
fi

log_event "module_uninstalled"
