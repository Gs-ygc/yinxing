#!/system/bin/sh

MODULE_DIR="${YINXING_GUARD_TEST_MODULE_DIR:-/data/adb/modules/yinxing_guard}"

if [ ! -d "$MODULE_DIR" ] || [ -e "$MODULE_DIR/disable" ] || [ -e "$MODULE_DIR/remove" ]; then
    exit 1
fi

SCRIPT_DIR=${0%/*}
. "$SCRIPT_DIR/common.sh"
launch_home
