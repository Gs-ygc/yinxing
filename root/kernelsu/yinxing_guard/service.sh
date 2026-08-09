#!/system/bin/sh

MODDIR=${0%/*}
PATH="/data/adb/ksu/bin:/system/bin:/system/xbin:${PATH:-}"
export PATH

CLEANUP_SOURCE="$MODDIR/bin/uninstall-cleanup.sh"
. "$MODDIR/bin/common.sh"
install_cleanup_helper "$CLEANUP_SOURCE" || true

LOCK_RETRY_SECONDS=${YINXING_GUARD_LOCK_RETRY_SECONDS:-5}
case "$LOCK_RETRY_SECONDS" in
    ''|*[!0-9]*) LOCK_RETRY_SECONDS=5 ;;
esac

RESTART_SECONDS=${YINXING_GUARD_RESTART_SECONDS:-30}
case "$RESTART_SECONDS" in
    ''|*[!0-9]*) RESTART_SECONDS=30 ;;
esac

OWNER_RETRY_SECONDS=${YINXING_GUARD_OWNER_RETRY_SECONDS:-30}
case "$OWNER_RETRY_SECONDS" in
    ''|*[!0-9]*) OWNER_RETRY_SECONDS=30 ;;
esac

(
    while module_is_active; do
        sh "$MODDIR/bin/guard.sh"
        guard_status=$?
        module_is_active || exit 0
        case "$guard_status" in
            0)
                exit 0
                ;;
            "$GUARD_OWNER_ACTIVE_STATUS")
                sleep "$OWNER_RETRY_SECONDS"
                ;;
            75)
                sleep "$LOCK_RETRY_SECONDS"
                ;;
            *)
                log_event "guard_unexpected_exit=$guard_status"
                sleep "$RESTART_SECONDS"
                ;;
        esac
    done
) >/dev/null 2>&1 &
