#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MODULE_ROOT="$REPO_ROOT/root/kernelsu/yinxing_guard"
MODE="${1:-all}"
TEST_ROOT="$(mktemp -d)"
FAKE_BIN="$TEST_ROOT/bin"
CALLS="$TEST_ROOT/calls.log"
SERVICES="$TEST_ROOT/accessibility_services"
ACCESSIBILITY_ENABLED="$TEST_ROOT/accessibility_enabled"

cleanup() {
    if [[ -n "${LIVE_PID:-}" ]]; then
        kill "$LIVE_PID" 2>/dev/null || true
        wait "$LIVE_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN"
: > "$CALLS"
: > "$SERVICES"
printf '0\n' > "$ACCESSIBILITY_ENABLED"
export TEST_ROOT FAKE_BIN CALLS SERVICES ACCESSIBILITY_ENABLED
export YINXING_GUARD_STATE_DIR="$TEST_ROOT/state"
export PATH="$FAKE_BIN:$PATH"

run_module_script() {
    if [[ "${YINXING_TEST_SHELL:-}" == "busybox" ]]; then
        busybox ash "$@"
    else
        sh "$@"
    fi
}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

pass() {
    printf 'PASS: %s\n' "$*"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    if [[ "$expected" != "$actual" ]]; then
        fail "$message (expected='$expected' actual='$actual')"
    fi
}

assert_contains() {
    local file="$1"
    local value="$2"
    grep -F -- "$value" "$file" >/dev/null || fail "missing '$value' in $file"
}

assert_not_contains() {
    local file="$1"
    local value="$2"
    if grep -F -- "$value" "$file" >/dev/null; then
        fail "unexpected '$value' in $file"
    fi
}

write_fake() {
    local name="$1"
    shift
    printf '%s\n' "$@" > "$FAKE_BIN/$name"
    chmod +x "$FAKE_BIN/$name"
}

write_fake settings \
    '#!/usr/bin/env bash' \
    'printf "settings %s\\n" "$*" >> "$CALLS"' \
    'shift_if_user() { if [[ "${1:-}" == "--user" ]]; then shift 2; fi; printf "%s" "$*"; }' \
    'args=("$@"); if [[ "${args[0]:-}" == "--user" ]]; then args=("${args[@]:2}"); fi' \
    'if [[ "${args[0]:-}" == "get" ]]; then if [[ "${args[2]:-}" == "enabled_accessibility_services" ]]; then [[ -s "$SERVICES" ]] && cat "$SERVICES" || printf "null\\n"; elif [[ "${args[2]:-}" == "accessibility_enabled" ]]; then cat "$ACCESSIBILITY_ENABLED"; else exit 2; fi; exit 0; fi' \
    'if [[ "${args[0]:-}" == "put" ]]; then [[ -e "$TEST_ROOT/fail_settings_put" ]] && exit 1; if [[ "${args[2]:-}" == "enabled_accessibility_services" ]]; then printf "%s\\n" "${args[3]:-}" > "$SERVICES"; elif [[ "${args[2]:-}" == "accessibility_enabled" ]]; then printf "%s\\n" "${args[3]:-}" > "$ACCESSIBILITY_ENABLED"; fi; exit 0; fi' \
    'exit 2'

write_fake pm \
    '#!/usr/bin/env bash' \
    'printf "pm %s\\n" "$*" >> "$CALLS"' \
    'args=("$@"); if [[ "${args[0]:-}" == "--user" ]]; then args=("${args[@]:2}"); fi' \
    'if [[ "${args[0]:-}" == "path" ]]; then [[ -e "$TEST_ROOT/package_missing" ]] && exit 1; printf "/data/app/com.yinxing.launcher/base.apk\\n"; exit 0; fi' \
    'if [[ "${args[0]:-}" == "enable" ]]; then exit 0; fi' \
    'exit 2'

write_fake cmd \
    '#!/usr/bin/env bash' \
    'printf "cmd %s\\n" "$*" >> "$CALLS"' \
    'if [[ "${1:-}" == "appops" && -e "$TEST_ROOT/fail_appops" ]]; then exit 1; fi' \
    'if [[ "${1:-}" == "deviceidle" && "${2:-}" == "whitelist" && $# -eq 2 ]]; then [[ -e "$TEST_ROOT/doze_whitelisted" ]] && printf "user,%s\\n" "com.yinxing.launcher"; exit 0; fi' \
    'if [[ "${1:-}" == "deviceidle" && "${2:-}" == "whitelist" && "${3:-}" == +com.yinxing.launcher ]]; then printf added > "$TEST_ROOT/doze_whitelisted"; fi' \
    'if [[ "${1:-}" == "deviceidle" && "${2:-}" == "whitelist" && "${3:-}" == -com.yinxing.launcher ]]; then rm -f "$TEST_ROOT/doze_whitelisted"; fi' \
    'exit 0'

write_fake am \
    '#!/usr/bin/env bash' \
    'printf "am %s\\n" "$*" >> "$CALLS"' \
    'printf launched > "$TEST_ROOT/home_launched"'

write_fake getprop \
    '#!/usr/bin/env bash' \
    'printf "getprop %s\\n" "$*" >> "$CALLS"' \
    '[[ "${1:-}" == "sys.boot_completed" ]] && printf "1\\n"'

write_fake log \
    '#!/usr/bin/env bash' \
    'printf "log %s\\n" "$*" >> "$CALLS"'

write_fake sleep \
    '#!/usr/bin/env bash' \
    'printf "sleep %s\\n" "$*" >> "$CALLS"'

# This is intentionally a RED test until the module implementation exists.
# The assertions describe observable state and command effects, not source text.
source "$MODULE_ROOT/bin/common.sh"

reset_fixture() {
    : > "$CALLS"
    : > "$SERVICES"
    printf '0\n' > "$ACCESSIBILITY_ENABLED"
    rm -f \
        "$TEST_ROOT/package_missing" \
        "$TEST_ROOT/fail_appops" \
        "$TEST_ROOT/fail_settings_put" \
        "$TEST_ROOT/home_launched" \
        "$TEST_ROOT/doze_whitelisted"
    rm -rf "$TEST_ROOT/state"
}

test_merge_cases() {
    local component="$ACCESSIBILITY_COMPONENT"
    assert_equals "$component" "$(merge_accessibility_services null "$component")" "empty accessibility list"
    assert_equals "$component" "$(merge_accessibility_services '   ' "$component")" "whitespace accessibility list"
    assert_equals "talkback:other:$component" "$(merge_accessibility_services 'talkback:other' "$component")" "preserve existing services"
    assert_equals "talkback:$component" "$(merge_accessibility_services "talkback:$component" "$component")" "do not duplicate service"
    assert_equals "talkback:${component}2:$component" "$(merge_accessibility_services "talkback:${component}2" "$component")" "avoid substring collision"
    pass "merge cases"
}

test_repair_preserves_and_enables() {
    reset_fixture
    printf 'talkback:other\n' > "$SERVICES"
    repair_state || fail "repair_state should succeed for installed package"
    assert_equals "talkback:other:$ACCESSIBILITY_COMPONENT" "$(tr -d '\n' < "$SERVICES")" "repair preserves existing services"
    assert_contains "$CALLS" "settings --user 0 put secure enabled_accessibility_services"
    assert_contains "$CALLS" "settings --user 0 put secure accessibility_enabled 1"
    pass "repair preserves and enables"
}

test_repair_is_idempotent() {
    reset_fixture
    repair_state || fail "initial repair should succeed"
    : > "$CALLS"
    repair_state || fail "second repair should succeed"
    local value
    value="$(tr -d '\n' < "$SERVICES")"
    assert_equals "$ACCESSIBILITY_COMPONENT" "$value" "idempotent repair value"
    [[ "$(grep -oF "$ACCESSIBILITY_COMPONENT" "$SERVICES" | wc -l)" -eq 1 ]] || fail "service appears more than once"
    assert_not_contains "$CALLS" "settings --user 0 put secure"
    pass "repair is idempotent"
}

test_missing_package_is_safe() {
    reset_fixture
    touch "$TEST_ROOT/package_missing"
    if repair_state; then
        fail "missing package should not report repair success"
    fi
    assert_not_contains "$CALLS" "settings --user 0 put"
    assert_not_contains "$CALLS" "am start"
    pass "missing package is safe"
}

test_optional_failure_does_not_block_accessibility() {
    reset_fixture
    touch "$TEST_ROOT/fail_appops"
    repair_state || fail "optional app-op failure should not block repair"
    assert_equals "$ACCESSIBILITY_COMPONENT" "$(tr -d '\n' < "$SERVICES")" "accessibility survives optional failure"
    assert_contains "$CALLS" "cmd appops set"
    pass "optional failures are isolated"
}

test_home_launch_is_fixed() {
    reset_fixture
    launch_home || fail "home launch should succeed with fake am"
    [[ -e "$TEST_ROOT/home_launched" ]] || fail "home activity was not launched"
    assert_contains "$CALLS" "com.yinxing.launcher/.feature.home.MainActivity"
    pass "home launch is fixed"
}

test_guard_runs_initial_repair_and_one_health_cycle() {
    reset_fixture
    YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=1 \
        run_module_script "$MODULE_ROOT/bin/guard.sh"
    assert_equals "$ACCESSIBILITY_COMPONENT" "$(tr -d '\n' < "$SERVICES")" "guard repairs accessibility"
    assert_equals "1" "$(grep -c '^am start ' "$CALLS")" "guard launches HOME once"
    if [[ "${YINXING_TEST_SHELL:-}" != "busybox" ]]; then
        assert_contains "$CALLS" "sleep 0"
    fi
    pass "guard runs initial repair and one health cycle"
}

test_guard_ignores_pid_from_previous_boot() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    /bin/sleep 30 &
    LIVE_PID=$!
    printf '%s\n' "$LIVE_PID" > "$TEST_ROOT/state/guard.pid"
    printf 'old-boot-id\n' > "$TEST_ROOT/state/guard.boot_id"
    printf 'new-boot-id\n' > "$TEST_ROOT/boot_id"
    YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=1 \
        run_module_script "$MODULE_ROOT/bin/guard.sh"
    assert_equals "1" "$(grep -c '^am start ' "$CALLS" || true)" "stale boot PID must not block guard"
    kill "$LIVE_PID" 2>/dev/null || true
    wait "$LIVE_PID" 2>/dev/null || true
    LIVE_PID=""
    pass "guard ignores PID from previous boot"
}

test_action_reuses_repair_and_launch() {
    reset_fixture
    run_module_script "$MODULE_ROOT/action.sh"
    assert_equals "$ACCESSIBILITY_COMPONENT" "$(tr -d '\n' < "$SERVICES")" "action repairs accessibility"
    assert_equals "1" "$(grep -c '^am start ' "$CALLS")" "action launches HOME once"
    pass "action reuses repair and launch"
}

test_uninstall_only_removes_module_state() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'added\n' > "$TEST_ROOT/state/doze_added_by_module"
    printf 'keep\n' > "$TEST_ROOT/unrelated"
    printf added > "$TEST_ROOT/doze_whitelisted"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    assert_contains "$CALLS" "cmd deviceidle whitelist -com.yinxing.launcher"
    [[ ! -e "$TEST_ROOT/state" ]] || fail "module state directory was not removed"
    assert_equals "keep" "$(tr -d '\n' < "$TEST_ROOT/unrelated")" "uninstall preserves unrelated files"
    pass "uninstall only removes module state"
}

test_module_package() {
    local rejection

    if rejection="$(bash "$REPO_ROOT/tools/package-yinxing-guard.sh" "$MODULE_ROOT" 2>&1)"; then
        fail "packager accepted the module source as its output"
    fi
    [[ "$rejection" == *"output must not be inside the module source"* ]] || \
        fail "packager did not report the unsafe output path clearly"
    [[ -f "$MODULE_ROOT/module.prop" ]] || fail "unsafe output check damaged the module source"

    bash "$REPO_ROOT/tools/package-yinxing-guard.sh" "$TEST_ROOT/module.zip" "9.9.9-test"
    unzip -t "$TEST_ROOT/module.zip" >/dev/null
    unzip -Z1 "$TEST_ROOT/module.zip" | grep -Fx 'module.prop' >/dev/null
    unzip -Z1 "$TEST_ROOT/module.zip" | grep -Fx 'bin/guard.sh' >/dev/null
    ! unzip -Z1 "$TEST_ROOT/module.zip" | grep -F 'yinxing_guard/' >/dev/null
    ! unzip -Z1 "$TEST_ROOT/module.zip" | grep -F '/tools/' >/dev/null
    assert_contains <(unzip -p "$TEST_ROOT/module.zip" module.prop) 'version=9.9.9-test'
    assert_contains "$MODULE_ROOT/module.prop" 'version=1.10.0-root-preview.1'
    for executable in service.sh action.sh uninstall.sh bin/common.sh bin/guard.sh; do
        zipinfo -l "$TEST_ROOT/module.zip" | grep -E "^-rwxr-xr-x .* ${executable}$" >/dev/null || \
            fail "$executable is not executable in the ZIP"
    done
    pass "module package"
}

case "$MODE" in
    --merge-only)
        test_merge_cases
        ;;
    --package-only)
        test_module_package
        ;;
    --guard-only)
        test_guard_runs_initial_repair_and_one_health_cycle
        test_guard_ignores_pid_from_previous_boot
        test_action_reuses_repair_and_launch
        test_uninstall_only_removes_module_state
        ;;
    all)
        test_merge_cases
        test_repair_preserves_and_enables
        test_repair_is_idempotent
        test_missing_package_is_safe
        test_optional_failure_does_not_block_accessibility
        test_home_launch_is_fixed
        test_guard_runs_initial_repair_and_one_health_cycle
        test_guard_ignores_pid_from_previous_boot
        test_action_reuses_repair_and_launch
        test_uninstall_only_removes_module_state
        test_module_package
        ;;
    *)
        fail "unknown mode: $MODE"
        ;;
esac
