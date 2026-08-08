#!/system/bin/sh

MODDIR=${0%/*}
PATH="/data/adb/ksu/bin:/system/bin:/system/xbin:${PATH:-}"
export PATH
. "$MODDIR/bin/common.sh"

repair_state || exit 1
launch_home
