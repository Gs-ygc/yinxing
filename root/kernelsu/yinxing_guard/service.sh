#!/system/bin/sh

MODDIR=${0%/*}
PATH="/data/adb/ksu/bin:/system/bin:/system/xbin:${PATH:-}"
export PATH

. "$MODDIR/bin/common.sh"
install_cleanup_helper "$MODDIR/bin/uninstall-cleanup.sh" || true

LOCK_RETRY_SECONDS=${YINXING_GUARD_LOCK_RETRY_SECONDS:-5}
case "$LOCK_RETRY_SECONDS" in
    ''|*[!0-9]*) LOCK_RETRY_SECONDS=5 ;;
esac

(
    while :; do
        sh "$MODDIR/bin/guard.sh"
        guard_status=$?
        [ "$guard_status" -eq 75 ] || exit 0
        sleep "$LOCK_RETRY_SECONDS"
    done
) >/dev/null 2>&1 &
