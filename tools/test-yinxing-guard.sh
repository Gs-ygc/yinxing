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
CLEANUP_TARGET="$TEST_ROOT/boot-completed.d/yinxing-guard-uninstall-cleanup.sh"
PACKAGE_NESTED_DIR="$MODULE_ROOT/.package-test-output"

cleanup() {
    if [[ -n "${LIVE_PID:-}" ]]; then
        kill "$LIVE_PID" 2>/dev/null || true
        wait "$LIVE_PID" 2>/dev/null || true
    fi
    if [[ -n "${GUARD_PID:-}" ]]; then
        kill "$GUARD_PID" 2>/dev/null || true
        wait "$GUARD_PID" 2>/dev/null || true
    fi
    if [[ -n "${SECOND_GUARD_PID:-}" ]]; then
        kill "$SECOND_GUARD_PID" 2>/dev/null || true
        wait "$SECOND_GUARD_PID" 2>/dev/null || true
    fi
    if [[ -n "${MTIME_REFERENCE:-}" && -e "$MTIME_REFERENCE" ]]; then
        touch -r "$MTIME_REFERENCE" "$MODULE_ROOT/module.prop"
    fi
    rmdir "$PACKAGE_NESTED_DIR" 2>/dev/null || true
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN"
: > "$CALLS"
: > "$SERVICES"
printf '0\n' > "$ACCESSIBILITY_ENABLED"
export TEST_ROOT FAKE_BIN CALLS SERVICES ACCESSIBILITY_ENABLED
export YINXING_GUARD_STATE_DIR="$TEST_ROOT/state"
export YINXING_GUARD_TEST_CLEANUP_TARGET="$CLEANUP_TARGET"
export YINXING_GUARD_TEST_MODULE_DIR="$TEST_ROOT/modules/yinxing_guard"
export PATH="$FAKE_BIN:$PATH"

run_module_script() {
    if [[ "${YINXING_TEST_SHELL:-}" == "busybox" ]]; then
        ASH_STANDALONE=1 busybox ash "$@"
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

assert_contains_text() {
    local text="$1"
    local value="$2"
    [[ "$text" == *"$value"* ]] || fail "missing '$value' in status output: $text"
}

assert_not_contains_text() {
    local text="$1"
    local value="$2"
    [[ "$text" != *"$value"* ]] || fail "unexpected '$value' in status output: $text"
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
    'if [[ "${args[0]:-}" == "get" ]]; then [[ -e "$TEST_ROOT/fail_settings_get" ]] && exit 1; if [[ "${args[2]:-}" == "enabled_accessibility_services" ]]; then [[ -s "$SERVICES" ]] && cat "$SERVICES" || printf "null\\n"; elif [[ "${args[2]:-}" == "accessibility_enabled" ]]; then cat "$ACCESSIBILITY_ENABLED"; else exit 2; fi; exit 0; fi' \
    'if [[ "${args[0]:-}" == "put" ]]; then [[ -e "$TEST_ROOT/fail_settings_put" ]] && exit 1; if [[ "${args[2]:-}" == "enabled_accessibility_services" ]]; then printf "%s\\n" "${args[3]:-}" > "$SERVICES"; elif [[ "${args[2]:-}" == "accessibility_enabled" ]]; then printf "%s\\n" "${args[3]:-}" > "$ACCESSIBILITY_ENABLED"; fi; exit 0; fi' \
    'exit 2'

write_fake pm \
    '#!/usr/bin/env bash' \
    'printf "pm %s\\n" "$*" >> "$CALLS"' \
    'args=("$@"); if [[ "${args[0]:-}" == "--user" ]]; then args=("${args[@]:2}"); fi' \
    'if [[ "${args[0]:-}" == "list" && "${args[1]:-}" == "packages" ]]; then [[ -e "$TEST_ROOT/fail_pm_list" ]] && exit 1; [[ -e "$TEST_ROOT/package_disabled" ]] && printf "package:com.yinxing.launcher\\n"; exit 0; fi' \
    'if [[ "${args[0]:-}" == "dump" ]]; then [[ -e "$TEST_ROOT/fail_pm_dump" ]] && exit 1; printf "Package com.yinxing.launcher\\n"; if [[ -e "$TEST_ROOT/component_disabled" ]]; then printf "disabledComponents: [%s]\\n" "$ACCESSIBILITY_COMPONENT"; else printf "Services: %s\\n" "$ACCESSIBILITY_COMPONENT"; fi; exit 0; fi' \
    'if [[ "${args[0]:-}" == "path" ]]; then [[ -e "$TEST_ROOT/package_missing" ]] && exit 1; if [[ -e "$TEST_ROOT/package_missing_once" ]]; then rm -f "$TEST_ROOT/package_missing_once"; exit 1; fi; printf "/data/app/com.yinxing.launcher/base.apk\\n"; exit 0; fi' \
    'if [[ "${args[0]:-}" == "enable" ]]; then [[ -e "$TEST_ROOT/fail_pm_enable" ]] && exit 1; exit 0; fi' \
    'exit 2'

write_fake cmd \
    '#!/usr/bin/env bash' \
    'printf "cmd %s\\n" "$*" >> "$CALLS"' \
    'if [[ "${1:-}" == "appops" && -e "$TEST_ROOT/fail_appops" ]]; then exit 1; fi' \
    'if [[ "${1:-}" == "deviceidle" && "${2:-}" == "whitelist" && $# -eq 2 ]]; then [[ -e "$TEST_ROOT/fail_deviceidle_query" ]] && exit 1; [[ -e "$TEST_ROOT/doze_whitelisted" ]] && printf "user,%s\\n" "com.yinxing.launcher"; exit 0; fi' \
    'if [[ "${1:-}" == "deviceidle" && "${2:-}" == "whitelist" && "${3:-}" == +com.yinxing.launcher ]]; then printf added > "$TEST_ROOT/doze_whitelisted"; fi' \
    'if [[ "${1:-}" == "deviceidle" && "${2:-}" == "whitelist" && "${3:-}" == -com.yinxing.launcher ]]; then [[ -e "$TEST_ROOT/fail_deviceidle_remove" ]] && exit 1; rm -f "$TEST_ROOT/doze_whitelisted"; fi' \
    'exit 0'

write_fake am \
    '#!/usr/bin/env bash' \
    'printf "am %s\\n" "$*" >> "$CALLS"' \
    'if [[ -e "$TEST_ROOT/fail_home_once" ]]; then rm -f "$TEST_ROOT/fail_home_once"; exit 1; fi' \
    'printf launched > "$TEST_ROOT/home_launched"'

write_fake getprop \
    '#!/usr/bin/env bash' \
    'printf "getprop %s\\n" "$*" >> "$CALLS"' \
    '[[ "${1:-}" == "sys.boot_completed" ]] && printf "1\\n"'

write_fake log \
    '#!/usr/bin/env bash' \
    'printf "log %s\\n" "$*" >> "$CALLS"' \
    '[[ -e "$TEST_ROOT/log_noise" ]] && printf "log-noise\\n"'

write_fake sleep \
    '#!/usr/bin/env bash' \
    'printf "sleep %s\\n" "$*" >> "$CALLS"' \
    '[[ -e "$TEST_ROOT/use_real_sleep" ]] && /bin/sleep "$@"' \
    'exit 0'

# The assertions describe observable state and command effects, not source text.
source "$MODULE_ROOT/bin/common.sh"
export ACCESSIBILITY_COMPONENT

reset_fixture() {
    : > "$CALLS"
    : > "$SERVICES"
    printf '0\n' > "$ACCESSIBILITY_ENABLED"
    rm -f \
        "$TEST_ROOT/package_missing" \
        "$TEST_ROOT/package_missing_once" \
        "$TEST_ROOT/fail_appops" \
        "$TEST_ROOT/fail_settings_get" \
        "$TEST_ROOT/fail_settings_put" \
        "$TEST_ROOT/fail_pm_list" \
        "$TEST_ROOT/fail_pm_dump" \
        "$TEST_ROOT/fail_pm_enable" \
        "$TEST_ROOT/fail_deviceidle_query" \
        "$TEST_ROOT/fail_deviceidle_remove" \
        "$TEST_ROOT/fail_home_once" \
        "$TEST_ROOT/use_real_sleep" \
        "$TEST_ROOT/home_launched" \
        "$TEST_ROOT/doze_whitelisted" \
        "$TEST_ROOT/package_disabled" \
        "$TEST_ROOT/component_disabled" \
        "$TEST_ROOT/log_noise"
    rm -rf "$TEST_ROOT/state" "$TEST_ROOT/boot-completed.d" "$TEST_ROOT/modules"
}

prepare_healthy_status_fixture() {
    mkdir -p \
        "$TEST_ROOT/modules/yinxing_guard" \
        "$TEST_ROOT/state/guard.lock/test-boot" \
        "$(dirname "$CLEANUP_TARGET")"
    printf 'test-boot\n' > "$TEST_ROOT/boot_id"
    printf '%s\n' "$$" > "$TEST_ROOT/state/guard.lock/test-boot/pid"
    printf 'ok\n' > "$TEST_ROOT/state/last_repair"
    printf 'added\n' > "$TEST_ROOT/state/doze_added_by_module"
    printf 'helper\n' > "$CLEANUP_TARGET"
    chmod 0755 "$CLEANUP_TARGET"
    printf '%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '1\n' > "$ACCESSIBILITY_ENABLED"
    touch "$TEST_ROOT/doze_whitelisted"
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

test_status_reports_healthy_state() {
    reset_fixture
    prepare_healthy_status_fixture
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "schema=1"
    assert_contains_text "$output" "module=active"
    assert_contains_text "$output" "guard=running"
    assert_contains_text "$output" "accessibility=enabled"
    assert_contains_text "$output" "doze=owned"
    assert_contains_text "$output" "cleanup=ready"
    assert_contains_text "$output" "last_repair=ok"
    pass "status reports healthy state"
}

test_status_reports_disabled_package_as_disabled() {
    reset_fixture
    prepare_healthy_status_fixture
    touch "$TEST_ROOT/package_disabled"
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "accessibility=disabled"
    pass "status reports disabled package"
}

test_status_reports_disabled_component_as_disabled() {
    reset_fixture
    prepare_healthy_status_fixture
    touch "$TEST_ROOT/component_disabled"
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "accessibility=disabled"
    pass "status reports disabled component"
}

test_status_reports_unknown_when_package_state_query_fails() {
    reset_fixture
    prepare_healthy_status_fixture
    touch "$TEST_ROOT/fail_pm_list"
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "accessibility=unknown"
    pass "status reports unknown on package state failure"
}

test_status_reports_unknown_when_component_state_query_fails() {
    reset_fixture
    prepare_healthy_status_fixture
    touch "$TEST_ROOT/fail_pm_dump"
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "accessibility=unknown"
    pass "status reports unknown on component state failure"
}

test_status_output_contract_ignores_log_noise() {
    reset_fixture
    prepare_healthy_status_fixture
    touch "$TEST_ROOT/fail_deviceidle_query" "$TEST_ROOT/log_noise"
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_equals "8" "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" "status output line count"
    assert_not_contains_text "$output" "log-noise"
    pass "status output contract ignores log noise"
}

test_status_reports_stale_guard_as_degraded() {
    reset_fixture
    mkdir -p "$TEST_ROOT/modules/yinxing_guard" "$TEST_ROOT/state/guard.lock/test-boot"
    printf 'test-boot\n' > "$TEST_ROOT/boot_id"
    printf '999999\n' > "$TEST_ROOT/state/guard.lock/test-boot/pid"
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "module=active"
    assert_contains_text "$output" "guard=stale"
    assert_contains_text "$output" "accessibility=disabled"
    assert_contains_text "$output" "last_repair=unknown"
    pass "status reports stale guard"
}

test_status_reports_missing_module() {
    reset_fixture
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "module=missing"
    assert_contains_text "$output" "guard=missing"
    assert_contains_text "$output" "accessibility=missing"
    pass "status reports missing module"
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

test_settings_read_failure_is_safe() {
    reset_fixture
    printf 'talkback:other\n' > "$SERVICES"
    touch "$TEST_ROOT/fail_settings_get"
    if repair_state; then
        fail "settings read failure should report an incomplete repair"
    fi
    assert_equals "talkback:other" "$(tr -d '\n' < "$SERVICES")" "settings read failure preserves services"
    assert_not_contains "$CALLS" "settings --user 0 put secure"
    pass "settings read failure is safe"
}

test_package_enable_failure_is_reported() {
    reset_fixture
    touch "$TEST_ROOT/fail_pm_enable"
    if repair_state; then
        fail "package enable failure should report an incomplete repair"
    fi
    assert_not_contains "$CALLS" "settings --user 0 put secure"
    pass "package enable failure is reported"
}

test_doze_query_failure_is_safe() {
    reset_fixture
    install_cleanup_helper "$MODULE_ROOT/bin/uninstall-cleanup.sh" || fail "could not install Doze test cleanup helper"
    touch "$TEST_ROOT/fail_deviceidle_query"
    repair_state || fail "optional Doze query failure should not block accessibility"
    assert_equals "$ACCESSIBILITY_COMPONENT" "$(tr -d '\n' < "$SERVICES")" "accessibility survives Doze query failure"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    [[ ! -e "$TEST_ROOT/state/doze_added_by_module" ]] || fail "Doze ownership was claimed after a failed query"
    pass "Doze query failure is safe"
}

test_doze_add_claims_ownership() {
    reset_fixture
    install_cleanup_helper "$MODULE_ROOT/bin/uninstall-cleanup.sh" || fail "could not install Doze add test cleanup helper"
    repair_state || fail "normal Doze add repair should succeed"
    [[ -e "$TEST_ROOT/doze_whitelisted" ]] || fail "normal repair did not add Doze whitelist"
    assert_equals "added" "$(tr -d '\n' < "$TEST_ROOT/state/doze_added_by_module")" "normal repair ownership marker"
    : > "$CALLS"
    repair_state || fail "idempotent Doze repair should succeed"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    pass "Doze add claims ownership"
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
    assert_equals "ok" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" "guard records successful repair"
    assert_equals "1" "$(grep -c '^am start ' "$CALLS")" "guard launches HOME once"
    if [[ "${YINXING_TEST_SHELL:-}" != "busybox" ]]; then
        assert_contains "$CALLS" "sleep 0"
    fi
    pass "guard runs initial repair and one health cycle"
}

test_guard_retries_transient_startup_failures() {
    reset_fixture
    touch "$TEST_ROOT/package_missing_once" "$TEST_ROOT/fail_home_once"
    YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=2 \
        run_module_script "$MODULE_ROOT/bin/guard.sh"
    assert_equals "$ACCESSIBILITY_COMPONENT" "$(tr -d '\n' < "$SERVICES")" "guard repairs after package appears"
    assert_equals "2" "$(grep -c '^am start ' "$CALLS" || true)" "guard retries one failed HOME launch"
    [[ -e "$TEST_ROOT/home_launched" ]] || fail "HOME retry never succeeded"
    pass "guard retries transient startup failures"
}

test_guard_ignores_pid_from_previous_boot() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state/guard.lock/old-boot-id"
    /bin/sleep 30 &
    LIVE_PID=$!
    printf '%s\n' "$LIVE_PID" > "$TEST_ROOT/state/guard.lock/old-boot-id/pid"
    printf 'old-boot-id\n' > "$TEST_ROOT/state/guard.lock/old-boot-id/boot_id"
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

test_guard_respects_live_guard_same_boot() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state/guard.lock/same-boot-id"
    /bin/sleep 30 &
    LIVE_PID=$!
    printf '%s\n' "$LIVE_PID" > "$TEST_ROOT/state/guard.lock/same-boot-id/pid"
    printf 'same-boot-id\n' > "$TEST_ROOT/state/guard.lock/same-boot-id/boot_id"
    printf 'same-boot-id\n' > "$TEST_ROOT/boot_id"
    YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=1 \
        run_module_script "$MODULE_ROOT/bin/guard.sh"
    assert_equals "0" "$(grep -c '^am start ' "$CALLS" || true)" "live same-boot guard must block duplicate"
    kill "$LIVE_PID" 2>/dev/null || true
    wait "$LIVE_PID" 2>/dev/null || true
    LIVE_PID=""
    pass "guard respects live same-boot lock"
}

test_guard_reclaims_dead_same_boot_lock() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state/guard.lock/dead-boot-id"
    printf '999999\n' > "$TEST_ROOT/state/guard.lock/dead-boot-id/pid"
    printf 'dead-boot-id\n' > "$TEST_ROOT/state/guard.lock/dead-boot-id/boot_id"
    printf 'dead-boot-id\n' > "$TEST_ROOT/boot_id"
    YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=1 \
        run_module_script "$MODULE_ROOT/bin/guard.sh"
    assert_equals "1" "$(grep -c '^am start ' "$CALLS" || true)" "dead same-boot lock must be reclaimed"
    pass "guard reclaims dead same-boot lock"
}

test_guard_preserves_incomplete_lock_for_service_retry() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state/guard.lock/incomplete-boot-id"
    printf 'incomplete-boot-id\n' > "$TEST_ROOT/boot_id"
    local status
    set +e
    YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=1 \
        YINXING_GUARD_LOCK_ATTEMPTS=1 \
        run_module_script "$MODULE_ROOT/bin/guard.sh"
    status=$?
    set -e
    assert_equals "75" "$status" "incomplete lock should ask service to retry"
    assert_equals "0" "$(grep -c '^am start ' "$CALLS" || true)" "incomplete lock must not be reclaimed"
    [[ -d "$TEST_ROOT/state/guard.lock/incomplete-boot-id" ]] || fail "incomplete lock was reclaimed"
    pass "guard preserves incomplete lock for service retry"
}

test_service_retries_incomplete_lock() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state/guard.lock/incomplete-boot-id"
    printf 'incomplete-boot-id\n' > "$TEST_ROOT/boot_id"
    touch "$TEST_ROOT/use_real_sleep"
    (
        /bin/sleep 0.2
        rm -rf "$TEST_ROOT/state/guard.lock/incomplete-boot-id"
    ) &
    local remover_pid=$!
    YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=1 \
        YINXING_GUARD_LOCK_ATTEMPTS=1 \
        YINXING_GUARD_LOCK_RETRY_SECONDS=0 \
        run_module_script "$MODULE_ROOT/service.sh"
    local found=0
    for _ in $(seq 1 100); do
        if grep -q '^am start ' "$CALLS"; then
            found=1
            break
        fi
        /bin/sleep 0.05
    done
    wait "$remover_pid" 2>/dev/null || true
    assert_equals "1" "$found" "service did not retry an incomplete lock"
    assert_equals "1" "$(grep -c '^am start ' "$CALLS" || true)" "service retried more than once"
    pass "service retries incomplete lock"
}

test_guard_prevents_concurrent_processes() {
    reset_fixture
    touch "$TEST_ROOT/use_real_sleep"
    printf 'concurrent-boot-id\n' > "$TEST_ROOT/boot_id"
    YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=2 \
        YINXING_GUARD_MAX_CYCLES=1 \
        run_module_script "$MODULE_ROOT/bin/guard.sh" &
    GUARD_PID=$!
    YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=2 \
        YINXING_GUARD_MAX_CYCLES=1 \
        run_module_script "$MODULE_ROOT/bin/guard.sh" &
    SECOND_GUARD_PID=$!
    wait "$GUARD_PID"
    wait "$SECOND_GUARD_PID"
    GUARD_PID=""
    SECOND_GUARD_PID=""
    assert_equals "1" "$(grep -c '^am start ' "$CALLS" || true)" "concurrent guards both performed health cycles"
    pass "guard prevents concurrent processes"
}

test_action_reuses_repair_and_launch() {
    reset_fixture
    run_module_script "$MODULE_ROOT/action.sh"
    assert_equals "$ACCESSIBILITY_COMPONENT" "$(tr -d '\n' < "$SERVICES")" "action repairs accessibility"
    assert_equals "ok" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" "action records successful repair"
    assert_equals "1" "$(grep -c '^am start ' "$CALLS")" "action launches HOME once"
    [[ -x "$CLEANUP_TARGET" ]] || fail "action did not install deferred cleanup helper"
    [[ -e "$TEST_ROOT/doze_whitelisted" ]] || fail "action did not add Doze whitelist"
    [[ -f "$TEST_ROOT/state/doze_added_by_module" ]] || fail "action did not record Doze ownership"
    pass "action reuses repair and launch"
}

test_cleanup_helper_waits_for_module_removal() {
    reset_fixture
    mkdir -p "$TEST_ROOT/modules/yinxing_guard" "$TEST_ROOT/state"
    printf 'added\n' > "$TEST_ROOT/state/doze_added_by_module"
    touch "$TEST_ROOT/doze_whitelisted"
    install_cleanup_helper "$MODULE_ROOT/bin/uninstall-cleanup.sh" || fail "could not install active-module cleanup helper"
    run_module_script "$CLEANUP_TARGET"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist -com.yinxing.launcher"
    [[ -e "$TEST_ROOT/state/doze_added_by_module" ]] || fail "active module cleanup removed ownership marker"
    [[ -e "$CLEANUP_TARGET" ]] || fail "active module cleanup removed helper"
    pass "cleanup helper waits for module removal"
}

test_cleanup_helper_stays_for_first_boot() {
    reset_fixture
    mkdir -p "$TEST_ROOT/modules/yinxing_guard"
    install_cleanup_helper "$MODULE_ROOT/bin/uninstall-cleanup.sh" || fail "could not install first-boot cleanup helper"
    run_module_script "$CLEANUP_TARGET"
    [[ -x "$CLEANUP_TARGET" ]] || fail "first-boot helper self-deleted while module was active"
    pass "cleanup helper stays for first boot"
}

test_cleanup_schedule_failure_preserves_existing_helper() {
    reset_fixture
    install_cleanup_helper "$MODULE_ROOT/bin/uninstall-cleanup.sh" || fail "could not install baseline cleanup helper"
    printf 'blocked\n' > "$TEST_ROOT/blocked-parent"
    previous_target="$CLEANUP_TARGET"
    CLEANUP_TARGET="$TEST_ROOT/blocked-parent/helper.sh"
    if install_cleanup_helper "$MODULE_ROOT/bin/uninstall-cleanup.sh"; then
        fail "cleanup helper installation unexpectedly succeeded under a blocked parent"
    fi
    CLEANUP_TARGET="$previous_target"
    [[ -x "$CLEANUP_TARGET" ]] || fail "schedule failure removed the existing helper"
    pass "cleanup schedule failure preserves existing helper"
}

test_cleanup_directory_target_is_rejected() {
    reset_fixture
    mkdir -p "$CLEANUP_TARGET"
    if install_cleanup_helper "$MODULE_ROOT/bin/uninstall-cleanup.sh"; then
        fail "cleanup helper accepted a directory target"
    fi
    repair_state || fail "accessibility repair should survive a bad helper target"
    [[ ! -e "$TEST_ROOT/doze_whitelisted" ]] || fail "bad helper target allowed an unowned Doze add"
    [[ ! -e "$TEST_ROOT/state/doze_added_by_module" ]] || fail "bad helper target created ownership marker"
    pass "cleanup directory target is rejected"
}

test_uninstall_retains_malformed_marker() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'partial\n' > "$TEST_ROOT/state/doze_added_by_module"
    touch "$TEST_ROOT/doze_whitelisted"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    [[ -x "$CLEANUP_TARGET" ]] || fail "malformed marker did not retain cleanup helper"
    if run_module_script "$CLEANUP_TARGET"; then
        fail "malformed marker cleanup unexpectedly succeeded"
    fi
    [[ -f "$TEST_ROOT/state/doze_added_by_module" ]] || fail "malformed marker was deleted"
    [[ -x "$CLEANUP_TARGET" ]] || fail "malformed marker cleanup helper was deleted"
    [[ -e "$TEST_ROOT/doze_whitelisted" ]] || fail "malformed marker cleanup changed Doze state"
    pass "uninstall retains malformed marker"
}

test_uninstall_reports_cleanup_schedule_failure() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'added\n' > "$TEST_ROOT/state/doze_added_by_module"
    touch "$TEST_ROOT/doze_whitelisted"
    blocked_target="$TEST_ROOT/blocked-parent/helper.sh"
    printf 'blocked\n' > "$TEST_ROOT/blocked-parent"
    export YINXING_GUARD_TEST_CLEANUP_TARGET="$blocked_target"
    if run_module_script "$MODULE_ROOT/uninstall.sh"; then
        fail "uninstall reported success without a cleanup helper"
    fi
    export YINXING_GUARD_TEST_CLEANUP_TARGET="$CLEANUP_TARGET"
    [[ -f "$TEST_ROOT/state/doze_added_by_module" ]] || fail "failed scheduling lost Doze ownership marker"
    [[ -e "$TEST_ROOT/doze_whitelisted" ]] || fail "failed scheduling changed Doze state"
    [[ ! -e "$blocked_target" ]] || fail "failed scheduling left a partial helper"
    pass "uninstall reports cleanup schedule failure"
}

test_uninstall_defers_cleanup_until_boot_completed() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'added\n' > "$TEST_ROOT/state/doze_added_by_module"
    printf 'ok\n' > "$TEST_ROOT/state/last_repair"
    printf 'stale\n' > "$TEST_ROOT/state/last_repair.tmp.999"
    printf 'stale\n' > "$TEST_ROOT/state/doze_added_by_module.tmp.999"
    printf 'keep\n' > "$TEST_ROOT/unrelated"
    printf added > "$TEST_ROOT/doze_whitelisted"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist -com.yinxing.launcher"
    [[ -x "$CLEANUP_TARGET" ]] || fail "uninstall did not schedule boot-completed cleanup"
    [[ -f "$TEST_ROOT/state/doze_added_by_module" ]] || fail "uninstall removed ownership before cleanup"
    run_module_script "$CLEANUP_TARGET"
    assert_contains "$CALLS" "cmd deviceidle whitelist -com.yinxing.launcher"
    [[ ! -e "$CLEANUP_TARGET" ]] || fail "successful cleanup did not remove itself"
    [[ ! -e "$TEST_ROOT/state/last_repair" ]] || fail "successful cleanup left last repair state"
    [[ ! -e "$TEST_ROOT/state/last_repair.tmp.999" ]] || fail "successful cleanup left repair temp state"
    [[ ! -e "$TEST_ROOT/state/doze_added_by_module.tmp.999" ]] || fail "successful cleanup left Doze temp state"
    [[ ! -e "$TEST_ROOT/state" ]] || fail "module state directory was not removed"
    assert_equals "keep" "$(tr -d '\n' < "$TEST_ROOT/unrelated")" "uninstall preserves unrelated files"
    pass "uninstall defers cleanup until boot completed"
}

test_uninstall_retains_marker_when_doze_remove_fails() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'added\n' > "$TEST_ROOT/state/doze_added_by_module"
    touch "$TEST_ROOT/doze_whitelisted" "$TEST_ROOT/fail_deviceidle_remove"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    [[ -x "$CLEANUP_TARGET" ]] || fail "failed cleanup was not scheduled"
    if run_module_script "$CLEANUP_TARGET"; then
        fail "boot-completed cleanup reported success after command failure"
    fi
    [[ -f "$TEST_ROOT/state/doze_added_by_module" ]] || fail "failed Doze removal lost ownership marker"
    [[ -x "$CLEANUP_TARGET" ]] || fail "failed cleanup removed its retry script"
    [[ -e "$TEST_ROOT/doze_whitelisted" ]] || fail "fake Doze entry unexpectedly disappeared"
    pass "boot-completed cleanup retains retry state after failure"
}

test_module_package() {
    local rejection

    if rejection="$(bash "$REPO_ROOT/tools/package-yinxing-guard.sh" "$MODULE_ROOT" 2>&1)"; then
        fail "packager accepted the module source as its output"
    fi
    [[ "$rejection" == *"output must not be inside the module source"* ]] || \
        fail "packager did not report the unsafe output path clearly"
    [[ -f "$MODULE_ROOT/module.prop" ]] || fail "unsafe output check damaged the module source"

    if bash "$REPO_ROOT/tools/package-yinxing-guard.sh" "$PACKAGE_NESTED_DIR/module.zip" 2>/dev/null; then
        fail "packager accepted a nested output inside the module source"
    fi
    [[ ! -e "$PACKAGE_NESTED_DIR" ]] || fail "rejected nested output dirtied the module source"

    mkdir "$TEST_ROOT/output-directory"
    if bash "$REPO_ROOT/tools/package-yinxing-guard.sh" "$TEST_ROOT/output-directory" 2>/dev/null; then
        fail "packager accepted a directory as its output"
    fi

    printf 'preserve-this-hardlink-target\n' > "$TEST_ROOT/hardlink-source"
    ln "$TEST_ROOT/hardlink-source" "$TEST_ROOT/hardlink.zip"
    bash "$REPO_ROOT/tools/package-yinxing-guard.sh" "$TEST_ROOT/hardlink.zip" "9.9.9-test" >/dev/null
    assert_equals "preserve-this-hardlink-target" "$(tr -d '\n' < "$TEST_ROOT/hardlink-source")" \
        "packager must not delete a hard-linked source when replacing output"

    bash "$REPO_ROOT/tools/package-yinxing-guard.sh" "$TEST_ROOT/module.zip" "9.9.9-test"
    unzip -t "$TEST_ROOT/module.zip" >/dev/null
    unzip -Z1 "$TEST_ROOT/module.zip" | grep -Fx 'module.prop' >/dev/null
    unzip -Z1 "$TEST_ROOT/module.zip" | grep -Fx 'bin/guard.sh' >/dev/null
    unzip -Z1 "$TEST_ROOT/module.zip" | grep -Fx 'bin/uninstall-cleanup.sh' >/dev/null
    unzip -Z1 "$TEST_ROOT/module.zip" | grep -Fx 'bin/status.sh' >/dev/null
    ! unzip -Z1 "$TEST_ROOT/module.zip" | grep -F 'yinxing_guard/' >/dev/null
    ! unzip -Z1 "$TEST_ROOT/module.zip" | grep -F '/tools/' >/dev/null
    assert_contains <(unzip -p "$TEST_ROOT/module.zip" module.prop) 'version=9.9.9-test'
    assert_contains <(unzip -p "$TEST_ROOT/module.zip" module.prop) 'versionCode=4'
    assert_contains <(unzip -p "$TEST_ROOT/module.zip" bin/common.sh) 'MODULE_VERSION="9.9.9-test"'
    assert_contains <(unzip -p "$TEST_ROOT/module.zip" bin/uninstall-cleanup.sh) 'MODULE_VERSION="9.9.9-test"'
    assert_contains "$MODULE_ROOT/module.prop" 'version=1.10.0-root-preview.4'
    assert_contains "$MODULE_ROOT/module.prop" 'versionCode=4'
    for executable in service.sh action.sh uninstall.sh bin/common.sh bin/guard.sh bin/status.sh bin/uninstall-cleanup.sh; do
        zipinfo -l "$TEST_ROOT/module.zip" | grep -E "^-rwxr-xr-x .* ${executable}$" >/dev/null || \
            fail "$executable is not executable in the ZIP"
    done
    zipinfo -T -l "$TEST_ROOT/module.zip" | awk '/^[-d]/{ if ($(NF - 1) != "19800101.000000") exit 1 }' || \
        fail "module ZIP timestamps are not normalized"
    MTIME_REFERENCE="$TEST_ROOT/module.prop.mtime"
    cp -p "$MODULE_ROOT/module.prop" "$MTIME_REFERENCE"
    touch -t 203001010000 "$MODULE_ROOT/module.prop"
    bash "$REPO_ROOT/tools/package-yinxing-guard.sh" "$TEST_ROOT/module-after-mtime.zip" "9.9.9-test" >/dev/null
    cmp -s "$TEST_ROOT/module.zip" "$TEST_ROOT/module-after-mtime.zip" || \
        fail "module ZIP changed after source mtime changed"
    touch -r "$MTIME_REFERENCE" "$MODULE_ROOT/module.prop"
    MTIME_REFERENCE=""
    pass "module package"
}

case "$MODE" in
    --merge-only)
        test_merge_cases
        ;;
    --status-only)
        test_status_reports_healthy_state
        test_status_reports_disabled_package_as_disabled
        test_status_reports_disabled_component_as_disabled
        test_status_reports_unknown_when_package_state_query_fails
        test_status_reports_unknown_when_component_state_query_fails
        test_status_output_contract_ignores_log_noise
        test_status_reports_stale_guard_as_degraded
        test_status_reports_missing_module
        ;;
    --package-only)
        test_module_package
        ;;
    --guard-only)
        test_guard_runs_initial_repair_and_one_health_cycle
        test_guard_retries_transient_startup_failures
        test_guard_ignores_pid_from_previous_boot
        test_guard_respects_live_guard_same_boot
        test_guard_reclaims_dead_same_boot_lock
        test_guard_preserves_incomplete_lock_for_service_retry
        test_service_retries_incomplete_lock
        test_guard_prevents_concurrent_processes
        test_action_reuses_repair_and_launch
        test_cleanup_helper_waits_for_module_removal
        test_cleanup_helper_stays_for_first_boot
        test_cleanup_schedule_failure_preserves_existing_helper
        test_cleanup_directory_target_is_rejected
        test_uninstall_reports_cleanup_schedule_failure
        test_uninstall_defers_cleanup_until_boot_completed
        test_uninstall_retains_marker_when_doze_remove_fails
        test_uninstall_retains_malformed_marker
        ;;
    all)
        test_merge_cases
        test_status_reports_healthy_state
        test_status_reports_disabled_package_as_disabled
        test_status_reports_disabled_component_as_disabled
        test_status_reports_unknown_when_package_state_query_fails
        test_status_reports_unknown_when_component_state_query_fails
        test_status_output_contract_ignores_log_noise
        test_status_reports_stale_guard_as_degraded
        test_status_reports_missing_module
        test_repair_preserves_and_enables
        test_repair_is_idempotent
        test_missing_package_is_safe
        test_optional_failure_does_not_block_accessibility
        test_settings_read_failure_is_safe
        test_package_enable_failure_is_reported
        test_doze_query_failure_is_safe
        test_doze_add_claims_ownership
        test_home_launch_is_fixed
        test_guard_runs_initial_repair_and_one_health_cycle
        test_guard_retries_transient_startup_failures
        test_guard_ignores_pid_from_previous_boot
        test_guard_respects_live_guard_same_boot
        test_guard_reclaims_dead_same_boot_lock
        test_guard_preserves_incomplete_lock_for_service_retry
        test_service_retries_incomplete_lock
        test_guard_prevents_concurrent_processes
        test_action_reuses_repair_and_launch
        test_cleanup_helper_waits_for_module_removal
        test_cleanup_helper_stays_for_first_boot
        test_cleanup_schedule_failure_preserves_existing_helper
        test_cleanup_directory_target_is_rejected
        test_uninstall_reports_cleanup_schedule_failure
        test_uninstall_defers_cleanup_until_boot_completed
        test_uninstall_retains_marker_when_doze_remove_fails
        test_uninstall_retains_malformed_marker
        test_module_package
        if [[ -z "${YINXING_TEST_SHELL:-}" ]] && command -v busybox >/dev/null 2>&1; then
            YINXING_TEST_SHELL=busybox bash "$0" all
        fi
        ;;
    *)
        fail "unknown mode: $MODE"
        ;;
esac
