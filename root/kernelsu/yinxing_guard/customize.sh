for script in \
    service.sh \
    action.sh \
    uninstall.sh \
    bin/common.sh \
    bin/guard.sh \
    bin/status.sh \
    bin/uninstall-cleanup.sh \
    bin/kiosk-home.sh; do
    set_perm "$MODPATH/$script" 0 0 0755 || \
        abort "! Failed to make $script executable"
done
