#!/system/bin/sh

MODDIR=${0%/*}
PATH="/data/adb/ksu/bin:/system/bin:/system/xbin:${PATH:-}"
export PATH
. "$MODDIR/bin/common.sh"

install_cleanup_helper "$MODDIR/bin/uninstall-cleanup.sh" || true
if ! repair_state; then
    record_repair_result failed || true
    exit 1
fi
record_repair_result ok || true
launch_home
