#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
MODULE_DIR="$REPO_ROOT/root/kernelsu/yinxing_guard"

usage() {
    printf 'usage: %s OUTPUT_ZIP [MODULE_VERSION]\n' "${0##*/}" >&2
    exit 2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

[ "$#" -ge 1 ] || usage
OUTPUT="$1"
VERSION="${2:-}"

command -v zip >/dev/null 2>&1 || die "zip is required"
command -v unzip >/dev/null 2>&1 || die "unzip is required"
[ -d "$MODULE_DIR" ] || die "module source is missing: $MODULE_DIR"

MODULE_ABS="$(cd "$MODULE_DIR" && pwd -P)"
OUTPUT_DIR="$(dirname "$OUTPUT")"
OUTPUT_NAME="$(basename "$OUTPUT")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_ABS="$(cd "$OUTPUT_DIR" && pwd -P)/$OUTPUT_NAME"
case "$OUTPUT_ABS" in
    "$MODULE_ABS"|"$MODULE_ABS"/*) die "output must not be inside the module source" ;;
esac

for required in module.prop skip_mount service.sh action.sh uninstall.sh bin/common.sh bin/guard.sh; do
    [ -f "$MODULE_DIR/$required" ] || die "required module file is missing: $required"
done

if [ -n "$VERSION" ]; then
    case "$VERSION" in
        *[!A-Za-z0-9._-]*) die "module version contains unsupported characters" ;;
    esac
fi

STAGING="$(mktemp -d)"
cleanup() {
    rm -rf "$STAGING"
}
trap cleanup EXIT

cp -a "$MODULE_DIR"/. "$STAGING"/
if [ -n "$VERSION" ]; then
    sed -i "s/^version=.*/version=$VERSION/" "$STAGING/module.prop"
fi

chmod 0755 \
    "$STAGING/service.sh" \
    "$STAGING/action.sh" \
    "$STAGING/uninstall.sh" \
    "$STAGING/bin/common.sh" \
    "$STAGING/bin/guard.sh"

rm -f -- "$OUTPUT_ABS"
(
    cd "$STAGING"
    zip -X -q -r "$OUTPUT_ABS" \
        module.prop \
        skip_mount \
        service.sh \
        action.sh \
        uninstall.sh \
        bin
)

unzip -t "$OUTPUT_ABS" >/dev/null || die "created ZIP failed integrity check"
printf '%s\n' "$OUTPUT_ABS"
