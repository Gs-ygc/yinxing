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
command -v realpath >/dev/null 2>&1 || die "realpath is required"
[ -d "$MODULE_DIR" ] || die "module source is missing: $MODULE_DIR"

MODULE_ABS="$(cd "$MODULE_DIR" && pwd -P)"
[ ! -L "$OUTPUT" ] || die "output must not be a symbolic link"
OUTPUT_ABS="$(realpath -m -- "$OUTPUT")"
case "$OUTPUT_ABS" in
    "$MODULE_ABS"|"$MODULE_ABS"/*) die "output must not be inside the module source" ;;
esac
[ ! -d "$OUTPUT_ABS" ] || die "output must be a file path"
OUTPUT_DIR="$(dirname "$OUTPUT_ABS")"
mkdir -p "$OUTPUT_DIR"

for required in module.prop skip_mount service.sh action.sh uninstall.sh bin/common.sh bin/guard.sh bin/status.sh bin/uninstall-cleanup.sh; do
    [ -f "$MODULE_DIR/$required" ] || die "required module file is missing: $required"
done

if [ -n "$VERSION" ]; then
    case "$VERSION" in
        *[!A-Za-z0-9._-]*) die "module version contains unsupported characters" ;;
    esac
fi

STAGING="$(mktemp -d)"
OUTPUT_TMP="$(mktemp "$OUTPUT_DIR/.yinxing-guard.XXXXXX.zip")"
rm -f -- "$OUTPUT_TMP"
cleanup() {
    rm -rf "$STAGING"
    rm -f -- "$OUTPUT_TMP"
}
trap cleanup EXIT

cp -a "$MODULE_DIR"/. "$STAGING"/
if [ -n "$VERSION" ]; then
    sed -i "s/^version=.*/version=$VERSION/" "$STAGING/module.prop"
    sed -i "s/^MODULE_VERSION=.*/MODULE_VERSION=\"$VERSION\"/" \
        "$STAGING/bin/common.sh" \
        "$STAGING/bin/uninstall-cleanup.sh"
fi

chmod 0755 \
    "$STAGING/service.sh" \
    "$STAGING/action.sh" \
    "$STAGING/uninstall.sh" \
    "$STAGING/bin/common.sh" \
    "$STAGING/bin/guard.sh" \
    "$STAGING/bin/status.sh" \
    "$STAGING/bin/uninstall-cleanup.sh"

find "$STAGING" -exec touch -t 198001010000 {} +

(
    cd "$STAGING"
    zip -X -q "$OUTPUT_TMP" \
        module.prop \
        skip_mount \
        service.sh \
        action.sh \
        uninstall.sh \
        bin/ \
        bin/common.sh \
        bin/guard.sh \
        bin/status.sh \
        bin/uninstall-cleanup.sh
)

unzip -t "$OUTPUT_TMP" >/dev/null || die "created ZIP failed integrity check"
mv -f -- "$OUTPUT_TMP" "$OUTPUT_ABS"
printf '%s\n' "$OUTPUT_ABS"
