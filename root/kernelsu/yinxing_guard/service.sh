#!/system/bin/sh

MODDIR=${0%/*}
PATH="/data/adb/ksu/bin:/system/bin:/system/xbin:${PATH:-}"
export PATH

"$MODDIR/bin/guard.sh" >/dev/null 2>&1 &
