#!/system/bin/sh

MODDIR=${0%/*}
PATH="/data/adb/ksu/bin:/system/bin:/system/xbin:${PATH:-}"
export PATH
. "$MODDIR/bin/common.sh"

install_cleanup_helper "$MODDIR/bin/uninstall-cleanup.sh" || true
repair_state || exit 1
launch_home
