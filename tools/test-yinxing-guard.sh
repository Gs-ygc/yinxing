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
HOME_HOLDER="$TEST_ROOT/home_holder"
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
    if [[ -n "${COMMAND_CALLER_PID:-}" ]]; then
        kill "$COMMAND_CALLER_PID" 2>/dev/null || true
        wait "$COMMAND_CALLER_PID" 2>/dev/null || true
    fi
    if [[ -n "${STALLED_COMMAND_PID:-}" ]]; then
        kill "$STALLED_COMMAND_PID" 2>/dev/null || true
        wait "$STALLED_COMMAND_PID" 2>/dev/null || true
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
printf 'com.oplus.launcher\n' > "$HOME_HOLDER"
export TEST_ROOT FAKE_BIN CALLS SERVICES ACCESSIBILITY_ENABLED HOME_HOLDER
export YINXING_GUARD_STATE_DIR="$TEST_ROOT/state"
export YINXING_GUARD_TEST_CLEANUP_TARGET="$CLEANUP_TARGET"
export YINXING_GUARD_TEST_MODULE_DIR="$TEST_ROOT/modules/yinxing_guard"
export YINXING_GUARD_MODULE_STATE_DIR="$MODULE_ROOT"
export YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id"
export YINXING_GUARD_HOME_MARKER_LINK_COMMAND="yinxing-test-ln"
export YINXING_GUARD_HOME_MARKER_SYNC_COMMAND="yinxing-test-sync"
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

wait_for_guard_shutdown() {
    local stable_absence=0
    for _ in $(seq 1 200); do
        if [[ ! -e "$TEST_ROOT/state/guard.lock" ]]; then
            stable_absence=$((stable_absence + 1))
            if [[ "$stable_absence" -ge 4 ]]; then
                return 0
            fi
        else
            stable_absence=0
        fi
        /bin/sleep 0.05
    done
    return 1
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
    'deactivate_from() { control="$1"; [[ -f "$control" ]] || return 0; marker="$(cat "$control")"; mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"; touch "$YINXING_GUARD_TEST_MODULE_DIR/$marker"; }' \
    'shift_if_user() { if [[ "${1:-}" == "--user" ]]; then shift 2; fi; printf "%s" "$*"; }' \
    'args=("$@"); if [[ "${args[0]:-}" == "--user" ]]; then args=("${args[@]:2}"); fi' \
    'if [[ "${args[0]:-}" == "get" ]]; then [[ -e "$TEST_ROOT/fail_settings_get" ]] && exit 1; if [[ "${args[2]:-}" == "enabled_accessibility_services" ]]; then deactivate_from "$TEST_ROOT/deactivate_during_accessibility_read"; [[ -s "$SERVICES" ]] && cat "$SERVICES" || printf "null\\n"; elif [[ "${args[2]:-}" == "accessibility_enabled" ]]; then cat "$ACCESSIBILITY_ENABLED"; else exit 2; fi; exit 0; fi' \
    'if [[ "${args[0]:-}" == "put" ]]; then' \
    '  [[ -e "$TEST_ROOT/fail_settings_put" ]] && exit 1' \
    '  if [[ "${args[2]:-}" == "enabled_accessibility_services" ]]; then' \
    '    previous="$(cat "$SERVICES" 2>/dev/null || true)"; value="${args[3]:-}"' \
    '    if [[ -f "$TEST_ROOT/fail_accessibility_compensation_services" && "$value" == "$(cat "$TEST_ROOT/fail_accessibility_compensation_services")" ]]; then exit 1; fi' \
    '    printf "%s\\n" "$value" > "$SERVICES"' \
    '    if [[ ":$previous:" == *":$ACCESSIBILITY_COMPONENT:"* && ":$value:" != *":$ACCESSIBILITY_COMPONENT:"* ]]; then' \
    '      touch "$TEST_ROOT/accessibility_rebind_removed"' \
    '      [[ -f "$TEST_ROOT/caregiver_services_during_rebind_remove" ]] && cat "$TEST_ROOT/caregiver_services_during_rebind_remove" > "$SERVICES"' \
    '      deactivate_from "$TEST_ROOT/deactivate_during_accessibility_rebind_remove"' \
    '    elif [[ -e "$TEST_ROOT/accessibility_rebind_removed" && ":$value:" == *":$ACCESSIBILITY_COMPONENT:"* ]]; then' \
    '      rm -f "$TEST_ROOT/accessibility_rebind_removed"; deactivate_from "$TEST_ROOT/deactivate_during_accessibility_rebind_restore"' \
    '    fi' \
    '    if [[ ":$previous:" != *":$ACCESSIBILITY_COMPONENT:"* && ":$value:" == *":$ACCESSIBILITY_COMPONENT:"* ]]; then' \
    '      deactivate_from "$TEST_ROOT/deactivate_during_accessibility_services_put"' \
    '      if [[ -e "$TEST_ROOT/fail_settings_services_put_after_apply" ]]; then rm -f "$TEST_ROOT/fail_settings_services_put_after_apply"; exit 1; fi' \
    '    fi' \
    '  elif [[ "${args[2]:-}" == "accessibility_enabled" ]]; then' \
    '    printf "%s\\n" "${args[3]:-}" > "$ACCESSIBILITY_ENABLED"' \
    '    deactivate_from "$TEST_ROOT/deactivate_during_accessibility_enabled_put"' \
    '    if [[ -e "$TEST_ROOT/fail_settings_enabled_put_after_apply" ]]; then rm -f "$TEST_ROOT/fail_settings_enabled_put_after_apply"; exit 1; fi' \
    '  fi' \
    '  exit 0' \
    'fi' \
    'exit 2'

write_fake pm \
    '#!/usr/bin/env bash' \
    'printf "pm %s\\n" "$*" >> "$CALLS"' \
    'deactivate_from() { control="$1"; [[ -f "$control" ]] || return 0; marker="$(cat "$control")"; mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"; touch "$YINXING_GUARD_TEST_MODULE_DIR/$marker"; }' \
    'args=("$@"); if [[ "${args[0]:-}" == "--user" ]]; then args=("${args[@]:2}"); fi' \
    'if [[ -e "$TEST_ROOT/hang_pm_path" && "${args[0]:-}" == "path" ]]; then /bin/sleep 5; fi' \
    'if [[ "${args[0]:-}" == "list" && "${args[1]:-}" == "packages" ]]; then [[ -e "$TEST_ROOT/fail_pm_list" ]] && exit 1; [[ -e "$TEST_ROOT/package_disabled" ]] && printf "package:com.yinxing.launcher\\n"; exit 0; fi' \
    'if [[ "${args[0]:-}" == "dump" ]]; then [[ -e "$TEST_ROOT/fail_pm_dump" ]] && exit 1; printf "Package com.yinxing.launcher\\n"; if [[ -e "$TEST_ROOT/component_disabled" ]]; then printf "disabledComponents: [%s]\\n" "$ACCESSIBILITY_COMPONENT"; else printf "Services: %s\\n" "$ACCESSIBILITY_COMPONENT"; fi; exit 0; fi' \
    'if [[ "${args[0]:-}" == "path" && "${args[-1]:-}" == "com.oplus.launcher" ]]; then [[ -e "$TEST_ROOT/previous_home_missing" ]] && exit 1; [[ -e "$TEST_ROOT/switch_home_during_previous_path" ]] && printf "com.example.caregiverlauncher\\n" > "$HOME_HOLDER"; printf "/system/priv-app/OplusLauncher/OplusLauncher.apk\\n"; exit 0; fi' \
    'if [[ "${args[0]:-}" == "path" ]]; then [[ -e "$TEST_ROOT/package_missing" ]] && exit 1; if [[ -e "$TEST_ROOT/package_missing_once" ]]; then rm -f "$TEST_ROOT/package_missing_once"; exit 1; fi; deactivate_from "$TEST_ROOT/deactivate_during_package_path"; printf "/data/app/com.yinxing.launcher/base.apk\\n"; exit 0; fi' \
    'if [[ "${args[0]:-}" == "enable" ]]; then [[ -e "$TEST_ROOT/fail_pm_enable" ]] && exit 1; exit 0; fi' \
    'exit 2'

write_fake cmd \
    '#!/usr/bin/env bash' \
    'printf "cmd %s\\n" "$*" >> "$CALLS"' \
    'deactivate_from() { control="$1"; [[ -f "$control" ]] || return 0; marker="$(cat "$control")"; mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"; touch "$YINXING_GUARD_TEST_MODULE_DIR/$marker"; }' \
    'apply_late_home_set() { [[ -f "$TEST_ROOT/late_home_target" ]] || return 0; reads="$(cat "$TEST_ROOT/late_home_reads" 2>/dev/null || printf 0)"; reads=$((reads + 1)); printf "%s\\n" "$reads" > "$TEST_ROOT/late_home_reads"; if [[ "$reads" -ge 4 ]]; then cat "$TEST_ROOT/late_home_target" > "$HOME_HOLDER"; rm -f "$TEST_ROOT/late_home_target"; fi; }' \
    'if [[ "${1:-}" == "role" && "${2:-}" == "get-role-holders" ]]; then apply_late_home_set; [[ -e "$TEST_ROOT/hang_home_role_query" ]] && /bin/sleep 5; [[ -e "$TEST_ROOT/fail_home_role_query" ]] && exit 1; [[ -f "$TEST_ROOT/malformed_home_role_output" ]] && cat "$TEST_ROOT/malformed_home_role_output" && exit 0; [[ -s "$HOME_HOLDER" ]] && cat "$HOME_HOLDER"; exit 0; fi' \
    'if [[ "${1:-}" == "package" && "${2:-}" == "set-home-activity" ]]; then target="${!#}"; if [[ -e "$TEST_ROOT/pause_home_role_set" && "${target%%/*}" == "com.yinxing.launcher" ]]; then touch "$TEST_ROOT/home_role_set_entered"; for _ in $(seq 1 200); do [[ -e "$TEST_ROOT/allow_home_role_set" ]] && break; /bin/sleep 0.01; done; [[ -e "$TEST_ROOT/allow_home_role_set" ]] || exit 89; fi; [[ -e "$TEST_ROOT/hang_home_role_set" ]] && /bin/sleep 5; [[ -e "$TEST_ROOT/fail_home_role_set" ]] && exit 1; [[ -e "$TEST_ROOT/fail_home_role_restore" && "${target%%/*}" != "com.yinxing.launcher" ]] && exit 1; if [[ -e "$TEST_ROOT/late_home_role_set" && "${target%%/*}" == "com.yinxing.launcher" ]]; then printf "%s\\n" "${target%%/*}" > "$TEST_ROOT/late_home_target"; printf '0\\n' > "$TEST_ROOT/late_home_reads"; fi; [[ "${target%%/*}" == "com.yinxing.launcher" ]] && deactivate_from "$TEST_ROOT/deactivate_during_home_role_set"; [[ -e "$TEST_ROOT/late_home_role_set" && "${target%%/*}" == "com.yinxing.launcher" ]] && /bin/sleep 5; [[ -e "$TEST_ROOT/ignore_home_role_set" ]] || printf "%s\\n" "${target%%/*}" > "$HOME_HOLDER"; exit 0; fi' \
    'if [[ "${1:-}" == "role" && "${2:-}" == "remove-role-holder" ]]; then [[ -e "$TEST_ROOT/hang_home_role_remove" ]] && /bin/sleep 5; [[ -e "$TEST_ROOT/fail_home_role_remove" ]] && exit 1; [[ -e "$TEST_ROOT/ignore_home_role_remove" ]] || : > "$HOME_HOLDER"; exit 0; fi' \
    'if [[ -e "$TEST_ROOT/hang_deviceidle_remove" && "${1:-}" == "deviceidle" && "${2:-}" == "whitelist" && "${3:-}" == -com.yinxing.launcher ]]; then /bin/sleep 5; fi' \
    'if [[ "${1:-}" == "appops" && "${6:-}" == "RUN_IN_BACKGROUND" ]]; then deactivate_from "$TEST_ROOT/deactivate_during_first_appops"; fi' \
    'if [[ "${1:-}" == "appops" && -e "$TEST_ROOT/fail_appops" ]]; then exit 1; fi' \
    'if [[ "${1:-}" == "deviceidle" && "${2:-}" == "whitelist" && $# -eq 2 ]]; then [[ -e "$TEST_ROOT/fail_deviceidle_query" ]] && exit 1; [[ -e "$TEST_ROOT/doze_whitelisted" ]] && printf "user,%s\\n" "com.yinxing.launcher"; exit 0; fi' \
    'if [[ "${1:-}" == "deviceidle" && "${2:-}" == "whitelist" && "${3:-}" == +com.yinxing.launcher ]]; then if [[ -e "$TEST_ROOT/pause_deviceidle_add" ]]; then touch "$TEST_ROOT/deviceidle_add_entered"; for _ in $(seq 1 400); do [[ -e "$TEST_ROOT/allow_deviceidle_add" ]] && break; /bin/sleep 0.01; done; [[ -e "$TEST_ROOT/allow_deviceidle_add" ]] || exit 89; fi; deactivate_from "$TEST_ROOT/deactivate_during_doze_add"; printf added > "$TEST_ROOT/doze_whitelisted"; [[ -e "$TEST_ROOT/fail_deviceidle_add_after_apply" ]] && exit 1; fi' \
    'if [[ "${1:-}" == "deviceidle" && "${2:-}" == "whitelist" && "${3:-}" == -com.yinxing.launcher ]]; then [[ -e "$TEST_ROOT/fail_deviceidle_remove" ]] && exit 1; [[ -e "$TEST_ROOT/ignore_deviceidle_remove" ]] || rm -f "$TEST_ROOT/doze_whitelisted"; [[ -e "$TEST_ROOT/fail_deviceidle_remove_after_apply" ]] && exit 1; fi' \
    'exit 0'

write_fake yinxing-test-sync \
    '#!/usr/bin/env bash' \
    'printf "sync %s\\n" "$*" >> "$CALLS"' \
    'if [[ " $* " == *" $TEST_ROOT/state/home_takeover_state "* && -e "$TEST_ROOT/switch_home_after_takeover_state_sync" ]]; then printf "com.example.caregiverlauncher\\n" > "$HOME_HOLDER"; rm -f "$TEST_ROOT/switch_home_after_takeover_state_sync"; fi' \
    'if [[ " $* " == *" $TEST_ROOT/state/home_previous_holder "* ]]; then [[ -e "$TEST_ROOT/hang_home_marker_sync" ]] && /bin/sleep 5; [[ -e "$TEST_ROOT/fail_home_marker_sync" ]] && exit 1; fi' \
    'exit 0'

write_fake mv \
    '#!/usr/bin/env bash' \
    'target="${!#}"' \
    'if [[ -e "$TEST_ROOT/concurrent_home_marker_publish" && "$target" == "$TEST_ROOT/state/home_previous_holder" ]]; then if mkdir "$TEST_ROOT/home_publish_slot_one" 2>/dev/null; then touch "$TEST_ROOT/home_publish_first_ready"; for _ in $(seq 1 500); do [[ -e "$TEST_ROOT/home_publish_second_ready" ]] && break; /bin/sleep 0.01; done; [[ -e "$TEST_ROOT/home_publish_second_ready" ]] || exit 90; /bin/sleep 0.1; else touch "$TEST_ROOT/home_publish_second_ready"; fi; fi' \
    'if [[ -e "$TEST_ROOT/doze_marker_directory_race" && "$target" == "$TEST_ROOT/state/doze_added_by_module" ]]; then rm -f "$target"; mkdir -p "$target"; fi' \
    'exec /bin/mv "$@"'

write_fake yinxing-test-ln \
    '#!/usr/bin/env bash' \
    'target="${!#}"' \
    'if [[ -e "$TEST_ROOT/pause_home_marker_publish" && "$target" == "$TEST_ROOT/state/home_previous_holder" ]]; then touch "$TEST_ROOT/home_marker_publish_entered"; for _ in $(seq 1 400); do [[ -e "$TEST_ROOT/allow_home_marker_publish" ]] && break; /bin/sleep 0.01; done; [[ -e "$TEST_ROOT/allow_home_marker_publish" ]] || exit 89; fi' \
    'if [[ -e "$TEST_ROOT/concurrent_home_marker_publish" && "$target" == "$TEST_ROOT/state/home_previous_holder" ]]; then if mkdir "$TEST_ROOT/home_publish_slot_one" 2>/dev/null; then touch "$TEST_ROOT/home_publish_first_ready"; for _ in $(seq 1 500); do [[ -e "$TEST_ROOT/home_publish_second_ready" ]] && break; /bin/sleep 0.01; done; [[ -e "$TEST_ROOT/home_publish_second_ready" ]] || exit 90; /bin/sleep 0.1; else touch "$TEST_ROOT/home_publish_second_ready"; fi; fi' \
    'exec /bin/ln "$@"'

write_fake am \
    '#!/usr/bin/env bash' \
    'printf "am %s\\n" "$*" >> "$CALLS"' \
    'if [[ -e "$TEST_ROOT/hang_am" ]]; then /bin/sleep 5; fi' \
    'if [[ -e "$TEST_ROOT/hang_am_descendant" ]]; then /bin/sleep 5 & child_pid=$!; printf "%s\\n" "$child_pid" > "$TEST_ROOT/hang_am_descendant_pid"; wait "$child_pid"; fi' \
    'if [[ -e "$TEST_ROOT/fail_home_once" ]]; then rm -f "$TEST_ROOT/fail_home_once"; exit 1; fi' \
    'printf launched > "$TEST_ROOT/home_launched"'

write_fake getprop \
    '#!/usr/bin/env bash' \
    'printf "getprop %s\\n" "$*" >> "$CALLS"' \
    'if [[ -e "$TEST_ROOT/boot_incomplete_once" ]]; then calls="$(cat "$TEST_ROOT/boot_incomplete_calls" 2>/dev/null || printf 0)"; calls=$((calls + 1)); printf "%s\\n" "$calls" > "$TEST_ROOT/boot_incomplete_calls"; if [[ "$calls" -ge 2 ]]; then rm -f "$TEST_ROOT/boot_incomplete_once"; fi; exit 1; fi' \
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

write_fake dumpsys \
    '#!/usr/bin/env bash' \
    'printf "dumpsys %s\\n" "$*" >> "$CALLS"' \
    '[[ "${1:-}" == "accessibility" ]] || exit 2' \
    'if [[ -e "$TEST_ROOT/hang_dumpsys" ]]; then /bin/sleep 5; fi' \
    '[[ -e "$TEST_ROOT/fail_accessibility_dump" ]] && exit 1' \
    'if [[ -d "$TEST_ROOT/accessibility_dump_sequence" ]]; then' \
    '  sequence_call="$(cat "$TEST_ROOT/accessibility_dump_sequence_calls" 2>/dev/null || printf 0)"' \
    '  sequence_call=$((sequence_call + 1))' \
    '  printf "%s\\n" "$sequence_call" > "$TEST_ROOT/accessibility_dump_sequence_calls"' \
    '  sequence_response="$TEST_ROOT/accessibility_dump_sequence/$sequence_call"' \
    '  [[ -f "$sequence_response" ]] || sequence_response="$TEST_ROOT/accessibility_dump_sequence/last"' \
    '  [[ -f "$sequence_response" ]] && cat "$sequence_response"' \
    '  exit 0' \
    'fi' \
    '[[ -f "$TEST_ROOT/accessibility_dump" ]] && cat "$TEST_ROOT/accessibility_dump"' \
    'exit 0'

write_proc_stat() {
    local pid="$1"
    local start_time="$2"
    mkdir -p "$TEST_ROOT/proc/$pid"
    {
        printf '%s (yinxing-guard) S' "$pid"
        for _ in $(seq 1 18); do printf ' 1'; done
        printf ' %s\n' "$start_time"
    } > "$TEST_ROOT/proc/$pid/stat"
}

read_host_proc_start_time() {
    local pid="$1"
    awk '{ sub(/^.*\) /, ""); print $20; exit }' "/proc/$pid/stat"
}

# The assertions describe observable state and command effects, not source text.
CLEANUP_SOURCE="$MODULE_ROOT/bin/uninstall-cleanup.sh"
export CLEANUP_SOURCE
source "$MODULE_ROOT/bin/common.sh"
export ACCESSIBILITY_COMPONENT

reset_fixture() {
    : > "$CALLS"
    : > "$SERVICES"
    printf '0\n' > "$ACCESSIBILITY_ENABLED"
    rm -f \
        "$TEST_ROOT/package_missing" \
        "$TEST_ROOT/package_missing_once" \
        "$TEST_ROOT/boot_incomplete_once" \
        "$TEST_ROOT/boot_incomplete_calls" \
        "$TEST_ROOT/fail_appops" \
        "$TEST_ROOT/fail_settings_get" \
        "$TEST_ROOT/fail_settings_put" \
        "$TEST_ROOT/fail_settings_services_put_after_apply" \
        "$TEST_ROOT/fail_settings_enabled_put_after_apply" \
        "$TEST_ROOT/fail_accessibility_compensation_services" \
        "$TEST_ROOT/fail_pm_list" \
        "$TEST_ROOT/fail_pm_dump" \
        "$TEST_ROOT/fail_pm_enable" \
        "$TEST_ROOT/fail_home_role_query" \
        "$TEST_ROOT/fail_home_role_set" \
        "$TEST_ROOT/fail_home_role_restore" \
        "$TEST_ROOT/fail_home_role_remove" \
        "$TEST_ROOT/hang_home_role_query" \
        "$TEST_ROOT/hang_home_role_set" \
        "$TEST_ROOT/hang_home_role_remove" \
        "$TEST_ROOT/pause_home_role_set" \
        "$TEST_ROOT/home_role_set_entered" \
        "$TEST_ROOT/allow_home_role_set" \
        "$TEST_ROOT/pause_home_marker_publish" \
        "$TEST_ROOT/home_marker_publish_entered" \
        "$TEST_ROOT/allow_home_marker_publish" \
        "$TEST_ROOT/hang_home_marker_sync" \
        "$TEST_ROOT/ignore_home_role_set" \
        "$TEST_ROOT/ignore_home_role_remove" \
        "$TEST_ROOT/fail_home_marker_sync" \
        "$TEST_ROOT/concurrent_home_marker_publish" \
        "$TEST_ROOT/home_publish_first_ready" \
        "$TEST_ROOT/home_publish_second_ready" \
        "$TEST_ROOT/deactivate_during_home_role_set" \
        "$TEST_ROOT/deactivate_during_doze_add" \
        "$TEST_ROOT/deactivate_during_first_appops" \
        "$TEST_ROOT/deactivate_during_package_path" \
        "$TEST_ROOT/deactivate_during_accessibility_read" \
        "$TEST_ROOT/deactivate_during_accessibility_services_put" \
        "$TEST_ROOT/deactivate_during_accessibility_enabled_put" \
        "$TEST_ROOT/deactivate_during_accessibility_rebind_remove" \
        "$TEST_ROOT/deactivate_during_accessibility_rebind_restore" \
        "$TEST_ROOT/caregiver_services_during_rebind_remove" \
        "$TEST_ROOT/accessibility_rebind_removed" \
        "$TEST_ROOT/late_home_role_set" \
        "$TEST_ROOT/late_home_target" \
        "$TEST_ROOT/late_home_reads" \
        "$TEST_ROOT/malformed_home_role_output" \
        "$TEST_ROOT/previous_home_missing" \
        "$TEST_ROOT/switch_home_during_previous_path" \
        "$TEST_ROOT/switch_home_after_takeover_state_sync" \
        "$TEST_ROOT/fail_deviceidle_query" \
        "$TEST_ROOT/fail_deviceidle_add_after_apply" \
        "$TEST_ROOT/pause_deviceidle_add" \
        "$TEST_ROOT/deviceidle_add_entered" \
        "$TEST_ROOT/allow_deviceidle_add" \
        "$TEST_ROOT/fail_deviceidle_remove" \
        "$TEST_ROOT/fail_deviceidle_remove_after_apply" \
        "$TEST_ROOT/ignore_deviceidle_remove" \
        "$TEST_ROOT/doze_marker_directory_race" \
        "$TEST_ROOT/cleanup_boot_id" \
        "$TEST_ROOT/fail_home_once" \
        "$TEST_ROOT/hang_dumpsys" \
        "$TEST_ROOT/hang_pm_path" \
        "$TEST_ROOT/hang_am" \
        "$TEST_ROOT/hang_am_descendant" \
        "$TEST_ROOT/hang_am_descendant_pid" \
        "$TEST_ROOT/hang_deviceidle_remove" \
        "$TEST_ROOT/use_real_sleep" \
        "$TEST_ROOT/accessibility_dump" \
        "$TEST_ROOT/accessibility_dump_sequence_calls" \
        "$TEST_ROOT/fail_accessibility_dump" \
        "$TEST_ROOT/home_launched" \
        "$TEST_ROOT/doze_whitelisted" \
        "$TEST_ROOT/package_disabled" \
        "$TEST_ROOT/component_disabled" \
        "$TEST_ROOT/log_noise"
    rm -rf "$TEST_ROOT/proc" "$TEST_ROOT/state" "$TEST_ROOT/boot-completed.d" "$TEST_ROOT/modules" \
        "$TEST_ROOT/accessibility_dump_sequence" "$TEST_ROOT/home_publish_slot_one"
    printf 'fixture-boot\n' > "$TEST_ROOT/boot_id"
    printf 'com.oplus.launcher\n' > "$HOME_HOLDER"
    install_cleanup_helper "$MODULE_ROOT/bin/uninstall-cleanup.sh" || fail "could not install baseline cleanup helper"
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
    printf '%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '1\n' > "$ACCESSIBILITY_ENABLED"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
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
    assert_contains_text "$output" "schema=2"
    assert_contains_text "$output" "module=active"
    assert_contains_text "$output" "guard=running"
    assert_contains_text "$output" "accessibility=enabled"
    assert_contains_text "$output" "home=owned"
    assert_contains_text "$output" "doze=owned"
    assert_contains_text "$output" "cleanup=ready"
    assert_contains_text "$output" "last_repair=ok"
    pass "status reports healthy state"
}

test_status_reports_stale_cleanup_helper_as_invalid() {
    reset_fixture
    prepare_healthy_status_fixture
    printf '#!/system/bin/sh\nexit 0\n' > "$CLEANUP_TARGET"
    chmod 0755 "$CLEANUP_TARGET"
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "cleanup=invalid"
    pass "status rejects stale cleanup helper"
}

test_status_reports_other_home_holder() {
    reset_fixture
    prepare_healthy_status_fixture
    printf 'com.oplus.launcher\n' > "$HOME_HOLDER"
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "home=other"
    pass "status reports another HOME holder"
}

test_status_reports_no_home_holder() {
    reset_fixture
    prepare_healthy_status_fixture
    : > "$HOME_HOLDER"
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "home=none"
    pass "status reports no HOME holder"
}

test_status_reports_unknown_home_holder() {
    reset_fixture
    prepare_healthy_status_fixture
    touch "$TEST_ROOT/fail_home_role_query"
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "home=unknown"
    pass "status reports unknown HOME holder"
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

test_status_reports_stale_when_accessibility_service_crashed() {
    reset_fixture
    prepare_healthy_status_fixture
    cat > "$TEST_ROOT/accessibility_dump" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{}
  Crashed services:{$ACCESSIBILITY_COMPONENT}
  Client list info:{}
]
EOF
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "accessibility=stale"
    pass "status reports stale crashed accessibility service"
}

test_status_reports_stale_when_accessibility_service_confirmed_unbound() {
    reset_fixture
    prepare_healthy_status_fixture
    cat > "$TEST_ROOT/accessibility_dump" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{}
  Crashed services:{}
  Client list info:{}
]
EOF
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "accessibility=stale"
    pass "status reports stale confirmed-unbound accessibility service"
}

test_status_output_contract_ignores_log_noise() {
    reset_fixture
    prepare_healthy_status_fixture
    touch "$TEST_ROOT/fail_deviceidle_query" "$TEST_ROOT/log_noise"
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_equals "9" "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" "status output line count"
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

test_status_reports_stale_guard_when_pid_identity_mismatches() {
    reset_fixture
    prepare_healthy_status_fixture
    rm -rf "$TEST_ROOT/state/guard.lock/test-boot"
    mkdir -p "$TEST_ROOT/state/guard.lock/test-boot"
    /bin/sleep 30 &
    LIVE_PID=$!
    printf '%s\n' "$LIVE_PID" > "$TEST_ROOT/state/guard.lock/test-boot/pid"
    printf 'test-boot\n' > "$TEST_ROOT/state/guard.lock/test-boot/boot_id"
    write_proc_stat "$LIVE_PID" 111
    printf '222\n' > "$TEST_ROOT/state/guard.lock/test-boot/start_time"
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        YINXING_GUARD_PROC_ROOT="$TEST_ROOT/proc" \
        run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "guard=stale"
    kill "$LIVE_PID" 2>/dev/null || true
    wait "$LIVE_PID" 2>/dev/null || true
    LIVE_PID=""
    pass "status reports stale guard on PID identity mismatch"
}

test_status_reports_missing_module() {
    reset_fixture
    output="$(YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        run_module_script "$MODULE_ROOT/bin/status.sh")"
    assert_contains_text "$output" "module=missing"
    assert_contains_text "$output" "guard=missing"
    assert_contains_text "$output" "accessibility=missing"
    assert_contains_text "$output" "home=unknown"
    pass "status reports missing module"
}

test_home_role_owned_is_idempotent() {
    reset_fixture
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    repair_state || fail "owned HOME should be healthy"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || fail "manual HOME ownership was claimed"
    pass "owned HOME role is idempotent"
}

test_home_role_reconciles_other_holder() {
    reset_fixture
    repair_state || fail "another HOME holder should be reconciled"
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" "HOME takeover"
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" "prior HOME marker"
    assert_equals "600" "$(stat -c '%a' "$TEST_ROOT/state/home_previous_holder")" \
        "prior HOME marker mode"
    assert_equals "owned" "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state")" \
        "confirmed HOME takeover state"
    assert_equals "1" \
        "$(grep -c '^cmd package set-home-activity --user 0 com.yinxing.launcher/.feature.home.MainActivity$' "$CALLS")" \
        "fixed HOME takeover count"
    pass "HOME role reconciles another holder"
}

test_home_role_reconciles_no_holder() {
    reset_fixture
    : > "$HOME_HOLDER"
    repair_state || fail "empty HOME should be reconciled"
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" "empty HOME takeover"
    assert_equals "none" "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "empty HOME marker"
    pass "HOME role reconciles no holder"
}

test_home_role_query_failure_is_safe() {
    reset_fixture
    touch "$TEST_ROOT/fail_home_role_query"
    if run_module_script "$MODULE_ROOT/action.sh"; then
        fail "failed HOME query unexpectedly reported recovery success"
    fi
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "failed HOME query preserves holder"
    assert_equals "failed" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" \
        "failed HOME query repair result"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "am start"
    pass "HOME role query failure is safe"
}

test_home_role_malformed_output_is_safe() {
    reset_fixture
    printf 'bad holder\n' > "$TEST_ROOT/malformed_home_role_output"
    if run_module_script "$MODULE_ROOT/action.sh"; then
        fail "malformed HOME output unexpectedly reported recovery success"
    fi
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "malformed HOME output preserves holder"
    assert_equals "failed" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" \
        "malformed HOME output repair result"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "am start"
    pass "malformed HOME role output is safe"
}

test_home_role_multiple_holders_are_safe() {
    reset_fixture
    printf 'com.oplus.launcher\ncom.example.launcher\n' > "$TEST_ROOT/malformed_home_role_output"
    if run_module_script "$MODULE_ROOT/action.sh"; then
        fail "multiple HOME holders unexpectedly reported recovery success"
    fi
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "multiple HOME holders preserve current holder"
    assert_equals "failed" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" \
        "multiple HOME holders repair result"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "am start"
    pass "multiple HOME role holders are safe"
}

test_home_role_rejects_invalid_android_package_names() {
    local holder long_holder

    long_holder="com.$(printf '%220s' '' | tr ' ' a)"
    for holder in 1.2 _bad.home com.2launcher com.bad-name "$long_holder"; do
        reset_fixture
        printf '%s\n' "$holder" > "$TEST_ROOT/malformed_home_role_output"
        if run_module_script "$MODULE_ROOT/action.sh"; then
            fail "invalid Android HOME package unexpectedly reported recovery success ($holder)"
        fi
        assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
            "invalid Android HOME package preserves holder ($holder)"
        assert_not_contains "$CALLS" "cmd package set-home-activity"
        assert_not_contains "$CALLS" "am start"
    done
    pass "HOME role rejects invalid Android package names"
}

test_home_marker_rejects_invalid_android_package_names() {
    local holder long_holder

    long_holder="com.$(printf '%220s' '' | tr ' ' a)"
    for holder in 1.2 _bad.home com.2launcher com.bad-name "$long_holder"; do
        reset_fixture
        mkdir -p "$TEST_ROOT/state"
        printf '%s\n' "$holder" > "$TEST_ROOT/state/home_previous_holder"
        if run_module_script "$MODULE_ROOT/action.sh"; then
            fail "invalid Android HOME marker unexpectedly reported recovery success ($holder)"
        fi
        assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
            "invalid Android HOME marker preserves holder ($holder)"
        assert_not_contains "$CALLS" "cmd package set-home-activity"
        assert_not_contains "$CALLS" "am start"
    done
    pass "HOME rollback marker rejects invalid Android package names"
}

test_android_package_name_length_boundary() {
    local max_holder oversized_holder

    max_holder="com.$(printf '%219s' '' | tr ' ' a)"
    oversized_holder="com.$(printf '%220s' '' | tr ' ' a)"
    assert_equals "223" "${#max_holder}" "maximum Android package name fixture"
    assert_equals "224" "${#oversized_holder}" "oversized Android package name fixture"
    run_module_script -c '. "$1"; valid_android_package_name "$2"' \
        yinxing-test "$MODULE_ROOT/bin/common.sh" "$max_holder" || \
        fail "223-byte Android package name was rejected"
    if run_module_script -c '. "$1"; valid_android_package_name "$2"' \
        yinxing-test "$MODULE_ROOT/bin/common.sh" "$oversized_holder"; then
        fail "224-byte Android package name was accepted"
    fi
    pass "Android package name length is bounded"
}

test_home_role_invalid_marker_is_safe() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'bad holder\n' > "$TEST_ROOT/state/home_previous_holder"
    if run_module_script "$MODULE_ROOT/action.sh"; then
        fail "invalid HOME marker unexpectedly reported recovery success"
    fi
    assert_equals "bad holder" "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "invalid HOME marker is retained"
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "invalid HOME marker preserves holder"
    assert_equals "failed" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" \
        "invalid HOME marker repair result"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "am start"
    pass "invalid HOME role marker is safe"
}

test_home_role_marker_write_failure_is_safe() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state/home_previous_holder.tmp.$$"
    if repair_state; then
        fail "HOME marker write failure unexpectedly reported success"
    fi
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "HOME marker write failure preserves holder"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "am start"
    pass "HOME role marker write failure is safe"
}

test_home_role_set_failure_retains_marker() {
    reset_fixture
    touch "$TEST_ROOT/fail_home_role_set"
    if run_module_script "$MODULE_ROOT/action.sh"; then
        fail "failed HOME set unexpectedly reported recovery success"
    fi
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "failed HOME set preserves holder"
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "failed HOME set retains prior holder"
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state" | sed 's/^pending|[^|]*|//')" \
        "failed HOME set retains pending holder"
    assert_equals "failed" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" \
        "failed HOME set repair result"
    assert_not_contains "$CALLS" "am start"
    pass "HOME role set failure retains marker"
}

test_home_role_unconfirmed_set_retains_marker() {
    reset_fixture
    touch "$TEST_ROOT/ignore_home_role_set"
    if run_module_script "$MODULE_ROOT/action.sh"; then
        fail "unconfirmed HOME set unexpectedly reported recovery success"
    fi
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "unconfirmed HOME set preserves holder"
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "unconfirmed HOME set retains prior holder"
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state" | sed 's/^pending|[^|]*|//')" \
        "unconfirmed HOME set retains pending holder"
    assert_equals "failed" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" \
        "unconfirmed HOME set repair result"
    assert_not_contains "$CALLS" "am start"
    pass "unconfirmed HOME role set retains marker"
}

test_home_role_bounds_stalled_query() {
    local started_at elapsed

    reset_fixture
    touch "$TEST_ROOT/hang_home_role_query"
    started_at=$SECONDS
    if YINXING_GUARD_COMMAND_TIMEOUT_SECONDS=1 run_module_script "$MODULE_ROOT/action.sh"; then
        fail "stalled HOME query unexpectedly reported recovery success"
    fi
    elapsed=$((SECONDS - started_at))
    [[ "$elapsed" -lt 4 ]] || fail "stalled HOME query exceeded bound (${elapsed}s)"
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "stalled HOME query preserves holder"
    assert_equals "failed" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" \
        "stalled HOME query repair result"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "am start"
    pass "HOME role query is bounded"
}

test_home_role_bounds_stalled_set() {
    local started_at elapsed

    reset_fixture
    touch "$TEST_ROOT/hang_home_role_set"
    started_at=$SECONDS
    if YINXING_GUARD_COMMAND_TIMEOUT_SECONDS=1 run_module_script "$MODULE_ROOT/action.sh"; then
        fail "stalled HOME set unexpectedly reported recovery success"
    fi
    elapsed=$((SECONDS - started_at))
    [[ "$elapsed" -lt 4 ]] || fail "stalled HOME set exceeded bound (${elapsed}s)"
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "stalled HOME set preserves holder"
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "stalled HOME set retains prior holder"
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state" | sed 's/^pending|[^|]*|//')" \
        "stalled HOME set retains pending holder"
    assert_equals "failed" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" \
        "stalled HOME set repair result"
    assert_not_contains "$CALLS" "am start"
    pass "HOME role set is bounded"
}

test_home_role_rejects_trailing_blank_query_output() {
    reset_fixture
    printf 'com.oplus.launcher\n\n' > "$TEST_ROOT/malformed_home_role_output"
    if run_module_script "$MODULE_ROOT/action.sh"; then
        fail "HOME query with a trailing blank line unexpectedly reported recovery success"
    fi
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "trailing blank HOME query preserves holder"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "am start"
    pass "HOME role query rejects trailing blank evidence"
}

test_home_role_rejects_trailing_blank_marker() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n\n' > "$TEST_ROOT/state/home_previous_holder"
    if run_module_script "$MODULE_ROOT/action.sh"; then
        fail "HOME marker with a trailing blank line unexpectedly reported recovery success"
    fi
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "trailing blank HOME marker preserves holder"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "am start"
    pass "HOME rollback marker rejects trailing blank evidence"
}

test_home_marker_concurrent_publish_does_not_clobber() {
    local first_status second_status

    reset_fixture
    touch "$TEST_ROOT/concurrent_home_marker_publish"
    run_module_script -c '. "$1"; record_home_previous_holder "$2"' \
        yinxing-test "$MODULE_ROOT/bin/common.sh" com.oplus.launcher &
    GUARD_PID=$!
    for _ in $(seq 1 500); do
        [[ -e "$TEST_ROOT/home_publish_first_ready" ]] && break
        /bin/sleep 0.01
    done
    [[ -e "$TEST_ROOT/home_publish_first_ready" ]] || fail "first HOME marker publisher did not reach commit"
    run_module_script -c '. "$1"; record_home_previous_holder "$2"' \
        yinxing-test "$MODULE_ROOT/bin/common.sh" com.example.caregiverlauncher &
    SECOND_GUARD_PID=$!
    set +e
    wait "$GUARD_PID"
    first_status=$?
    wait "$SECOND_GUARD_PID"
    second_status=$?
    set -e
    GUARD_PID=""
    SECOND_GUARD_PID=""
    assert_equals "0" "$first_status" "first HOME marker publisher status"
    assert_equals "0" "$second_status" "second HOME marker publisher status"
    assert_equals "com.example.caregiverlauncher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "later overwrite must not replace the first committed HOME marker"
    pass "HOME rollback marker publication does not clobber"
}

test_home_marker_sync_failure_blocks_takeover() {
    reset_fixture
    touch "$TEST_ROOT/fail_home_marker_sync"
    if run_module_script "$MODULE_ROOT/action.sh"; then
        fail "HOME takeover succeeded after rollback marker sync failure"
    fi
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "marker sync failure preserves HOME"
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "marker sync failure retains rollback evidence"
    assert_contains "$CALLS" \
        "sync -f $TEST_ROOT/state/home_previous_holder $TEST_ROOT/state"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "am start"
    pass "HOME takeover requires durable rollback marker"
}

test_home_role_preserves_choice_after_takeover_state_publish() {
    reset_fixture
    touch "$TEST_ROOT/switch_home_after_takeover_state_sync"
    if repair_state; then
        fail "HOME repair overwrote a choice made after pending-state publication"
    fi
    assert_equals "com.example.caregiverlauncher" \
        "$(tr -d '\n' < "$HOME_HOLDER")" \
        "post-publication caregiver HOME choice"
    assert_not_contains "$CALLS" \
        "cmd package set-home-activity --user 0 com.yinxing.launcher/.feature.home.MainActivity"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || \
        fail "post-publication HOME choice retained original-holder evidence"
    [[ ! -e "$TEST_ROOT/state/home_takeover_state" ]] || \
        fail "post-publication HOME choice retained takeover state"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    pass "HOME preserves choice made after takeover state publication"
}

test_home_marker_sync_is_bounded() {
    local started_at elapsed

    reset_fixture
    touch "$TEST_ROOT/hang_home_marker_sync"
    started_at=$SECONDS
    if YINXING_GUARD_COMMAND_TIMEOUT_SECONDS=1 run_module_script "$MODULE_ROOT/action.sh"; then
        fail "HOME takeover succeeded after stalled rollback marker sync"
    fi
    elapsed=$((SECONDS - started_at))
    [[ "$elapsed" -lt 4 ]] || fail "rollback marker sync exceeded bound (${elapsed}s)"
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "stalled marker sync preserves HOME"
    [[ -f "$TEST_ROOT/state/home_previous_holder" ]] || fail "stalled sync lost rollback marker"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "am start"
    pass "HOME rollback marker sync is bounded"
}

test_home_marker_uses_default_busybox_applets() {
    local busybox_path default_state

    busybox_path="$(command -v busybox 2>/dev/null || true)"
    [[ -n "$busybox_path" ]] || {
        pass "default BusyBox marker applets unavailable"
        return
    }
    reset_fixture
    default_state="$TEST_ROOT/default-busybox-state"
    PATH=/nonexistent \
        ASH_STANDALONE=1 \
        YINXING_GUARD_BUSYBOX_BIN="$busybox_path" \
        YINXING_GUARD_STATE_DIR="$default_state" \
        YINXING_GUARD_HOME_MARKER_LINK_COMMAND=ln \
        YINXING_GUARD_HOME_MARKER_SYNC_COMMAND=sync \
        "$busybox_path" ash -c '. "$1"; record_home_previous_holder com.oplus.launcher' \
            yinxing-test "$MODULE_ROOT/bin/common.sh"
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$default_state/home_previous_holder")" \
        "default BusyBox marker publication"
    assert_equals "600" "$(stat -c '%a' "$default_state/home_previous_holder")" \
        "default BusyBox marker mode"
    pass "HOME marker uses actual standalone BusyBox applets"
}

test_guard_requires_cleanup_helper_before_home_takeover() {
    reset_fixture
    rm -f "$CLEANUP_TARGET"
    mkdir -p "$CLEANUP_TARGET"
    YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=1 \
        run_module_script "$MODULE_ROOT/bin/guard.sh" || true
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "Guard without a cleanup helper preserves HOME"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "am start"
    pass "Guard requires rollback cleanup before HOME takeover"
}

test_guard_rejects_stale_cleanup_helper_when_refresh_fails() {
    local cleanup_dir guard_status

    reset_fixture
    cleanup_dir=${CLEANUP_TARGET%/*}
    printf '#!/system/bin/sh\nexit 0\n' > "$CLEANUP_TARGET"
    chmod 0755 "$CLEANUP_TARGET"
    chmod 0500 "$cleanup_dir"
    set +e
    YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=1 \
        run_module_script "$MODULE_ROOT/bin/guard.sh"
    guard_status=$?
    set -e
    chmod 0700 "$cleanup_dir"
    [[ "$guard_status" -eq 0 || "$guard_status" -eq 1 ]] || \
        fail "Guard returned unexpected stale-helper status ($guard_status)"
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "stale cleanup helper blocks HOME takeover"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "am start"
    pass "Guard rejects stale cleanup helper when refresh fails"
}

test_repair_preserves_and_enables() {
    reset_fixture
    printf 'talkback:other\n' > "$SERVICES"
    repair_state || fail "repair_state should succeed for installed package"
    assert_equals "talkback:other:$ACCESSIBILITY_COMPONENT" "$(tr -d '\n' < "$SERVICES")" "repair preserves existing services"
    assert_contains "$CALLS" "settings --user 0 put secure enabled_accessibility_services"
    assert_contains "$CALLS" "settings --user 0 put secure accessibility_enabled 1"
    [[ ! -e "$TEST_ROOT/state/accessibility_transaction" ]] || \
        fail "successful accessibility repair retained transaction evidence"
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

test_repair_retains_noncanonical_accessibility_transaction() {
    local journal marker="$TEST_ROOT/state/accessibility_transaction"

    for journal in \
        "pending|0|1|null|$ACCESSIBILITY_COMPONENT|" \
        "pending|0|1|NULL|$ACCESSIBILITY_COMPONENT|" \
        "pending|0|1|   |$ACCESSIBILITY_COMPONENT|" \
        "pending|0|1|null:$ACCESSIBILITY_COMPONENT|null:$ACCESSIBILITY_COMPONENT|null" \
        "pending|0|1|NULL:$ACCESSIBILITY_COMPONENT|NULL:$ACCESSIBILITY_COMPONENT|NULL"; do
        reset_fixture
        mkdir -p "$TEST_ROOT/state"
        printf '1\n' > "$ACCESSIBILITY_ENABLED"
        printf '%s\n' "$journal" > "$marker"
        if repair_state; then
            fail "noncanonical accessibility transaction unexpectedly recovered"
        fi
        [[ -f "$marker" ]] || \
            fail "noncanonical accessibility transaction lost evidence"
        assert_not_contains "$CALLS" "settings --user 0 put secure"
        assert_not_contains "$CALLS" "cmd package set-home-activity"
        assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    done
    pass "repair retains noncanonical accessibility transaction"
}

test_accessibility_applied_write_errors_are_compensated() {
    local phase control

    for phase in services enabled; do
        reset_fixture
        printf 'talkback:other\n' > "$SERVICES"
        printf '0\n' > "$ACCESSIBILITY_ENABLED"
        case "$phase" in
            services) control="$TEST_ROOT/fail_settings_services_put_after_apply" ;;
            enabled) control="$TEST_ROOT/fail_settings_enabled_put_after_apply" ;;
        esac
        touch "$control"
        if repair_state; then
            fail "applied accessibility write error unexpectedly succeeded ($phase)"
        fi
        assert_equals "talkback:other" "$(tr -d '\n' < "$SERVICES")" \
            "applied accessibility write restores services ($phase)"
        assert_equals "0" "$(tr -d '\n' < "$ACCESSIBILITY_ENABLED")" \
            "applied accessibility write restores global switch ($phase)"
        assert_not_contains "$CALLS" "cmd package set-home-activity"
        assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    done
    pass "applied accessibility write errors are compensated"
}

test_accessibility_initial_writes_roll_back_after_module_deactivation() {
    local phase control

    for phase in services enabled; do
        reset_fixture
        mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
        printf 'talkback:other\n' > "$SERVICES"
        printf '0\n' > "$ACCESSIBILITY_ENABLED"
        case "$phase" in
            services) control="$TEST_ROOT/deactivate_during_accessibility_services_put" ;;
            enabled) control="$TEST_ROOT/deactivate_during_accessibility_enabled_put" ;;
        esac
        printf 'disable\n' > "$control"
        if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
            run_module_script "$MODULE_ROOT/action.sh"; then
            fail "accessibility repair survived module deactivation ($phase)"
        fi
        assert_equals "talkback:other" "$(tr -d '\n' < "$SERVICES")" \
            "deactivated accessibility repair restores services ($phase)"
        assert_equals "0" "$(tr -d '\n' < "$ACCESSIBILITY_ENABLED")" \
            "deactivated accessibility repair restores global switch ($phase)"
        assert_not_contains "$CALLS" "cmd package set-home-activity"
        assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    done
    pass "accessibility initial writes roll back after module deactivation"
}

test_accessibility_failed_compensation_is_recovered_on_uninstall() {
    reset_fixture
    mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
    printf 'talkback:other\n' > "$SERVICES"
    printf '0\n' > "$ACCESSIBILITY_ENABLED"
    printf 'disable\n' > \
        "$TEST_ROOT/deactivate_during_accessibility_enabled_put"
    printf 'talkback:other\n' > \
        "$TEST_ROOT/fail_accessibility_compensation_services"
    if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
        run_module_script "$MODULE_ROOT/action.sh"; then
        fail "failed accessibility compensation unexpectedly succeeded"
    fi
    [[ -f "$TEST_ROOT/state/accessibility_transaction" ]] || \
        fail "failed accessibility compensation lost durable evidence"
    assert_equals "talkback:other:$ACCESSIBILITY_COMPONENT" \
        "$(tr -d '\n' < "$SERVICES")" \
        "failed accessibility compensation retains transaction-owned services"
    assert_equals "1" "$(tr -d '\n' < "$ACCESSIBILITY_ENABLED")" \
        "failed accessibility compensation retains transaction-owned switch"

    run_module_script "$MODULE_ROOT/uninstall.sh"
    touch "$YINXING_GUARD_TEST_MODULE_DIR/remove"
    rm -f "$TEST_ROOT/fail_accessibility_compensation_services"
    run_module_script "$CLEANUP_TARGET"
    assert_equals "talkback:other" "$(tr -d '\n' < "$SERVICES")" \
        "uninstall restores accessibility services after failed compensation"
    assert_equals "0" "$(tr -d '\n' < "$ACCESSIBILITY_ENABLED")" \
        "uninstall restores accessibility switch after failed compensation"
    [[ ! -e "$TEST_ROOT/state/accessibility_transaction" ]] || \
        fail "uninstall retained recovered accessibility evidence"
    [[ ! -e "$CLEANUP_TARGET" ]] || \
        fail "uninstall retained accessibility recovery helper"
    pass "failed accessibility compensation is recovered on uninstall"
}

test_repair_confirms_binding_after_crash() {
    reset_fixture
    printf 'talkback:other:%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '1\n' > "$ACCESSIBILITY_ENABLED"
    mkdir -p "$TEST_ROOT/accessibility_dump_sequence"
    cat > "$TEST_ROOT/accessibility_dump_sequence/1" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{}
  Crashed services:{$ACCESSIBILITY_COMPONENT}
  Client list info:{}
]
EOF
    cp "$TEST_ROOT/accessibility_dump_sequence/1" "$TEST_ROOT/accessibility_dump_sequence/2"
    cat > "$TEST_ROOT/accessibility_dump_sequence/3" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{$ACCESSIBILITY_COMPONENT}
  Crashed services:{}
  Client list info:{}
]
EOF
    YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS=3 \
    YINXING_GUARD_REBIND_CONFIRM_SECONDS=0 \
        repair_state || fail "crashed accessibility service should be rebound"
    assert_equals "talkback:other:$ACCESSIBILITY_COMPONENT" "$(tr -d '\n' < "$SERVICES")" \
        "rebind preserves existing services"
    assert_equals "3" "$(grep -c '^dumpsys accessibility$' "$CALLS" || true)" \
        "rebind should poll until binding is observed"
    assert_equals "2" "$(grep -c '^settings --user 0 put secure enabled_accessibility_services' "$CALLS" || true)" \
        "binding confirmation must not repeat the remove/restore pair"
    assert_contains "$CALLS" "settings --user 0 put secure enabled_accessibility_services talkback:other"
    assert_contains "$CALLS" "settings --user 0 put secure enabled_accessibility_services talkback:other:$ACCESSIBILITY_COMPONENT"
    assert_not_contains "$CALLS" "settings --user 0 put secure accessibility_enabled 1"
    assert_contains "$CALLS" "accessibility_service_rebind_confirmed"
    assert_contains "$CALLS" "accessibility_service_rebound"
    pass "repair confirms accessibility binding after crash"
}

test_repair_confirms_binding_after_confirmed_unbound() {
    reset_fixture
    printf 'talkback:other:%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '1\n' > "$ACCESSIBILITY_ENABLED"
    mkdir -p "$TEST_ROOT/accessibility_dump_sequence"
    cat > "$TEST_ROOT/accessibility_dump_sequence/1" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{}
  Crashed services:{}
  Client list info:{}
]
EOF
    cat > "$TEST_ROOT/accessibility_dump_sequence/2" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{$ACCESSIBILITY_COMPONENT}
  Crashed services:{}
  Client list info:{}
]
EOF
    YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS=2 \
    YINXING_GUARD_REBIND_CONFIRM_SECONDS=0 \
        repair_state || fail "confirmed unbound service should be rebound"
    assert_equals "2" "$(grep -c '^dumpsys accessibility$' "$CALLS" || true)" \
        "confirmed unbound rebind should poll until binding is observed"
    assert_equals "2" "$(grep -c '^settings --user 0 put secure enabled_accessibility_services' "$CALLS" || true)" \
        "confirmed unbound rebind should write the service list twice"
    assert_contains "$CALLS" "settings --user 0 put secure enabled_accessibility_services talkback:other"
    assert_contains "$CALLS" "settings --user 0 put secure enabled_accessibility_services talkback:other:$ACCESSIBILITY_COMPONENT"
    assert_contains "$CALLS" "accessibility_service_rebind_confirmed"
    assert_contains "$CALLS" "accessibility_service_rebound"
    pass "repair confirms accessibility binding after confirmed unbound state"
}

test_rebind_preserves_caregiver_change_when_module_deactivates_after_remove() {
    reset_fixture
    mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
    printf 'talkback:other:%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '0\n' > "$ACCESSIBILITY_ENABLED"
    printf 'caregiver.reader/service\n' > "$TEST_ROOT/caregiver_services_during_rebind_remove"
    printf 'disable\n' > "$TEST_ROOT/deactivate_during_accessibility_rebind_remove"
    cat > "$TEST_ROOT/accessibility_dump" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{}
  Crashed services:{$ACCESSIBILITY_COMPONENT}
  Client list info:{}
]
EOF
    if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
        YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS=1 \
        run_module_script "$MODULE_ROOT/action.sh"; then
        fail "rebind succeeded after module deactivated during temporary removal"
    fi
    assert_equals "caregiver.reader/service" "$(tr -d '\n' < "$SERVICES")" \
        "interrupted rebind preserves newer caregiver services"
    assert_equals "0" "$(tr -d '\n' < "$ACCESSIBILITY_ENABLED")" \
        "interrupted rebind restores the original accessibility switch"
    assert_contains "$CALLS" "settings --user 0 put secure accessibility_enabled 1"
    assert_contains "$CALLS" "settings --user 0 put secure accessibility_enabled 0"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    assert_not_contains "$CALLS" "am start"
    pass "rebind preserves caregiver change after module deactivation"
}

test_rebind_preserves_caregiver_change_while_module_remains_active() {
    reset_fixture
    printf 'talkback:other:%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '1\n' > "$ACCESSIBILITY_ENABLED"
    printf 'caregiver.reader/service\n' > \
        "$TEST_ROOT/caregiver_services_during_rebind_remove"
    cat > "$TEST_ROOT/accessibility_dump" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{}
  Crashed services:{$ACCESSIBILITY_COMPONENT}
  Client list info:{}
]
EOF
    if YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS=1 repair_state; then
        fail "rebind overwrote a caregiver change while the module remained active"
    fi
    assert_equals "caregiver.reader/service" "$(tr -d '\n' < "$SERVICES")" \
        "active rebind preserves newer caregiver services"
    assert_equals "1" "$(tr -d '\n' < "$ACCESSIBILITY_ENABLED")" \
        "active rebind preserves the original global switch"
    assert_equals "1" \
        "$(grep -c '^settings --user 0 put secure enabled_accessibility_services' "$CALLS" || true)" \
        "active rebind only performs the temporary service removal"
    [[ ! -e "$TEST_ROOT/state/accessibility_transaction" ]] || \
        fail "active caregiver preservation retained transaction evidence"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    pass "rebind preserves caregiver change while module remains active"
}

test_rebind_stops_after_module_deactivates_during_restore() {
    reset_fixture
    mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
    printf 'talkback:other:%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '1\n' > "$ACCESSIBILITY_ENABLED"
    printf 'disable\n' > "$TEST_ROOT/deactivate_during_accessibility_rebind_restore"
    cat > "$TEST_ROOT/accessibility_dump" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{}
  Crashed services:{$ACCESSIBILITY_COMPONENT}
  Client list info:{}
]
EOF
    if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
        YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS=1 \
        run_module_script "$MODULE_ROOT/action.sh"; then
        fail "rebind succeeded after module deactivated during service-list restore"
    fi
    assert_equals "talkback:other:$ACCESSIBILITY_COMPONENT" "$(tr -d '\n' < "$SERVICES")" \
        "interrupted restore leaves the original service list"
    assert_not_contains "$CALLS" "settings --user 0 put secure accessibility_enabled 1"
    assert_equals "1" "$(grep -c '^dumpsys accessibility$' "$CALLS" || true)" \
        "interrupted restore must not enter confirmation polling"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    assert_not_contains "$CALLS" "am start"
    pass "rebind stops after module deactivates during restore"
}

test_rebind_restores_original_enabled_state_after_interruption() {
    reset_fixture
    mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
    printf 'talkback:other:%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '0\n' > "$ACCESSIBILITY_ENABLED"
    printf 'disable\n' > "$TEST_ROOT/deactivate_during_accessibility_rebind_remove"
    cat > "$TEST_ROOT/accessibility_dump" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{}
  Crashed services:{$ACCESSIBILITY_COMPONENT}
  Client list info:{}
]
EOF
    if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
        YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS=1 \
        run_module_script "$MODULE_ROOT/action.sh"; then
        fail "rebind succeeded after interruption with an originally disabled service"
    fi
    assert_equals "talkback:other:$ACCESSIBILITY_COMPONENT" \
        "$(tr -d '\n' < "$SERVICES")" \
        "interrupted rebind restores the original service list"
    assert_equals "0" "$(tr -d '\n' < "$ACCESSIBILITY_ENABLED")" \
        "interrupted rebind restores the original accessibility switch"
    assert_contains "$CALLS" "settings --user 0 put secure accessibility_enabled 1"
    assert_contains "$CALLS" "settings --user 0 put secure accessibility_enabled 0"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    pass "rebind restores original accessibility enabled state"
}

test_action_marks_persistent_accessibility_crash_failed() {
    reset_fixture
    printf 'talkback:other:%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '1\n' > "$ACCESSIBILITY_ENABLED"
    mkdir -p "$TEST_ROOT/accessibility_dump_sequence"
    cat > "$TEST_ROOT/accessibility_dump_sequence/1" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{}
  Crashed services:{$ACCESSIBILITY_COMPONENT}
  Client list info:{}
]
EOF
    cp "$TEST_ROOT/accessibility_dump_sequence/1" "$TEST_ROOT/accessibility_dump_sequence/2"
    cp "$TEST_ROOT/accessibility_dump_sequence/1" "$TEST_ROOT/accessibility_dump_sequence/3"
    if YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS=2 \
        YINXING_GUARD_REBIND_CONFIRM_SECONDS=0 \
        run_module_script "$MODULE_ROOT/action.sh"; then
        fail "persistent accessibility crash unexpectedly reported recovery success"
    fi
    assert_equals "failed" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" \
        "persistent crash should record failed repair"
    assert_equals "3" "$(grep -c '^dumpsys accessibility$' "$CALLS" || true)" \
        "persistent crash should stop at the confirmation bound"
    assert_equals "2" "$(grep -c '^settings --user 0 put secure enabled_accessibility_services' "$CALLS" || true)" \
        "persistent crash must not repeat settings toggles"
    assert_not_contains "$CALLS" "am start"
    assert_contains "$CALLS" "accessibility_service_rebind_persisted"
    pass "action marks persistent accessibility crash failed"
}

test_action_marks_persistent_confirmed_unbound_failed() {
    reset_fixture
    printf 'talkback:other:%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '1\n' > "$ACCESSIBILITY_ENABLED"
    mkdir -p "$TEST_ROOT/accessibility_dump_sequence"
    for response in 1 2 3; do
        cat > "$TEST_ROOT/accessibility_dump_sequence/$response" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{}
  Crashed services:{}
  Client list info:{}
]
EOF
    done
    if YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS=2 \
        YINXING_GUARD_REBIND_CONFIRM_SECONDS=0 \
        run_module_script "$MODULE_ROOT/action.sh"; then
        fail "persistent confirmed unbound service unexpectedly reported recovery success"
    fi
    assert_equals "failed" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" \
        "persistent confirmed unbound service should record failed repair"
    assert_equals "3" "$(grep -c '^dumpsys accessibility$' "$CALLS" || true)" \
        "persistent confirmed unbound service should stop at the confirmation bound"
    assert_equals "2" "$(grep -c '^settings --user 0 put secure enabled_accessibility_services' "$CALLS" || true)" \
        "persistent confirmed unbound service must not repeat settings toggles"
    assert_not_contains "$CALLS" "am start"
    assert_contains "$CALLS" "accessibility_service_rebind_persisted"
    pass "action marks persistent confirmed-unbound accessibility service failed"
}

test_repair_does_not_rebind_initial_enable_when_unbound() {
    reset_fixture
    : > "$SERVICES"
    printf '0\n' > "$ACCESSIBILITY_ENABLED"
    cat > "$TEST_ROOT/accessibility_dump" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{}
  Crashed services:{}
  Client list info:{}
]
EOF
    repair_state || fail "initial accessibility enable should succeed"
    assert_equals "1" "$(grep -oF "$ACCESSIBILITY_COMPONENT" "$SERVICES" | wc -l | tr -d ' ')" \
        "initial accessibility enable should include the target once"
    assert_equals "1" "$(grep -c '^settings --user 0 put secure enabled_accessibility_services' "$CALLS" || true)" \
        "initial accessibility enable should write the service list once"
    assert_not_contains "$CALLS" "accessibility_service_rebind"
    pass "repair does not rebind initial enable when unbound"
}

test_repair_ignores_partial_accessibility_diagnostic() {
    reset_fixture
    printf '%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '1\n' > "$ACCESSIBILITY_ENABLED"
    cat > "$TEST_ROOT/accessibility_dump" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{}
]
EOF
    repair_state || fail "partial accessibility diagnostic should not fail repair"
    assert_not_contains "$CALLS" "settings --user 0 put secure"
    assert_not_contains "$CALLS" "accessibility_service_rebind"
    pass "repair ignores partial accessibility diagnostic"
}

test_repair_bounds_stalled_accessibility_diagnostic() {
    local started_at elapsed

    reset_fixture
    printf '%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '1\n' > "$ACCESSIBILITY_ENABLED"
    touch "$TEST_ROOT/hang_dumpsys"
    started_at=$SECONDS
    YINXING_GUARD_COMMAND_TIMEOUT_SECONDS=1 \
        run_module_script -c '. "$1"; repair_state' yinxing-test "$MODULE_ROOT/bin/common.sh" || \
        fail "stalled accessibility diagnostic should remain nonfatal"
    elapsed=$((SECONDS - started_at))
    [[ "$elapsed" -lt 4 ]] || fail "stalled accessibility diagnostic exceeded bound (${elapsed}s)"
    assert_not_contains "$CALLS" "settings --user 0 put secure"
    assert_not_contains "$CALLS" "accessibility_service_rebind"
    pass "repair bounds stalled accessibility diagnostic"
}

test_command_timeout_sanitizes_non_positive_overrides() {
    local output override

    for override in invalid -1 0 00; do
        reset_fixture
        output="$(YINXING_GUARD_COMMAND_TIMEOUT_SECONDS="$override" \
            run_module_script -c '. "$1"; printf "%s\\n" "$GUARD_COMMAND_TIMEOUT_SECONDS"' \
            yinxing-test "$MODULE_ROOT/bin/common.sh")"
        assert_equals "2" "$output" "invalid command timeout '$override' should use the safe default"
    done
    pass "command timeout sanitizes non-positive overrides"
}

test_repair_keeps_unknown_rebind_confirmation_nonfatal() {
    reset_fixture
    printf 'talkback:other:%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '1\n' > "$ACCESSIBILITY_ENABLED"
    mkdir -p "$TEST_ROOT/accessibility_dump_sequence"
    cat > "$TEST_ROOT/accessibility_dump_sequence/1" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{}
  Crashed services:{$ACCESSIBILITY_COMPONENT}
  Client list info:{}
]
EOF
    : > "$TEST_ROOT/accessibility_dump_sequence/2"
    YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS=2 \
    YINXING_GUARD_REBIND_CONFIRM_SECONDS=0 \
        repair_state || fail "unknown accessibility rebind confirmation should remain nonfatal"
    assert_equals "2" "$(grep -c '^dumpsys accessibility$' "$CALLS" || true)" \
        "unknown confirmation should stop after the bounded poll"
    assert_equals "2" "$(grep -c '^settings --user 0 put secure enabled_accessibility_services' "$CALLS" || true)" \
        "unknown confirmation must not repeat settings toggles"
    assert_contains "$CALLS" "accessibility_service_rebind_unverified"
    assert_not_contains "$CALLS" "accessibility_service_rebind_persisted"
    pass "unknown accessibility rebind confirmation remains nonfatal"
}

test_repair_leaves_bound_or_binding_accessibility_service_untouched() {
    local state
    for state in "Bound services" "Binding services"; do
        reset_fixture
        printf '%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
        printf '1\n' > "$ACCESSIBILITY_ENABLED"
        printf 'User state[\n  %s:{%s}\n  Enabled services:{}\n  Crashed services:{}\n  Client list info:{}\n]\n' \
            "$state" "$ACCESSIBILITY_COMPONENT" > "$TEST_ROOT/accessibility_dump"
        repair_state || fail "$state accessibility service should remain healthy"
        assert_not_contains "$CALLS" "settings --user 0 put secure"
    done
    pass "repair leaves bound and binding accessibility services untouched"
}

test_repair_ignores_unavailable_accessibility_diagnostic() {
    reset_fixture
    printf '%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '1\n' > "$ACCESSIBILITY_ENABLED"
    touch "$TEST_ROOT/fail_accessibility_dump"
    repair_state || fail "unavailable accessibility diagnostic should not fail repair"
    assert_not_contains "$CALLS" "settings --user 0 put secure"
    pass "repair ignores unavailable accessibility diagnostic"
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

test_doze_add_nonzero_after_apply_retains_ownership() {
    reset_fixture
    install_cleanup_helper "$MODULE_ROOT/bin/uninstall-cleanup.sh" || \
        fail "could not install applied-error Doze cleanup helper"
    touch "$TEST_ROOT/fail_deviceidle_add_after_apply"
    repair_state || fail "applied Doze add with a client error should remain recoverable"
    [[ -e "$TEST_ROOT/doze_whitelisted" ]] || fail "applied-error Doze add lost whitelist state"
    assert_equals "added" "$(tr -d '\n' < "$TEST_ROOT/state/doze_added_by_module")" \
        "applied-error Doze add ownership marker"
    pass "Doze add retains ownership after an applied client error"
}

test_doze_marker_directory_race_blocks_add() {
    reset_fixture
    install_cleanup_helper "$MODULE_ROOT/bin/uninstall-cleanup.sh" || \
        fail "could not install Doze marker-race cleanup helper"
    touch "$TEST_ROOT/doze_marker_directory_race"
    if repair_state; then
        fail "Doze marker directory race unexpectedly reported full repair success"
    fi
    [[ ! -e "$TEST_ROOT/doze_whitelisted" ]] || \
        fail "Doze add ran without a validated pending ownership marker"
    [[ -d "$TEST_ROOT/state/doze_added_by_module" ]] || \
        fail "Doze marker race fixture did not replace the target with a directory"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    pass "Doze marker directory race blocks add"
}

test_doze_same_boot_pending_absence_does_not_redispatch() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    printf 'pending|fixture-boot\n' > "$TEST_ROOT/state/doze_added_by_module"
    if repair_state; then
        fail "same-boot pending Doze absence unexpectedly resolved"
    fi
    assert_equals "pending|fixture-boot" \
        "$(tr -d '\n' < "$TEST_ROOT/state/doze_added_by_module")" \
        "same-boot Doze pending state"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    assert_not_contains "$CALLS" "cmd appops set"
    pass "same-boot pending Doze absence does not redispatch"
}

test_doze_visible_pending_state_promotes_to_owned() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    printf 'pending|fixture-boot\n' > "$TEST_ROOT/state/doze_added_by_module"
    touch "$TEST_ROOT/doze_whitelisted"
    repair_state || fail "visible pending Doze state should resolve"
    assert_equals "added" \
        "$(tr -d '\n' < "$TEST_ROOT/state/doze_added_by_module")" \
        "visible pending Doze ownership"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    assert_contains "$CALLS" "cmd appops set"
    pass "visible pending Doze state promotes to ownership"
}

test_doze_cross_boot_pending_absence_retries_once() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'next-boot\n' > "$TEST_ROOT/boot_id"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    printf 'pending|previous-boot\n' > "$TEST_ROOT/state/doze_added_by_module"
    repair_state || fail "cross-boot pending Doze absence should retry"
    assert_equals "added" \
        "$(tr -d '\n' < "$TEST_ROOT/state/doze_added_by_module")" \
        "cross-boot Doze retry ownership"
    assert_equals "1" \
        "$(grep -c '^cmd deviceidle whitelist +com.yinxing.launcher$' "$CALLS" || true)" \
        "cross-boot Doze retry count"
    pass "cross-boot pending Doze absence retries once"
}

test_doze_transaction_blocks_cleanup_while_add_is_in_flight() {
    local action_status uninstall_status cleanup_status

    reset_fixture
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    touch "$TEST_ROOT/pause_deviceidle_add"
    (set +e; repair_state) &
    GUARD_PID=$!
    for _ in $(seq 1 200); do
        [[ -e "$TEST_ROOT/deviceidle_add_entered" ]] && break
        /bin/sleep 0.01
    done
    [[ -e "$TEST_ROOT/deviceidle_add_entered" ]] || \
        fail "Doze add did not reach the paused mutation boundary"
    assert_equals "pending|fixture-boot" \
        "$(tr -d '\n' < "$TEST_ROOT/state/doze_added_by_module")" \
        "in-flight Doze ownership state"

    set +e
    run_module_script "$MODULE_ROOT/uninstall.sh"
    uninstall_status=$?
    run_module_script "$CLEANUP_TARGET"
    cleanup_status=$?
    touch "$TEST_ROOT/allow_deviceidle_add"
    wait "$GUARD_PID"
    action_status=$?
    set -e
    GUARD_PID=""

    [[ "$uninstall_status" -ne 0 ]] || \
        fail "uninstall entered an in-flight Doze transaction"
    [[ "$cleanup_status" -ne 0 ]] || \
        fail "cleanup entered an in-flight Doze transaction"
    assert_equals "0" "$action_status" "in-flight Doze action status"
    [[ -e "$TEST_ROOT/doze_whitelisted" ]] || \
        fail "serialized Doze add did not complete"
    assert_equals "added" \
        "$(tr -d '\n' < "$TEST_ROOT/state/doze_added_by_module")" \
        "serialized Doze ownership state"
    [[ -x "$CLEANUP_TARGET" ]] || \
        fail "blocked Doze cleanup removed its retry helper"

    run_module_script "$MODULE_ROOT/uninstall.sh"
    run_module_script "$CLEANUP_TARGET"
    [[ ! -e "$TEST_ROOT/doze_whitelisted" ]] || \
        fail "serialized Doze cleanup retained the whitelist"
    [[ ! -e "$TEST_ROOT/state/doze_added_by_module" ]] || \
        fail "serialized Doze cleanup retained ownership evidence"
    pass "Doze transaction blocks cleanup while add is in flight"
}

test_home_launch_is_fixed() {
    reset_fixture
    launch_home || fail "home launch should succeed with fake am"
    [[ -e "$TEST_ROOT/home_launched" ]] || fail "home activity was not launched"
    assert_contains "$CALLS" "com.yinxing.launcher/.feature.home.MainActivity"
    pass "home launch is fixed"
}

test_kiosk_home_command_requires_active_module() {
    reset_fixture
    mkdir -p "$TEST_ROOT/modules/yinxing_guard"
    run_module_script "$MODULE_ROOT/bin/kiosk-home.sh" || fail "active kiosk home command should succeed"
    [[ -e "$TEST_ROOT/home_launched" ]] || fail "active kiosk home command did not launch HOME"
    assert_equals "1" "$(grep -c '^am start --user 0 -n com.yinxing.launcher/.feature.home.MainActivity$' "$CALLS" || true)" \
        "kiosk home command should launch the fixed HOME component once"

    reset_fixture
    mkdir -p "$TEST_ROOT/modules/yinxing_guard"
    touch "$TEST_ROOT/modules/yinxing_guard/disable"
    if run_module_script "$MODULE_ROOT/bin/kiosk-home.sh"; then
        fail "disabled module must reject kiosk home command"
    fi
    [[ ! -e "$TEST_ROOT/home_launched" ]] || fail "disabled module launched HOME"
    assert_not_contains "$CALLS" "am start"

    reset_fixture
    if run_module_script "$MODULE_ROOT/bin/kiosk-home.sh"; then
        fail "missing module must reject kiosk home command"
    fi
    [[ ! -e "$TEST_ROOT/home_launched" ]] || fail "missing module launched HOME"
    assert_not_contains "$CALLS" "am start"
    pass "kiosk home command requires active module"
}

test_kiosk_home_bounds_stalled_launch() {
    local started_at elapsed

    reset_fixture
    mkdir -p "$TEST_ROOT/modules/yinxing_guard"
    touch "$TEST_ROOT/hang_am"
    started_at=$SECONDS
    if YINXING_GUARD_COMMAND_TIMEOUT_SECONDS=1 \
        run_module_script "$MODULE_ROOT/bin/kiosk-home.sh"; then
        fail "stalled kiosk HOME launch unexpectedly succeeded"
    fi
    elapsed=$((SECONDS - started_at))
    [[ "$elapsed" -lt 4 ]] || fail "stalled kiosk HOME launch exceeded bound (${elapsed}s)"
    assert_equals "1" "$(grep -c '^am start --user 0 -n com.yinxing.launcher/.feature.home.MainActivity$' "$CALLS" || true)" \
        "stalled kiosk HOME command should attempt the fixed component once"
    pass "kiosk home bounds stalled launch"
}

test_kiosk_home_cleans_stalled_descendant_after_caller_exit() {
    local descendant_pid

    reset_fixture
    mkdir -p "$TEST_ROOT/modules/yinxing_guard"
    touch "$TEST_ROOT/hang_am_descendant"
    /bin/sleep 5 &
    LIVE_PID=$!
    if [[ "${YINXING_TEST_SHELL:-}" == "busybox" ]]; then
        ASH_STANDALONE=1 YINXING_GUARD_COMMAND_TIMEOUT_SECONDS=1 \
            busybox ash "$MODULE_ROOT/bin/kiosk-home.sh" &
    else
        YINXING_GUARD_COMMAND_TIMEOUT_SECONDS=1 sh "$MODULE_ROOT/bin/kiosk-home.sh" &
    fi
    COMMAND_CALLER_PID=$!
    for _ in $(seq 1 100); do
        [[ -s "$TEST_ROOT/hang_am_descendant_pid" ]] && break
        /bin/sleep 0.02
    done
    [[ -s "$TEST_ROOT/hang_am_descendant_pid" ]] || fail "stalled HOME descendant PID was not published"
    descendant_pid="$(tr -d '\n' < "$TEST_ROOT/hang_am_descendant_pid")"
    STALLED_COMMAND_PID="$descendant_pid"
    kill -KILL "$COMMAND_CALLER_PID" 2>/dev/null || true
    wait "$COMMAND_CALLER_PID" 2>/dev/null || true
    COMMAND_CALLER_PID=""
    /bin/sleep 2.5
    if kill -0 "$descendant_pid" 2>/dev/null; then
        fail "stalled HOME descendant survived caller exit and internal timeout"
    fi
    STALLED_COMMAND_PID=""
    kill -0 "$LIVE_PID" 2>/dev/null || fail "stalled HOME cleanup targeted an unrelated process"
    kill "$LIVE_PID" 2>/dev/null || true
    wait "$LIVE_PID" 2>/dev/null || true
    LIVE_PID=""
    pass "kiosk home cleans stalled descendant after caller exit"
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
    local status
    set +e
    YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=1 \
        run_module_script "$MODULE_ROOT/bin/guard.sh"
    status=$?
    set -e
    assert_equals "76" "$status" "live same-boot guard should report an active owner"
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

test_guard_reclaims_live_pid_with_mismatched_start_time() {
    reset_fixture
    printf 'same-boot-id\n' > "$TEST_ROOT/boot_id"
    mkdir -p "$TEST_ROOT/state/guard.lock/same-boot-id"
    /bin/sleep 30 &
    LIVE_PID=$!
    printf '%s\n' "$LIVE_PID" > "$TEST_ROOT/state/guard.lock/same-boot-id/pid"
    printf 'same-boot-id\n' > "$TEST_ROOT/state/guard.lock/same-boot-id/boot_id"
    printf '999999999999999\n' > "$TEST_ROOT/state/guard.lock/same-boot-id/start_time"
    local status
    set +e
    YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=1 \
        run_module_script "$MODULE_ROOT/bin/guard.sh"
    status=$?
    set -e
    assert_equals "0" "$status" "PID identity mismatch should reclaim the stale lock"
    assert_equals "1" "$(grep -c '^am start ' "$CALLS" || true)" \
        "PID identity mismatch must allow one health cycle"
    kill "$LIVE_PID" 2>/dev/null || true
    wait "$LIVE_PID" 2>/dev/null || true
    LIVE_PID=""
    pass "guard reclaims live PID with mismatched start time"
}

test_guard_keeps_matching_live_owner_active() {
    reset_fixture
    printf 'same-boot-id\n' > "$TEST_ROOT/boot_id"
    mkdir -p "$TEST_ROOT/state/guard.lock/same-boot-id"
    /bin/sleep 30 &
    LIVE_PID=$!
    printf '%s\n' "$LIVE_PID" > "$TEST_ROOT/state/guard.lock/same-boot-id/pid"
    printf 'same-boot-id\n' > "$TEST_ROOT/state/guard.lock/same-boot-id/boot_id"
    read_host_proc_start_time "$LIVE_PID" > "$TEST_ROOT/state/guard.lock/same-boot-id/start_time"
    local status
    set +e
    YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=1 \
        run_module_script "$MODULE_ROOT/bin/guard.sh"
    status=$?
    set -e
    assert_equals "76" "$status" "matching owner identity should remain active"
    assert_equals "0" "$(grep -c '^am start ' "$CALLS" || true)" \
        "matching owner identity must block duplicate health cycles"
    kill "$LIVE_PID" 2>/dev/null || true
    wait "$LIVE_PID" 2>/dev/null || true
    LIVE_PID=""
    pass "guard keeps matching live owner active"
}

test_guard_keeps_live_owner_active_when_identity_unreadable() {
    reset_fixture
    printf 'same-boot-id\n' > "$TEST_ROOT/boot_id"
    mkdir -p "$TEST_ROOT/state/guard.lock/same-boot-id"
    /bin/sleep 30 &
    LIVE_PID=$!
    printf '%s\n' "$LIVE_PID" > "$TEST_ROOT/state/guard.lock/same-boot-id/pid"
    printf 'same-boot-id\n' > "$TEST_ROOT/state/guard.lock/same-boot-id/boot_id"
    printf '111\n' > "$TEST_ROOT/state/guard.lock/same-boot-id/start_time"
    mkdir -p "$TEST_ROOT/proc"
    local status
    set +e
    YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        YINXING_GUARD_PROC_ROOT="$TEST_ROOT/proc" \
        YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=1 \
        run_module_script "$MODULE_ROOT/bin/guard.sh"
    status=$?
    set -e
    assert_equals "76" "$status" "unreadable identity should remain conservative"
    assert_equals "0" "$(grep -c '^am start ' "$CALLS" || true)" \
        "unreadable identity must block duplicate health cycles"
    kill "$LIVE_PID" 2>/dev/null || true
    wait "$LIVE_PID" 2>/dev/null || true
    LIVE_PID=""
    pass "guard keeps live owner active when identity is unreadable"
}

test_guard_publishes_owner_start_time_before_pid() {
    reset_fixture
    printf 'publish-boot-id\n' > "$TEST_ROOT/boot_id"
    touch "$TEST_ROOT/use_real_sleep"
    YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=2 \
        YINXING_GUARD_MAX_CYCLES=1 \
        run_module_script "$MODULE_ROOT/bin/guard.sh" &
    GUARD_PID=$!
    local lock_dir="$TEST_ROOT/state/guard.lock/publish-boot-id"
    local found=0
    for _ in $(seq 1 100); do
        if [ -s "$lock_dir/pid" ] && [ -s "$lock_dir/start_time" ]; then
            found=1
            break
        fi
        /bin/sleep 0.05
    done
    assert_equals "1" "$found" "Guard must publish start_time before its PID"
    [[ "$(tr -d '\n' < "$lock_dir/start_time")" =~ ^[0-9]+$ ]] || \
        fail "published owner start_time is not numeric"
    kill "$GUARD_PID" 2>/dev/null || true
    wait "$GUARD_PID" 2>/dev/null || true
    GUARD_PID=""
    wait_for_guard_shutdown || fail "guard did not stop after owner publication check"
    pass "guard publishes owner start time before PID"
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
    wait_for_guard_shutdown || fail "service did not stop after retrying an incomplete lock"
    pass "service retries incomplete lock"
}

test_service_restarts_non_lock_guard_failure() {
    reset_fixture
    mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
    touch "$TEST_ROOT/boot_incomplete_once"
    YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
        YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_BOOT_WAIT_MAX_CYCLES=1 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=1 \
        YINXING_GUARD_RESTART_SECONDS=0 \
        run_module_script "$MODULE_ROOT/service.sh"
    local found=0
    for _ in $(seq 1 100); do
        if grep -q '^am start ' "$CALLS"; then
            found=1
            break
        fi
        /bin/sleep 0.05
    done
    assert_equals "1" "$found" "service did not restart a non-lock guard failure"
    assert_equals "1" "$(grep -c '^am start ' "$CALLS" || true)" "service restarted guard more than once"
    local boot_calls
    boot_calls="$(cat "$TEST_ROOT/boot_incomplete_calls" 2>/dev/null || printf 0)"
    [[ "$boot_calls" -ge 2 ]] || fail "guard did not fail during boot readiness (calls=$boot_calls)"
    assert_equals "3" "$(grep -c '^getprop sys.boot_completed$' "$CALLS" || true)" \
        "supervisor should start a second guard after the first boot failure"
    wait_for_guard_shutdown || fail "service did not stop after restarting a failed guard"
    pass "service restarts non-lock guard failure"
}

test_service_reclaims_lock_after_owner_disappears() {
    reset_fixture
    mkdir -p "$TEST_ROOT/modules/yinxing_guard" "$TEST_ROOT/state/guard.lock/owner-boot-id"
    printf 'owner-boot-id\n' > "$TEST_ROOT/boot_id"
    /bin/sh -c "sleep 0.2; rm -rf '$TEST_ROOT/state/guard.lock/owner-boot-id'; sleep 1" &
    LIVE_PID=$!
    printf '%s\n' "$LIVE_PID" > "$TEST_ROOT/state/guard.lock/owner-boot-id/pid"
    printf 'owner-boot-id\n' > "$TEST_ROOT/state/guard.lock/owner-boot-id/boot_id"
    touch "$TEST_ROOT/use_real_sleep"
    YINXING_GUARD_MODULE_STATE_DIR="$TEST_ROOT/modules/yinxing_guard" \
        YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
        YINXING_GUARD_OWNER_RETRY_SECONDS=0 \
        YINXING_GUARD_LOCK_RETRY_SECONDS=0 \
        YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
        YINXING_GUARD_INTERVAL_SECONDS=0 \
        YINXING_GUARD_MAX_CYCLES=1 \
        run_module_script "$MODULE_ROOT/service.sh"
    local found=0
    for _ in $(seq 1 100); do
        if grep -q '^am start ' "$CALLS"; then
            found=1
            break
        fi
        /bin/sleep 0.05
    done
    assert_equals "1" "$found" "service did not reclaim lock after owner disappeared"
    assert_equals "1" "$(grep -c '^am start ' "$CALLS" || true)" \
        "service reclaimed owner more than once"
    kill "$LIVE_PID" 2>/dev/null || true
    wait "$LIVE_PID" 2>/dev/null || true
    LIVE_PID=""
    wait_for_guard_shutdown || fail "service did not stop after reclaiming the owner lock"
    pass "service reclaims lock after owner disappears"
}

test_service_stops_when_module_disabled_or_removing() {
    local marker
    for marker in disable remove; do
        reset_fixture
        mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
        touch "$YINXING_GUARD_TEST_MODULE_DIR/$marker"
        YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
            YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
            YINXING_GUARD_INTERVAL_SECONDS=0 \
            YINXING_GUARD_MAX_CYCLES=1 \
            YINXING_GUARD_RESTART_SECONDS=0 \
            run_module_script "$MODULE_ROOT/service.sh"
        /bin/sleep 0.1
        assert_equals "0" "$(grep -c '^pm path ' "$CALLS" || true)" \
            "disabled/removing module must not start guard ($marker)"
    done
    pass "service stops when module disabled or removing"
}

test_guard_rejects_inactive_module_before_initial_repair() {
    local marker

    for marker in disable remove; do
        reset_fixture
        mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
        touch "$YINXING_GUARD_TEST_MODULE_DIR/$marker"
        YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
            YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
            YINXING_GUARD_INTERVAL_SECONDS=0 \
            YINXING_GUARD_MAX_CYCLES=1 \
            run_module_script "$MODULE_ROOT/bin/guard.sh"
        assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
            "inactive Guard changed HOME ($marker)"
        assert_not_contains "$CALLS" "cmd package set-home-activity"
        assert_not_contains "$CALLS" "am start"
    done
    pass "Guard rejects inactive module before initial repair"
}

test_guard_stops_home_enforcement_after_disable_or_remove() {
    local marker observed

    for marker in disable remove; do
        reset_fixture
        mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
        touch "$TEST_ROOT/use_real_sleep"
        YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
            YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
            YINXING_GUARD_INTERVAL_SECONDS=1 \
            YINXING_GUARD_MAX_CYCLES=1 \
            run_module_script "$MODULE_ROOT/bin/guard.sh" &
        GUARD_PID=$!
        observed=0
        for _ in $(seq 1 100); do
            if [ "$(tr -d '\n' < "$HOME_HOLDER")" = "com.yinxing.launcher" ]; then
                observed=1
                break
            fi
            /bin/sleep 0.05
        done
        assert_equals "1" "$observed" "Guard did not complete initial HOME takeover ($marker)"
        touch "$YINXING_GUARD_TEST_MODULE_DIR/$marker"
        printf 'com.example.caregiverlauncher\n' > "$HOME_HOLDER"
        : > "$CALLS"
        wait "$GUARD_PID"
        GUARD_PID=""
        assert_equals "com.example.caregiverlauncher" "$(tr -d '\n' < "$HOME_HOLDER")" \
            "inactive Guard reclaimed caregiver HOME ($marker)"
        assert_not_contains "$CALLS" "cmd package set-home-activity"
    done
    pass "Guard stops HOME enforcement after disable or remove"
}

test_action_rejects_disabled_or_removing_module() {
    local marker

    for marker in disable remove; do
        reset_fixture
        mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
        touch "$YINXING_GUARD_TEST_MODULE_DIR/$marker"
        if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
            run_module_script "$MODULE_ROOT/action.sh"; then
            fail "action accepted inactive module ($marker)"
        fi
        assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
            "inactive action changed HOME ($marker)"
        assert_not_contains "$CALLS" "cmd package set-home-activity"
        assert_not_contains "$CALLS" "am start"
    done
    pass "action rejects disabled or removing module"
}

test_action_rolls_back_home_when_module_deactivates_during_set() {
    local marker

    for marker in disable remove; do
        reset_fixture
        mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
        printf '%s\n' "$marker" > "$TEST_ROOT/deactivate_during_home_role_set"
        if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
            run_module_script "$MODULE_ROOT/action.sh"; then
            fail "action succeeded after module deactivated during HOME set ($marker)"
        fi
        assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
            "mid-set deactivation restores prior HOME ($marker)"
        assert_equals "2" \
            "$(grep -c '^cmd package set-home-activity --user 0 ' "$CALLS" || true)" \
            "mid-set deactivation takeover/rollback count ($marker)"
        assert_contains "$CALLS" \
            "cmd package set-home-activity --user 0 com.oplus.launcher"
        assert_equals "released" \
            "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state")" \
            "successful mid-set rollback releases ownership ($marker)"
        assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
        assert_not_contains "$CALLS" "cmd appops set"
        assert_not_contains "$CALLS" "am start"
    done
    pass "action rolls back HOME after mid-set module deactivation"
}

test_action_rolls_back_latest_home_when_marker_predates_takeover() {
    reset_fixture
    mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR" "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'com.example.caregiverlauncher\n' > "$HOME_HOLDER"
    printf 'disable\n' > "$TEST_ROOT/deactivate_during_home_role_set"

    if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
        run_module_script "$MODULE_ROOT/action.sh"; then
        fail "action succeeded after repeated takeover deactivated module"
    fi

    assert_equals "com.example.caregiverlauncher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "mid-set deactivation restores the latest caregiver HOME"
    assert_contains "$CALLS" \
        "cmd package set-home-activity --user 0 com.example.caregiverlauncher"
    assert_not_contains "$CALLS" \
        "cmd package set-home-activity --user 0 com.oplus.launcher"
    assert_equals "released" "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state")" \
        "successful latest-HOME rollback releases ownership"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    assert_not_contains "$CALLS" "cmd appops set"
    assert_not_contains "$CALLS" "am start"
    pass "action rolls back the latest HOME after repeated takeover interruption"
}

test_action_persists_latest_home_when_inactive_rollback_fails() {
    reset_fixture
    mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR" "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'com.example.caregiverlauncher\n' > "$HOME_HOLDER"
    printf 'disable\n' > "$TEST_ROOT/deactivate_during_home_role_set"
    touch "$TEST_ROOT/fail_home_role_restore"

    if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
        run_module_script "$MODULE_ROOT/action.sh"; then
        fail "action succeeded after inactive HOME rollback failed"
    fi
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "failed inactive rollback leaves observable HOME for retry"
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "failed inactive rollback preserves original HOME target"
    assert_equals "com.example.caregiverlauncher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state" | sed 's/^pending|[^|]*|//')" \
        "failed inactive rollback persists latest pending HOME target"

    rm -f "$TEST_ROOT/fail_home_role_restore"
    touch "$YINXING_GUARD_TEST_MODULE_DIR/remove"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    if run_module_script "$CLEANUP_TARGET"; then
        fail "same-boot pending HOME evidence was released too early"
    fi
    assert_equals "com.example.caregiverlauncher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "same-boot cleanup compensates the interrupted HOME takeover"
    [[ -f "$TEST_ROOT/state/home_previous_holder" ]] || \
        fail "same-boot compensation lost original HOME evidence"
    [[ -f "$TEST_ROOT/state/home_takeover_state" ]] || \
        fail "same-boot compensation lost pending HOME evidence"
    [[ -x "$CLEANUP_TARGET" ]] || fail "same-boot compensation lost cleanup helper"

    printf 'next-boot\n' > "$TEST_ROOT/boot_id"
    run_module_script "$CLEANUP_TARGET"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || \
        fail "cleanup retained recovered latest HOME marker"
    [[ ! -e "$TEST_ROOT/state/home_takeover_state" ]] || \
        fail "cleanup retained recovered HOME takeover state"
    [[ ! -e "$CLEANUP_TARGET" ]] || fail "cleanup retained itself after latest HOME recovery"
    pass "inactive HOME rollback failure remains recoverable"
}

test_uninstall_recovers_latest_home_after_late_set_completion() {
    reset_fixture
    mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR" "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'com.example.caregiverlauncher\n' > "$HOME_HOLDER"
    printf 'disable\n' > "$TEST_ROOT/deactivate_during_home_role_set"
    touch "$TEST_ROOT/late_home_role_set"

    if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
        YINXING_GUARD_COMMAND_TIMEOUT_SECONDS=1 \
        run_module_script "$MODULE_ROOT/action.sh"; then
        fail "action succeeded after timed-out HOME takeover"
    fi
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "timed-out takeover preserves original HOME evidence"
    assert_equals "com.example.caregiverlauncher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state" | sed 's/^pending|[^|]*|//')" \
        "timed-out takeover retains latest pending HOME evidence"

    printf 'next-boot\n' > "$TEST_ROOT/boot_id"
    touch "$YINXING_GUARD_TEST_MODULE_DIR/remove"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    run_module_script "$CLEANUP_TARGET"
    assert_equals "com.example.caregiverlauncher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "cleanup repairs a late HOME takeover to latest holder"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || \
        fail "late HOME cleanup retained marker"
    [[ ! -e "$TEST_ROOT/state/home_takeover_state" ]] || \
        fail "late HOME cleanup retained takeover state"
    [[ ! -e "$CLEANUP_TARGET" ]] || fail "late HOME cleanup retained itself"
    pass "late HOME takeover remains recoverable after client timeout"
}

test_action_removes_home_after_mid_set_deactivation_when_prior_was_none() {
    reset_fixture
    mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
    : > "$HOME_HOLDER"
    printf 'disable\n' > "$TEST_ROOT/deactivate_during_home_role_set"
    if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
        run_module_script "$MODULE_ROOT/action.sh"; then
        fail "action succeeded after no-holder HOME set deactivated module"
    fi
    assert_equals "" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "mid-set deactivation restores no-holder HOME"
    assert_contains "$CALLS" \
        "cmd role remove-role-holder --user 0 android.app.role.HOME com.yinxing.launcher"
    assert_equals "released" "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state")" \
        "successful no-holder rollback releases ownership"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    assert_not_contains "$CALLS" "cmd appops set"
    assert_not_contains "$CALLS" "am start"
    pass "action restores no-holder HOME after mid-set deactivation"
}

test_repeated_home_takeover_never_clobbers_original_holder() {
    reset_fixture
    mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
    repair_state || fail "initial HOME takeover should succeed"
    printf 'com.example.caregiverlauncher\n' > "$HOME_HOLDER"
    repair_state || fail "repeated HOME takeover should succeed"
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "repeated HOME takeover"
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "repeated takeover preserves immutable original HOME"
    assert_equals "owned" "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state")" \
        "confirmed repeated takeover owns HOME"

    touch "$YINXING_GUARD_TEST_MODULE_DIR/remove"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    run_module_script "$CLEANUP_TARGET"
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "uninstall restores immutable original HOME"
    pass "repeated HOME takeover never clobbers original holder"
}

test_manual_yinxing_choice_after_inactive_rollback_is_preserved() {
    reset_fixture
    mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
    printf 'disable\n' > "$TEST_ROOT/deactivate_during_home_role_set"
    if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
        run_module_script "$MODULE_ROOT/action.sh"; then
        fail "interrupted HOME takeover unexpectedly succeeded"
    fi
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "inactive rollback restores caregiver HOME"
    assert_equals "released" "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state")" \
        "inactive rollback records released ownership"

    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    touch "$YINXING_GUARD_TEST_MODULE_DIR/remove"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    [[ -x "$CLEANUP_TARGET" ]] || \
        fail "released HOME state did not retain cleanup helper"
    run_module_script "$CLEANUP_TARGET"
    [[ ! -e "$CLEANUP_TARGET" ]] || fail "released HOME cleanup retained helper"
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "manual Yinxing choice after inactive rollback"
    pass "manual Yinxing choice after inactive rollback is preserved"
}

test_home_transaction_lock_serializes_concurrent_actions() {
    local first_status second_status

    reset_fixture
    mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
    touch "$TEST_ROOT/pause_home_role_set"
    YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
        run_module_script "$MODULE_ROOT/action.sh" &
    GUARD_PID=$!
    for _ in $(seq 1 200); do
        [[ -e "$TEST_ROOT/home_role_set_entered" ]] && break
        /bin/sleep 0.01
    done
    [[ -e "$TEST_ROOT/home_role_set_entered" ]] || \
        fail "first HOME transaction did not reach the mutation boundary"

    set +e
    YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
        run_module_script "$MODULE_ROOT/action.sh"
    second_status=$?
    touch "$TEST_ROOT/allow_home_role_set"
    wait "$GUARD_PID"
    first_status=$?
    set -e
    GUARD_PID=""

    assert_equals "0" "$first_status" "first concurrent HOME action status"
    [[ "$second_status" -ne 0 ]] || fail "second concurrent HOME action acquired the writer lock"
    assert_equals "1" \
        "$(grep -c '^cmd package set-home-activity --user 0 com.yinxing.launcher/.feature.home.MainActivity$' "$CALLS" || true)" \
        "concurrent HOME takeover count"
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "concurrent actions preserve the immutable original HOME"
    assert_equals "owned" "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state")" \
        "concurrent HOME transaction state"
    [[ ! -e "$TEST_ROOT/state/home_transaction.lock" ]] || \
        fail "successful HOME action retained its transaction lock"
    pass "HOME transaction lock serializes concurrent actions"
}

test_uninstall_waits_for_unpublished_home_transaction() {
    local action_status uninstall_status cleanup_status

    reset_fixture
    touch "$TEST_ROOT/pause_home_marker_publish"
    (set +e; repair_state) &
    GUARD_PID=$!
    for _ in $(seq 1 200); do
        [[ -e "$TEST_ROOT/home_marker_publish_entered" ]] && break
        /bin/sleep 0.01
    done
    [[ -e "$TEST_ROOT/home_marker_publish_entered" ]] || \
        fail "HOME repair did not reach the unpublished transaction boundary"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || \
        fail "paused HOME transaction published ownership evidence too early"

    set +e
    run_module_script "$MODULE_ROOT/uninstall.sh"
    uninstall_status=$?
    run_module_script "$CLEANUP_TARGET"
    cleanup_status=$?
    touch "$TEST_ROOT/allow_home_marker_publish"
    wait "$GUARD_PID"
    action_status=$?
    set -e
    GUARD_PID=""

    [[ "$uninstall_status" -ne 0 ]] || \
        fail "uninstall entered an unpublished HOME transaction"
    [[ "$cleanup_status" -ne 0 ]] || \
        fail "cleanup entered an unpublished HOME transaction"
    assert_equals "0" "$action_status" "unpublished HOME action status"
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "HOME takeover after serialized uninstall"
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "serialized HOME original holder"
    assert_equals "owned" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state")" \
        "serialized HOME ownership state"
    [[ -x "$CLEANUP_TARGET" ]] || \
        fail "blocked HOME cleanup removed its retry helper"

    run_module_script "$MODULE_ROOT/uninstall.sh"
    run_module_script "$CLEANUP_TARGET"
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "serialized uninstall restores original HOME"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || \
        fail "serialized HOME cleanup retained original-holder evidence"
    [[ ! -e "$TEST_ROOT/state/home_takeover_state" ]] || \
        fail "serialized HOME cleanup retained ownership state"
    pass "uninstall waits for unpublished HOME transaction"
}

test_home_transaction_lock_reclaims_dead_owner() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state/home_transaction.lock"
    printf '999999\n' > "$TEST_ROOT/state/home_transaction.lock/pid"
    printf 'fixture-boot\n' > "$TEST_ROOT/state/home_transaction.lock/boot_id"
    run_module_script "$MODULE_ROOT/action.sh" || fail "dead HOME lock should be reclaimed"
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "HOME takeover after dead lock reclaim"
    [[ ! -e "$TEST_ROOT/state/home_transaction.lock" ]] || \
        fail "dead HOME transaction lock survived repair"
    pass "HOME transaction lock reclaims a dead owner"
}

test_home_transaction_lock_rejects_symlink() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state" "$TEST_ROOT/external-home-lock"
    ln -s "$TEST_ROOT/external-home-lock" "$TEST_ROOT/state/home_transaction.lock"
    if run_module_script "$MODULE_ROOT/action.sh"; then
        fail "symlink HOME transaction lock unexpectedly allowed repair"
    fi
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "symlink HOME lock preserves current HOME"
    [[ -L "$TEST_ROOT/state/home_transaction.lock" ]] || \
        fail "symlink HOME transaction lock was modified"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    pass "HOME transaction lock rejects symlink state"
}

test_guard_promotes_visible_pending_home_state() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'pending|fixture-boot|com.example.caregiverlauncher\n' > \
        "$TEST_ROOT/state/home_takeover_state"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    repair_state || fail "visible pending HOME should be promoted"
    assert_equals "owned" "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state")" \
        "visible pending HOME promotion"
    assert_equals "com.oplus.launcher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "visible pending HOME preserves original holder"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    pass "Guard promotes visible pending HOME state"
}

test_guard_waits_for_same_boot_pending_home_absence() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'pending|fixture-boot|com.example.caregiverlauncher\n' > \
        "$TEST_ROOT/state/home_takeover_state"
    printf 'com.example.caregiverlauncher\n' > "$HOME_HOLDER"
    if repair_state; then
        fail "same-boot pending HOME absence unexpectedly retried"
    fi
    assert_equals "pending|fixture-boot|com.example.caregiverlauncher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state")" \
        "same-boot pending HOME state"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    pass "Guard waits for same-boot pending HOME uncertainty"
}

test_guard_rebaselines_cross_boot_pending_home() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'next-boot\n' > "$TEST_ROOT/boot_id"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'pending|previous-boot|com.example.caregiverlauncher\n' > \
        "$TEST_ROOT/state/home_takeover_state"
    printf 'com.example.caregiverlauncher\n' > "$HOME_HOLDER"
    repair_state || fail "cross-boot pending HOME should rebaseline and repair"
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "cross-boot pending HOME takeover"
    assert_equals "com.example.caregiverlauncher" \
        "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "cross-boot pending HOME rebaseline"
    assert_equals "owned" "$(tr -d '\n' < "$TEST_ROOT/state/home_takeover_state")" \
        "cross-boot pending HOME ownership"
    pass "Guard rebaselines cross-boot pending HOME"
}

test_action_stops_after_module_deactivates_during_doze_add() {
    local marker

    for marker in disable remove; do
        reset_fixture
        mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
        printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
        printf '%s\n' "$marker" > "$TEST_ROOT/deactivate_during_doze_add"
        if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
            run_module_script "$MODULE_ROOT/action.sh"; then
            fail "action succeeded after module deactivated during Doze add ($marker)"
        fi
        [[ -e "$TEST_ROOT/doze_whitelisted" ]] || fail "mid-add Doze state was lost ($marker)"
        [[ -f "$TEST_ROOT/state/doze_added_by_module" ]] || \
            fail "mid-add deactivation lost Doze ownership marker ($marker)"
        assert_not_contains "$CALLS" "cmd appops set"
        assert_not_contains "$CALLS" "am start"
    done
    pass "action stops after mid-Doze module deactivation"
}

test_action_stops_after_module_deactivates_during_first_appop() {
    local marker

    for marker in disable remove; do
        reset_fixture
        mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
        printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
        touch "$TEST_ROOT/doze_whitelisted"
        printf '%s\n' "$marker" > "$TEST_ROOT/deactivate_during_first_appops"
        if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
            run_module_script "$MODULE_ROOT/action.sh"; then
            fail "action succeeded after module deactivated during AppOps ($marker)"
        fi
        assert_contains "$CALLS" \
            "cmd appops set --user 0 com.yinxing.launcher RUN_IN_BACKGROUND allow"
        assert_not_contains "$CALLS" "RUN_ANY_IN_BACKGROUND"
        assert_not_contains "$CALLS" "am start"
    done
    pass "action stops after first AppOps deactivates module"
}

test_action_stops_after_module_deactivates_during_package_probe() {
    reset_fixture
    mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
    printf 'disable\n' > "$TEST_ROOT/deactivate_during_package_path"
    if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
        run_module_script "$MODULE_ROOT/action.sh"; then
        fail "action succeeded after module deactivated during package probe"
    fi
    assert_not_contains "$CALLS" "pm --user 0 enable"
    assert_not_contains "$CALLS" "settings --user 0 put secure"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    assert_not_contains "$CALLS" "cmd appops set"
    assert_not_contains "$CALLS" "am start"
    pass "action stops after package probe deactivates module"
}

test_action_stops_after_module_deactivates_during_accessibility_read() {
    reset_fixture
    mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
    printf 'disable\n' > "$TEST_ROOT/deactivate_during_accessibility_read"
    if YINXING_GUARD_MODULE_STATE_DIR="$YINXING_GUARD_TEST_MODULE_DIR" \
        run_module_script "$MODULE_ROOT/action.sh"; then
        fail "action succeeded after module deactivated during accessibility read"
    fi
    assert_not_contains "$CALLS" "settings --user 0 put secure"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist +com.yinxing.launcher"
    assert_not_contains "$CALLS" "cmd appops set"
    assert_not_contains "$CALLS" "am start"
    pass "action stops after accessibility read deactivates module"
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
    local first_status second_status
    set +e
    wait "$GUARD_PID"
    first_status=$?
    wait "$SECOND_GUARD_PID"
    second_status=$?
    set -e
    if ! { [ "$first_status" -eq 0 ] && [ "$second_status" -eq 76 ]; } && \
        ! { [ "$first_status" -eq 76 ] && [ "$second_status" -eq 0 ]; }; then
        fail "concurrent guards returned unexpected statuses ($first_status/$second_status)"
    fi
    GUARD_PID=""
    SECOND_GUARD_PID=""
    assert_equals "1" "$(grep -c '^am start ' "$CALLS" || true)" "concurrent guards both performed health cycles"
    pass "guard prevents concurrent processes"
}

test_action_reuses_repair_and_launch() {
    reset_fixture
    rm -f "$CLEANUP_TARGET"
    run_module_script "$MODULE_ROOT/action.sh"
    assert_equals "$ACCESSIBILITY_COMPONENT" "$(tr -d '\n' < "$SERVICES")" "action repairs accessibility"
    assert_equals "ok" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" "action records successful repair"
    assert_equals "1" "$(grep -c '^am start ' "$CALLS")" "action launches HOME once"
    [[ -x "$CLEANUP_TARGET" ]] || fail "action did not install deferred cleanup helper"
    [[ -e "$TEST_ROOT/doze_whitelisted" ]] || fail "action did not add Doze whitelist"
    [[ -f "$TEST_ROOT/state/doze_added_by_module" ]] || fail "action did not record Doze ownership"
    pass "action reuses repair and launch"
}

test_action_bounds_stalled_package_query() {
    local started_at elapsed

    reset_fixture
    touch "$TEST_ROOT/hang_pm_path"
    started_at=$SECONDS
    if YINXING_GUARD_COMMAND_TIMEOUT_SECONDS=1 \
        run_module_script "$MODULE_ROOT/action.sh"; then
        fail "stalled package query unexpectedly reported recovery success"
    fi
    elapsed=$((SECONDS - started_at))
    [[ "$elapsed" -lt 4 ]] || fail "stalled package query exceeded bound (${elapsed}s)"
    assert_equals "failed" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" \
        "stalled package query should record failed repair"
    assert_not_contains "$CALLS" "settings --user 0 put secure"
    assert_not_contains "$CALLS" "am start"
    pass "action bounds stalled package query"
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
    rm -f "$CLEANUP_TARGET"
    mkdir -p "$CLEANUP_TARGET"
    if install_cleanup_helper "$MODULE_ROOT/bin/uninstall-cleanup.sh"; then
        fail "cleanup helper accepted a directory target"
    fi
    if repair_state; then
        fail "repair unexpectedly succeeded without rollback cleanup readiness"
    fi
    assert_equals "$ACCESSIBILITY_COMPONENT" "$(tr -d '\n' < "$SERVICES")" \
        "accessibility repair survives a bad helper target"
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "bad helper target blocks HOME takeover"
    [[ ! -e "$TEST_ROOT/doze_whitelisted" ]] || fail "bad helper target allowed an unowned Doze add"
    [[ ! -e "$TEST_ROOT/state/doze_added_by_module" ]] || fail "bad helper target created ownership marker"
    pass "cleanup directory target is rejected"
}

test_uninstall_recovers_global_only_accessibility_transaction() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf '%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '1\n' > "$ACCESSIBILITY_ENABLED"
    printf 'pending|0|1|%s|%s|\n' \
        "$ACCESSIBILITY_COMPONENT" "$ACCESSIBILITY_COMPONENT" > \
        "$TEST_ROOT/state/accessibility_transaction"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    run_module_script "$CLEANUP_TARGET"
    assert_equals "$ACCESSIBILITY_COMPONENT" "$(tr -d '\n' < "$SERVICES")" \
        "global-only accessibility recovery preserves services"
    assert_equals "0" "$(tr -d '\n' < "$ACCESSIBILITY_ENABLED")" \
        "global-only accessibility recovery restores switch"
    assert_not_contains "$CALLS" \
        "settings --user 0 put secure enabled_accessibility_services"
    [[ ! -e "$TEST_ROOT/state/accessibility_transaction" ]] || \
        fail "global-only accessibility recovery retained evidence"
    [[ ! -e "$CLEANUP_TARGET" ]] || \
        fail "global-only accessibility recovery retained helper"
    pass "uninstall recovers global-only accessibility transaction"
}

test_uninstall_retains_malformed_accessibility_transaction() {
    local journal marker="$TEST_ROOT/state/accessibility_transaction"

    for journal in \
        'pending|0|1|original|primary|alternate|extra' \
        "pending|0|0|talkback:other|talkback:other:$ACCESSIBILITY_COMPONENT|talkback:other" \
        'pending|0|1|talkback:other|caregiver.reader/service|talkback:other' \
        "pending|0|1|talkback:other|talkback:other:$ACCESSIBILITY_COMPONENT|caregiver.reader/service" \
        "pending|0|1|null|$ACCESSIBILITY_COMPONENT|" \
        "pending|0|1|NULL|$ACCESSIBILITY_COMPONENT|" \
        "pending|0|1|   |$ACCESSIBILITY_COMPONENT|" \
        "pending|0|1|null:$ACCESSIBILITY_COMPONENT|null:$ACCESSIBILITY_COMPONENT|null" \
        "pending|0|1|NULL:$ACCESSIBILITY_COMPONENT|NULL:$ACCESSIBILITY_COMPONENT|NULL"; do
        reset_fixture
        mkdir -p "$TEST_ROOT/state"
        printf '%s\n' "$journal" > "$marker"
        run_module_script "$MODULE_ROOT/uninstall.sh"
        if run_module_script "$CLEANUP_TARGET"; then
            fail "malformed accessibility transaction unexpectedly cleaned"
        fi
        [[ -f "$marker" ]] || \
            fail "malformed accessibility transaction lost evidence"
        [[ -x "$CLEANUP_TARGET" ]] || \
            fail "malformed accessibility transaction lost helper"
        assert_not_contains "$CALLS" "settings --user 0 put secure"
    done
    pass "uninstall retains malformed accessibility transaction"
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

test_uninstall_cleanup_bounds_stalled_doze_remove() {
    local started_at elapsed

    reset_fixture
    mkdir -p "$TEST_ROOT/state" "$TEST_ROOT/modules/yinxing_guard"
    printf 'added\n' > "$TEST_ROOT/state/doze_added_by_module"
    touch \
        "$TEST_ROOT/doze_whitelisted" \
        "$TEST_ROOT/modules/yinxing_guard/remove" \
        "$TEST_ROOT/hang_deviceidle_remove"
    install_cleanup_helper "$MODULE_ROOT/bin/uninstall-cleanup.sh" || \
        fail "could not install stalled cleanup helper"
    started_at=$SECONDS
    if YINXING_GUARD_COMMAND_TIMEOUT_SECONDS=1 run_module_script "$CLEANUP_TARGET"; then
        fail "stalled Doze cleanup unexpectedly succeeded"
    fi
    elapsed=$((SECONDS - started_at))
    [[ "$elapsed" -lt 4 ]] || fail "stalled Doze cleanup exceeded bound (${elapsed}s)"
    [[ -f "$TEST_ROOT/state/doze_added_by_module" ]] || fail "stalled Doze cleanup lost ownership marker"
    [[ -x "$CLEANUP_TARGET" ]] || fail "stalled Doze cleanup removed its retry script"
    pass "uninstall cleanup bounds stalled Doze remove"
}

test_uninstall_resolves_pending_doze_state() {
    local state marker_boot cleanup_boot_file

    for state in absent present; do
        reset_fixture
        mkdir -p "$TEST_ROOT/state"
        cleanup_boot_file="$TEST_ROOT/cleanup_boot_id"
        printf 'current-boot\n' > "$cleanup_boot_file"
        if [[ "$state" == "present" ]]; then
            marker_boot=current-boot
        else
            marker_boot=previous-boot
        fi
        printf 'pending|%s\n' "$marker_boot" > "$TEST_ROOT/state/doze_added_by_module"
        if [[ "$state" == "present" ]]; then
            touch "$TEST_ROOT/doze_whitelisted"
        fi
        run_module_script "$MODULE_ROOT/uninstall.sh"
        YINXING_GUARD_BOOT_ID_FILE="$cleanup_boot_file" run_module_script "$CLEANUP_TARGET"
        [[ ! -e "$TEST_ROOT/state/doze_added_by_module" ]] || \
            fail "resolved pending Doze marker was retained ($state)"
        [[ ! -e "$TEST_ROOT/doze_whitelisted" ]] || \
            fail "resolved pending Doze whitelist was retained ($state)"
        if [[ "$state" == "present" ]]; then
            assert_contains "$CALLS" "cmd deviceidle whitelist -com.yinxing.launcher"
        else
            assert_not_contains "$CALLS" "cmd deviceidle whitelist -com.yinxing.launcher"
        fi
        [[ ! -e "$CLEANUP_TARGET" ]] || fail "resolved pending Doze cleanup retained helper ($state)"
    done
    pass "uninstall resolves pending Doze state"
}

test_uninstall_retains_same_boot_pending_doze_absence() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'same-boot\n' > "$TEST_ROOT/cleanup_boot_id"
    printf 'pending|same-boot\n' > "$TEST_ROOT/state/doze_added_by_module"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    if YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/cleanup_boot_id" \
        run_module_script "$CLEANUP_TARGET"; then
        fail "same-boot pending Doze absence was released before late mutation became impossible"
    fi
    [[ -f "$TEST_ROOT/state/doze_added_by_module" ]] || \
        fail "same-boot pending Doze marker was lost"
    [[ -x "$CLEANUP_TARGET" ]] || fail "same-boot pending Doze helper was lost"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist -com.yinxing.launcher"
    pass "uninstall retains same-boot pending Doze absence"
}

test_uninstall_accepts_nonzero_after_applied_doze_remove() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'added\n' > "$TEST_ROOT/state/doze_added_by_module"
    touch "$TEST_ROOT/doze_whitelisted" "$TEST_ROOT/fail_deviceidle_remove_after_apply"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    run_module_script "$CLEANUP_TARGET"
    [[ ! -e "$TEST_ROOT/doze_whitelisted" ]] || \
        fail "applied-error Doze removal retained whitelist entry"
    [[ ! -e "$TEST_ROOT/state/doze_added_by_module" ]] || \
        fail "applied-error Doze removal retained marker"
    [[ ! -e "$CLEANUP_TARGET" ]] || \
        fail "applied-error Doze removal retained helper"
    pass "uninstall accepts nonzero after confirmed Doze removal"
}

test_uninstall_retries_unconfirmed_doze_remove() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'added\n' > "$TEST_ROOT/state/doze_added_by_module"
    touch "$TEST_ROOT/doze_whitelisted" "$TEST_ROOT/ignore_deviceidle_remove"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    if run_module_script "$CLEANUP_TARGET"; then
        fail "unconfirmed Doze removal unexpectedly succeeded"
    fi
    [[ -e "$TEST_ROOT/doze_whitelisted" ]] || \
        fail "unconfirmed Doze fixture lost whitelist entry"
    [[ -f "$TEST_ROOT/state/doze_added_by_module" ]] || \
        fail "unconfirmed Doze removal lost ownership marker"
    [[ -x "$CLEANUP_TARGET" ]] || fail "unconfirmed Doze removal lost helper"
    pass "uninstall retries unconfirmed Doze removal"
}

test_uninstall_clears_absent_owned_doze_state() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'added\n' > "$TEST_ROOT/state/doze_added_by_module"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    run_module_script "$CLEANUP_TARGET"
    assert_not_contains "$CALLS" "cmd deviceidle whitelist -com.yinxing.launcher"
    [[ ! -e "$TEST_ROOT/state/doze_added_by_module" ]] || \
        fail "absent owned Doze marker was retained"
    [[ ! -e "$CLEANUP_TARGET" ]] || fail "absent owned Doze cleanup retained helper"
    pass "uninstall clears absent owned Doze state"
}

test_uninstall_clears_unarmed_home_evidence_without_mutation() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    run_module_script "$CLEANUP_TARGET"
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "unarmed HOME evidence preserves manual Yinxing choice"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "cmd role remove-role-holder"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || \
        fail "unarmed original HOME evidence was retained"
    [[ ! -e "$TEST_ROOT/state/home_takeover_state" ]] || \
        fail "unarmed HOME cleanup retained phase state"
    pass "uninstall clears unarmed HOME evidence without mutation"
}

test_uninstall_rejects_owned_home_state_without_original() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    if run_module_script "$CLEANUP_TARGET"; then
        fail "HOME ownership without original evidence unexpectedly cleaned"
    fi
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "HOME state without original preserves current holder"
    [[ -f "$TEST_ROOT/state/home_takeover_state" ]] || \
        fail "HOME state without original was removed"
    [[ -x "$CLEANUP_TARGET" ]] || fail "HOME state without original lost helper"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "cmd role remove-role-holder"
    pass "uninstall rejects owned HOME state without original"
}

test_uninstall_retains_same_boot_pending_home_absence() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'pending|fixture-boot|com.example.caregiverlauncher\n' > \
        "$TEST_ROOT/state/home_takeover_state"
    printf 'com.example.caregiverlauncher\n' > "$HOME_HOLDER"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    if run_module_script "$CLEANUP_TARGET"; then
        fail "same-boot pending HOME absence was released too early"
    fi
    assert_equals "com.example.caregiverlauncher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "same-boot pending HOME preserves caregiver choice"
    [[ -f "$TEST_ROOT/state/home_takeover_state" ]] || \
        fail "same-boot pending HOME lost phase evidence"
    [[ -x "$CLEANUP_TARGET" ]] || fail "same-boot pending HOME lost helper"
    assert_not_contains "$CALLS" "cmd package set-home-activity"

    printf 'next-boot\n' > "$TEST_ROOT/boot_id"
    run_module_script "$CLEANUP_TARGET"
    assert_equals "com.example.caregiverlauncher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "cross-boot pending HOME preserves caregiver choice"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || \
        fail "cross-boot pending HOME retained original evidence"
    [[ ! -e "$TEST_ROOT/state/home_takeover_state" ]] || \
        fail "cross-boot pending HOME retained phase evidence"
    [[ ! -e "$CLEANUP_TARGET" ]] || fail "cross-boot pending HOME retained helper"
    pass "uninstall retains same-boot pending HOME absence"
}

test_uninstall_waits_for_live_home_transaction() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state/home_transaction.lock"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    /bin/sleep 30 &
    LIVE_PID=$!
    printf '%s\n' "$LIVE_PID" > "$TEST_ROOT/state/home_transaction.lock/pid"
    printf 'fixture-boot\n' > "$TEST_ROOT/state/home_transaction.lock/boot_id"
    if run_module_script "$MODULE_ROOT/uninstall.sh"; then
        fail "uninstall entered a live HOME transaction"
    fi
    if run_module_script "$CLEANUP_TARGET"; then
        fail "uninstall cleanup entered a live HOME transaction"
    fi
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "live HOME transaction blocks cleanup mutation"
    [[ -f "$TEST_ROOT/state/home_takeover_state" ]] || \
        fail "live HOME transaction lost phase evidence"
    [[ -x "$CLEANUP_TARGET" ]] || fail "live HOME transaction lost cleanup helper"
    assert_not_contains "$CALLS" "cmd package set-home-activity --user 0 com.oplus.launcher"

    kill "$LIVE_PID" 2>/dev/null || true
    wait "$LIVE_PID" 2>/dev/null || true
    LIVE_PID=""
    run_module_script "$CLEANUP_TARGET"
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "HOME cleanup after lock owner exits"
    [[ ! -e "$CLEANUP_TARGET" ]] || fail "reclaimed HOME transaction retained helper"
    pass "uninstall waits for a live HOME transaction"
}

test_uninstall_restores_previous_home_holder() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'stale\n' > "$TEST_ROOT/state/home_previous_holder.tmp.999"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    [[ -x "$CLEANUP_TARGET" ]] || fail "HOME rollback helper was not scheduled"
    [[ -f "$TEST_ROOT/state/home_previous_holder" ]] || fail "uninstall removed HOME marker early"
    run_module_script "$CLEANUP_TARGET"
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "uninstall restores previous HOME"
    assert_equals "1" \
        "$(grep -c '^cmd package set-home-activity --user 0 com.oplus.launcher$' "$CALLS")" \
        "previous HOME restore count"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || fail "successful HOME restore retained marker"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder.tmp.999" ]] || \
        fail "successful HOME restore retained temp marker"
    [[ ! -e "$CLEANUP_TARGET" ]] || fail "successful HOME restore retained helper"
    pass "uninstall restores previous HOME holder"
}

test_uninstall_removes_owned_home_when_previous_was_none() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'none\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    [[ -x "$CLEANUP_TARGET" ]] || fail "empty HOME rollback helper was not scheduled"
    run_module_script "$CLEANUP_TARGET"
    assert_equals "" "$(tr -d '\n' < "$HOME_HOLDER")" "uninstall removes module-owned HOME"
    assert_equals "1" \
        "$(grep -c '^cmd role remove-role-holder --user 0 android.app.role.HOME com.yinxing.launcher$' "$CALLS")" \
        "owned HOME removal count"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || fail "HOME removal retained marker"
    [[ ! -e "$CLEANUP_TARGET" ]] || fail "HOME removal retained helper"
    pass "uninstall removes owned HOME when no holder existed"
}

test_uninstall_preserves_newer_home_choice() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'com.example.caregiverlauncher\n' > "$HOME_HOLDER"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    [[ -x "$CLEANUP_TARGET" ]] || fail "new HOME choice cleanup helper was not scheduled"
    run_module_script "$CLEANUP_TARGET"
    assert_equals "com.example.caregiverlauncher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "uninstall preserves newer HOME choice"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "cmd role remove-role-holder"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || fail "new HOME choice retained stale marker"
    [[ ! -e "$CLEANUP_TARGET" ]] || fail "new HOME choice retained helper"
    pass "uninstall preserves newer HOME choice"
}

test_uninstall_does_not_remove_preexisting_yinxing_home() {
    reset_fixture
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    install_cleanup_helper "$MODULE_ROOT/bin/uninstall-cleanup.sh" || \
        fail "could not install preexisting HOME helper fixture"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "uninstall preserves manually selected Yinxing HOME"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "cmd role remove-role-holder"
    [[ ! -e "$CLEANUP_TARGET" ]] || fail "unowned HOME retained cleanup helper"
    pass "uninstall does not remove preexisting Yinxing HOME"
}

test_uninstall_retains_home_marker_when_previous_package_is_missing() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    touch "$TEST_ROOT/previous_home_missing"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    if run_module_script "$CLEANUP_TARGET"; then
        fail "missing previous HOME unexpectedly restored"
    fi
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "missing previous HOME preserves current holder"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    [[ -f "$TEST_ROOT/state/home_previous_holder" ]] || fail "missing previous HOME lost marker"
    [[ -x "$CLEANUP_TARGET" ]] || fail "missing previous HOME lost retry helper"
    pass "uninstall retains HOME marker when previous package is missing"
}

test_uninstall_retains_home_marker_when_restore_fails() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    touch "$TEST_ROOT/fail_home_role_set"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    if run_module_script "$CLEANUP_TARGET"; then
        fail "failed previous HOME restore unexpectedly succeeded"
    fi
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "failed restore preserves current HOME"
    [[ -f "$TEST_ROOT/state/home_previous_holder" ]] || fail "failed restore lost HOME marker"
    [[ -x "$CLEANUP_TARGET" ]] || fail "failed restore lost retry helper"
    pass "uninstall retains HOME marker when restore fails"
}

test_uninstall_retains_invalid_home_marker() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'bad holder\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    if run_module_script "$CLEANUP_TARGET"; then
        fail "invalid HOME marker cleanup unexpectedly succeeded"
    fi
    assert_equals "bad holder" "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" \
        "invalid HOME marker is retained"
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "invalid HOME marker preserves current holder"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    assert_not_contains "$CALLS" "cmd role remove-role-holder"
    [[ -x "$CLEANUP_TARGET" ]] || fail "invalid HOME marker lost retry helper"
    pass "uninstall retains invalid HOME marker"
}

test_uninstall_bounds_stalled_home_restore() {
    local started_at elapsed

    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    touch "$TEST_ROOT/hang_home_role_set"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    started_at=$SECONDS
    if YINXING_GUARD_COMMAND_TIMEOUT_SECONDS=1 run_module_script "$CLEANUP_TARGET"; then
        fail "stalled HOME restore unexpectedly succeeded"
    fi
    elapsed=$((SECONDS - started_at))
    [[ "$elapsed" -lt 4 ]] || fail "stalled HOME restore exceeded bound (${elapsed}s)"
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "stalled HOME restore preserves current holder"
    [[ -f "$TEST_ROOT/state/home_previous_holder" ]] || fail "stalled HOME restore lost marker"
    [[ -x "$CLEANUP_TARGET" ]] || fail "stalled HOME restore lost retry helper"
    pass "uninstall bounds stalled HOME restore"
}

test_uninstall_completes_home_when_doze_cleanup_needs_retry() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'added\n' > "$TEST_ROOT/state/doze_added_by_module"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    touch "$TEST_ROOT/doze_whitelisted" "$TEST_ROOT/fail_deviceidle_remove"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    if run_module_script "$CLEANUP_TARGET"; then
        fail "partial HOME/Doze cleanup unexpectedly succeeded"
    fi
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "HOME restore completes independently"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || fail "completed HOME restore retained marker"
    [[ -f "$TEST_ROOT/state/doze_added_by_module" ]] || fail "failed Doze cleanup lost marker"
    [[ -x "$CLEANUP_TARGET" ]] || fail "partial cleanup lost retry helper"
    rm -f "$TEST_ROOT/fail_deviceidle_remove"
    run_module_script "$CLEANUP_TARGET"
    [[ ! -e "$TEST_ROOT/state/doze_added_by_module" ]] || fail "Doze retry retained marker"
    [[ ! -e "$CLEANUP_TARGET" ]] || fail "completed cleanup retained helper"
    pass "uninstall completes HOME while Doze cleanup retries"
}

test_uninstall_retains_nonregular_accessibility_transactions() {
    local shape marker="$TEST_ROOT/state/accessibility_transaction"

    for shape in directory symlink dangling; do
        reset_fixture
        mkdir -p "$TEST_ROOT/state"
        case "$shape" in
            directory)
                mkdir "$marker"
                ;;
            symlink)
                printf 'pending|0|1||%s|\n' "$ACCESSIBILITY_COMPONENT" > \
                    "$TEST_ROOT/external-accessibility-transaction"
                ln -s "$TEST_ROOT/external-accessibility-transaction" "$marker"
                ;;
            dangling)
                ln -s "$TEST_ROOT/missing-accessibility-transaction" "$marker"
                ;;
        esac
        run_module_script "$MODULE_ROOT/uninstall.sh"
        [[ -x "$CLEANUP_TARGET" ]] || \
            fail "nonregular accessibility transaction lost helper ($shape)"
        if run_module_script "$CLEANUP_TARGET"; then
            fail "nonregular accessibility transaction unexpectedly cleaned ($shape)"
        fi
        if [[ "$shape" == "directory" ]]; then
            [[ -d "$marker" ]] || \
                fail "accessibility transaction directory was removed"
        else
            [[ -L "$marker" ]] || \
                fail "accessibility transaction symlink was removed ($shape)"
        fi
        [[ -x "$CLEANUP_TARGET" ]] || \
            fail "nonregular accessibility transaction removed helper ($shape)"
        assert_not_contains "$CALLS" "settings --user 0 put secure"
    done
    pass "uninstall retains nonregular accessibility transactions"
}

test_uninstall_retains_nonregular_home_markers() {
    local shape marker="$TEST_ROOT/state/home_previous_holder"

    for shape in directory symlink dangling; do
        reset_fixture
        mkdir -p "$TEST_ROOT/state"
        case "$shape" in
            directory)
                mkdir "$marker"
                ;;
            symlink)
                printf 'com.oplus.launcher\n' > "$TEST_ROOT/external-home-marker"
                ln -s "$TEST_ROOT/external-home-marker" "$marker"
                ;;
            dangling)
                ln -s "$TEST_ROOT/missing-home-marker" "$marker"
                ;;
        esac
        printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
        run_module_script "$MODULE_ROOT/uninstall.sh"
        [[ -x "$CLEANUP_TARGET" ]] || fail "nonregular HOME marker lost retry helper ($shape)"
        if run_module_script "$CLEANUP_TARGET"; then
            fail "nonregular HOME marker cleanup unexpectedly succeeded ($shape)"
        fi
        if [[ "$shape" == "directory" ]]; then
            [[ -d "$marker" ]] || fail "HOME marker directory was removed"
        else
            [[ -L "$marker" ]] || fail "HOME marker symlink was removed ($shape)"
        fi
        [[ -x "$CLEANUP_TARGET" ]] || fail "nonregular HOME marker removed retry helper ($shape)"
        assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
            "nonregular HOME marker preserves holder ($shape)"
        assert_not_contains "$CALLS" "cmd package set-home-activity"
        assert_not_contains "$CALLS" "cmd role remove-role-holder"
    done
    pass "uninstall retains nonregular HOME markers"
}

test_uninstall_retains_nonregular_doze_markers() {
    local shape marker="$TEST_ROOT/state/doze_added_by_module"

    for shape in directory symlink dangling; do
        reset_fixture
        mkdir -p "$TEST_ROOT/state"
        case "$shape" in
            directory)
                mkdir "$marker"
                ;;
            symlink)
                printf 'added\n' > "$TEST_ROOT/external-doze-marker"
                ln -s "$TEST_ROOT/external-doze-marker" "$marker"
                ;;
            dangling)
                ln -s "$TEST_ROOT/missing-doze-marker" "$marker"
                ;;
        esac
        touch "$TEST_ROOT/doze_whitelisted"
        run_module_script "$MODULE_ROOT/uninstall.sh"
        [[ -x "$CLEANUP_TARGET" ]] || fail "nonregular Doze marker lost retry helper ($shape)"
        if run_module_script "$CLEANUP_TARGET"; then
            fail "nonregular Doze marker cleanup unexpectedly succeeded ($shape)"
        fi
        if [[ "$shape" == "directory" ]]; then
            [[ -d "$marker" ]] || fail "Doze marker directory was removed"
        else
            [[ -L "$marker" ]] || fail "Doze marker symlink was removed ($shape)"
        fi
        [[ -x "$CLEANUP_TARGET" ]] || fail "nonregular Doze marker removed retry helper ($shape)"
        [[ -e "$TEST_ROOT/doze_whitelisted" ]] || fail "nonregular Doze marker changed whitelist ($shape)"
        assert_not_contains "$CALLS" "cmd deviceidle whitelist -com.yinxing.launcher"
    done
    pass "uninstall retains nonregular Doze markers"
}

test_uninstall_rejects_trailing_blank_home_marker() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    if run_module_script "$CLEANUP_TARGET"; then
        fail "trailing-blank HOME marker cleanup unexpectedly succeeded"
    fi
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "trailing-blank marker preserves current HOME"
    [[ -f "$TEST_ROOT/state/home_previous_holder" ]] || fail "trailing-blank HOME marker was removed"
    [[ -x "$CLEANUP_TARGET" ]] || fail "trailing-blank HOME marker lost retry helper"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    pass "uninstall rejects trailing-blank HOME marker"
}

test_uninstall_rejects_trailing_blank_home_query() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'com.yinxing.launcher\n\n' > "$TEST_ROOT/malformed_home_role_output"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    if run_module_script "$CLEANUP_TARGET"; then
        fail "trailing-blank HOME query cleanup unexpectedly succeeded"
    fi
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "trailing-blank query preserves current HOME"
    [[ -f "$TEST_ROOT/state/home_previous_holder" ]] || fail "trailing-blank query lost HOME marker"
    [[ -x "$CLEANUP_TARGET" ]] || fail "trailing-blank query lost retry helper"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    pass "uninstall rejects trailing-blank HOME query"
}

test_uninstall_rejects_invalid_android_home_markers() {
    local holder long_holder

    long_holder="com.$(printf '%220s' '' | tr ' ' a)"
    for holder in 1.2 _bad.home com.2launcher com.bad-name "$long_holder"; do
        reset_fixture
        mkdir -p "$TEST_ROOT/state"
        printf '%s\n' "$holder" > "$TEST_ROOT/state/home_previous_holder"
        printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
        run_module_script "$MODULE_ROOT/uninstall.sh"
        if run_module_script "$CLEANUP_TARGET"; then
            fail "invalid Android HOME marker cleanup unexpectedly succeeded ($holder)"
        fi
        assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
            "invalid uninstall HOME marker preserves holder ($holder)"
        [[ -f "$TEST_ROOT/state/home_previous_holder" ]] || \
            fail "invalid uninstall HOME marker was removed ($holder)"
        [[ -x "$CLEANUP_TARGET" ]] || fail "invalid uninstall HOME marker lost helper ($holder)"
        assert_not_contains "$CALLS" "cmd package set-home-activity"
    done
    pass "uninstall rejects invalid Android HOME markers"
}

test_uninstall_preserves_choice_made_during_previous_home_validation() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'com.oplus.launcher\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    touch "$TEST_ROOT/switch_home_during_previous_path"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    run_module_script "$CLEANUP_TARGET"
    assert_equals "com.example.caregiverlauncher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "caregiver HOME choice made during validation wins"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || fail "caregiver choice retained stale HOME marker"
    [[ ! -e "$CLEANUP_TARGET" ]] || fail "caregiver choice retained cleanup helper"
    pass "uninstall preserves HOME choice made during package validation"
}

test_uninstall_retries_failed_or_unconfirmed_home_removal() {
    local mode control

    for mode in failed unconfirmed; do
        reset_fixture
        mkdir -p "$TEST_ROOT/state"
        printf 'none\n' > "$TEST_ROOT/state/home_previous_holder"
        printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
        printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
        case "$mode" in
            failed) control="$TEST_ROOT/fail_home_role_remove" ;;
            unconfirmed) control="$TEST_ROOT/ignore_home_role_remove" ;;
        esac
        touch "$control"
        run_module_script "$MODULE_ROOT/uninstall.sh"
        if run_module_script "$CLEANUP_TARGET"; then
            fail "HOME removal unexpectedly succeeded ($mode)"
        fi
        assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
            "failed HOME removal preserves holder ($mode)"
        [[ -f "$TEST_ROOT/state/home_previous_holder" ]] || fail "failed HOME removal lost marker ($mode)"
        [[ -x "$CLEANUP_TARGET" ]] || fail "failed HOME removal lost retry helper ($mode)"
    done
    pass "uninstall retries failed or unconfirmed HOME removal"
}

test_uninstall_bounds_stalled_home_removal() {
    local started_at elapsed

    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'none\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    touch "$TEST_ROOT/hang_home_role_remove"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    started_at=$SECONDS
    if YINXING_GUARD_COMMAND_TIMEOUT_SECONDS=1 run_module_script "$CLEANUP_TARGET"; then
        fail "stalled HOME removal unexpectedly succeeded"
    fi
    elapsed=$((SECONDS - started_at))
    [[ "$elapsed" -lt 4 ]] || fail "stalled HOME removal exceeded bound (${elapsed}s)"
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" \
        "stalled HOME removal preserves holder"
    [[ -f "$TEST_ROOT/state/home_previous_holder" ]] || fail "stalled HOME removal lost marker"
    [[ -x "$CLEANUP_TARGET" ]] || fail "stalled HOME removal lost retry helper"
    pass "uninstall bounds stalled HOME removal"
}

test_uninstall_completes_doze_when_home_removal_needs_retry() {
    reset_fixture
    mkdir -p "$TEST_ROOT/state"
    printf 'none\n' > "$TEST_ROOT/state/home_previous_holder"
    printf 'owned\n' > "$TEST_ROOT/state/home_takeover_state"
    printf 'added\n' > "$TEST_ROOT/state/doze_added_by_module"
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    touch "$TEST_ROOT/doze_whitelisted" "$TEST_ROOT/fail_home_role_remove"
    run_module_script "$MODULE_ROOT/uninstall.sh"
    if run_module_script "$CLEANUP_TARGET"; then
        fail "partial HOME-removal/Doze cleanup unexpectedly succeeded"
    fi
    [[ ! -e "$TEST_ROOT/state/doze_added_by_module" ]] || fail "completed Doze cleanup retained marker"
    [[ ! -e "$TEST_ROOT/doze_whitelisted" ]] || fail "completed Doze cleanup retained whitelist"
    [[ -f "$TEST_ROOT/state/home_previous_holder" ]] || fail "failed HOME removal lost marker"
    [[ -x "$CLEANUP_TARGET" ]] || fail "partial cleanup lost retry helper"
    rm -f "$TEST_ROOT/fail_home_role_remove"
    run_module_script "$CLEANUP_TARGET"
    assert_equals "" "$(tr -d '\n' < "$HOME_HOLDER")" "HOME removal retry completes"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || fail "HOME retry retained marker"
    [[ ! -e "$CLEANUP_TARGET" ]] || fail "completed retry retained helper"
    pass "uninstall completes Doze while HOME removal retries"
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
    unzip -Z1 "$TEST_ROOT/module.zip" | grep -Fx 'bin/kiosk-home.sh' >/dev/null
    ! unzip -Z1 "$TEST_ROOT/module.zip" | grep -F 'yinxing_guard/' >/dev/null
    ! unzip -Z1 "$TEST_ROOT/module.zip" | grep -F '/tools/' >/dev/null
    assert_contains <(unzip -p "$TEST_ROOT/module.zip" module.prop) 'version=9.9.9-test'
    assert_contains <(unzip -p "$TEST_ROOT/module.zip" module.prop) 'versionCode=14'
    assert_contains <(unzip -p "$TEST_ROOT/module.zip" bin/common.sh) 'MODULE_VERSION="9.9.9-test"'
    assert_contains <(unzip -p "$TEST_ROOT/module.zip" bin/uninstall-cleanup.sh) 'MODULE_VERSION="9.9.9-test"'
    assert_contains "$MODULE_ROOT/module.prop" 'version=1.10.0-root-preview.14'
    assert_contains "$MODULE_ROOT/module.prop" 'versionCode=14'
    for executable in service.sh action.sh uninstall.sh bin/common.sh bin/guard.sh bin/status.sh bin/uninstall-cleanup.sh bin/kiosk-home.sh; do
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
        test_status_reports_stale_cleanup_helper_as_invalid
        test_status_reports_other_home_holder
        test_status_reports_no_home_holder
        test_status_reports_unknown_home_holder
        test_status_reports_disabled_package_as_disabled
        test_status_reports_disabled_component_as_disabled
        test_status_reports_unknown_when_package_state_query_fails
        test_status_reports_unknown_when_component_state_query_fails
        test_status_reports_stale_when_accessibility_service_crashed
        test_status_reports_stale_when_accessibility_service_confirmed_unbound
        test_status_output_contract_ignores_log_noise
        test_status_reports_stale_guard_as_degraded
        test_status_reports_stale_guard_when_pid_identity_mismatches
        test_status_reports_missing_module
        ;;
    --package-only)
        test_module_package
        ;;
    --home-lifecycle-only)
        test_action_rolls_back_home_when_module_deactivates_during_set
        test_action_rolls_back_latest_home_when_marker_predates_takeover
        test_action_persists_latest_home_when_inactive_rollback_fails
        test_uninstall_recovers_latest_home_after_late_set_completion
        test_action_removes_home_after_mid_set_deactivation_when_prior_was_none
        test_repeated_home_takeover_never_clobbers_original_holder
        test_manual_yinxing_choice_after_inactive_rollback_is_preserved
        ;;
    --review-regressions-only)
        test_accessibility_applied_write_errors_are_compensated
        test_accessibility_initial_writes_roll_back_after_module_deactivation
        test_accessibility_failed_compensation_is_recovered_on_uninstall
        test_repair_retains_noncanonical_accessibility_transaction
        test_rebind_preserves_caregiver_change_when_module_deactivates_after_remove
        test_rebind_preserves_caregiver_change_while_module_remains_active
        test_rebind_restores_original_enabled_state_after_interruption
        test_doze_same_boot_pending_absence_does_not_redispatch
        test_doze_visible_pending_state_promotes_to_owned
        test_doze_cross_boot_pending_absence_retries_once
        test_doze_transaction_blocks_cleanup_while_add_is_in_flight
        test_home_transaction_lock_serializes_concurrent_actions
        test_uninstall_waits_for_unpublished_home_transaction
        test_home_role_preserves_choice_after_takeover_state_publish
        test_home_transaction_lock_reclaims_dead_owner
        test_home_transaction_lock_rejects_symlink
        test_guard_promotes_visible_pending_home_state
        test_guard_waits_for_same_boot_pending_home_absence
        test_guard_rebaselines_cross_boot_pending_home
        test_uninstall_accepts_nonzero_after_applied_doze_remove
        test_uninstall_retries_unconfirmed_doze_remove
        test_uninstall_clears_absent_owned_doze_state
        test_uninstall_clears_unarmed_home_evidence_without_mutation
        test_uninstall_rejects_owned_home_state_without_original
        test_uninstall_retains_same_boot_pending_home_absence
        test_uninstall_waits_for_live_home_transaction
        test_uninstall_recovers_global_only_accessibility_transaction
        test_uninstall_retains_malformed_accessibility_transaction
        test_uninstall_retains_nonregular_accessibility_transactions
        ;;
    --guard-only)
        test_home_role_owned_is_idempotent
        test_home_role_reconciles_other_holder
        test_home_role_reconciles_no_holder
        test_home_role_query_failure_is_safe
        test_home_role_malformed_output_is_safe
        test_home_role_multiple_holders_are_safe
        test_home_role_rejects_invalid_android_package_names
        test_home_marker_rejects_invalid_android_package_names
        test_android_package_name_length_boundary
        test_home_role_invalid_marker_is_safe
        test_home_role_marker_write_failure_is_safe
        test_home_role_set_failure_retains_marker
        test_home_role_unconfirmed_set_retains_marker
        test_home_role_bounds_stalled_query
        test_home_role_bounds_stalled_set
        test_home_role_rejects_trailing_blank_query_output
        test_home_role_rejects_trailing_blank_marker
        test_home_marker_concurrent_publish_does_not_clobber
        test_home_marker_sync_failure_blocks_takeover
        test_home_role_preserves_choice_after_takeover_state_publish
        test_home_marker_sync_is_bounded
        test_home_marker_uses_default_busybox_applets
        test_guard_requires_cleanup_helper_before_home_takeover
        test_guard_rejects_stale_cleanup_helper_when_refresh_fails
        test_accessibility_applied_write_errors_are_compensated
        test_accessibility_initial_writes_roll_back_after_module_deactivation
        test_accessibility_failed_compensation_is_recovered_on_uninstall
        test_repair_retains_noncanonical_accessibility_transaction
        test_repair_confirms_binding_after_confirmed_unbound
        test_rebind_preserves_caregiver_change_when_module_deactivates_after_remove
        test_rebind_preserves_caregiver_change_while_module_remains_active
        test_rebind_stops_after_module_deactivates_during_restore
        test_rebind_restores_original_enabled_state_after_interruption
        test_action_marks_persistent_confirmed_unbound_failed
        test_repair_does_not_rebind_initial_enable_when_unbound
        test_repair_ignores_partial_accessibility_diagnostic
        test_repair_bounds_stalled_accessibility_diagnostic
        test_action_bounds_stalled_package_query
        test_kiosk_home_bounds_stalled_launch
        test_kiosk_home_cleans_stalled_descendant_after_caller_exit
        test_command_timeout_sanitizes_non_positive_overrides
        test_doze_add_nonzero_after_apply_retains_ownership
        test_doze_marker_directory_race_blocks_add
        test_doze_same_boot_pending_absence_does_not_redispatch
        test_doze_visible_pending_state_promotes_to_owned
        test_doze_cross_boot_pending_absence_retries_once
        test_doze_transaction_blocks_cleanup_while_add_is_in_flight
        test_guard_runs_initial_repair_and_one_health_cycle
        test_guard_retries_transient_startup_failures
        test_guard_ignores_pid_from_previous_boot
        test_guard_respects_live_guard_same_boot
        test_guard_reclaims_dead_same_boot_lock
        test_guard_reclaims_live_pid_with_mismatched_start_time
        test_guard_keeps_matching_live_owner_active
        test_guard_keeps_live_owner_active_when_identity_unreadable
        test_guard_publishes_owner_start_time_before_pid
        test_guard_preserves_incomplete_lock_for_service_retry
        test_service_retries_incomplete_lock
        test_service_restarts_non_lock_guard_failure
        test_service_reclaims_lock_after_owner_disappears
        test_service_stops_when_module_disabled_or_removing
        test_guard_rejects_inactive_module_before_initial_repair
        test_guard_stops_home_enforcement_after_disable_or_remove
        test_action_rejects_disabled_or_removing_module
        test_action_rolls_back_home_when_module_deactivates_during_set
        test_action_rolls_back_latest_home_when_marker_predates_takeover
        test_action_persists_latest_home_when_inactive_rollback_fails
        test_uninstall_recovers_latest_home_after_late_set_completion
        test_action_removes_home_after_mid_set_deactivation_when_prior_was_none
        test_repeated_home_takeover_never_clobbers_original_holder
        test_manual_yinxing_choice_after_inactive_rollback_is_preserved
        test_home_transaction_lock_serializes_concurrent_actions
        test_uninstall_waits_for_unpublished_home_transaction
        test_home_transaction_lock_reclaims_dead_owner
        test_home_transaction_lock_rejects_symlink
        test_guard_promotes_visible_pending_home_state
        test_guard_waits_for_same_boot_pending_home_absence
        test_guard_rebaselines_cross_boot_pending_home
        test_action_stops_after_module_deactivates_during_doze_add
        test_action_stops_after_module_deactivates_during_first_appop
        test_action_stops_after_module_deactivates_during_package_probe
        test_action_stops_after_module_deactivates_during_accessibility_read
        test_guard_prevents_concurrent_processes
        test_action_reuses_repair_and_launch
        test_cleanup_helper_waits_for_module_removal
        test_cleanup_helper_stays_for_first_boot
        test_cleanup_schedule_failure_preserves_existing_helper
        test_cleanup_directory_target_is_rejected
        test_uninstall_reports_cleanup_schedule_failure
        test_uninstall_defers_cleanup_until_boot_completed
        test_uninstall_retains_marker_when_doze_remove_fails
        test_uninstall_cleanup_bounds_stalled_doze_remove
        test_uninstall_resolves_pending_doze_state
        test_uninstall_retains_same_boot_pending_doze_absence
        test_uninstall_accepts_nonzero_after_applied_doze_remove
        test_uninstall_retries_unconfirmed_doze_remove
        test_uninstall_clears_absent_owned_doze_state
        test_uninstall_clears_unarmed_home_evidence_without_mutation
        test_uninstall_rejects_owned_home_state_without_original
        test_uninstall_retains_same_boot_pending_home_absence
        test_uninstall_waits_for_live_home_transaction
        test_uninstall_recovers_global_only_accessibility_transaction
        test_uninstall_retains_malformed_accessibility_transaction
        test_uninstall_retains_nonregular_accessibility_transactions
        test_uninstall_retains_malformed_marker
        test_uninstall_restores_previous_home_holder
        test_uninstall_removes_owned_home_when_previous_was_none
        test_uninstall_preserves_newer_home_choice
        test_uninstall_does_not_remove_preexisting_yinxing_home
        test_uninstall_retains_home_marker_when_previous_package_is_missing
        test_uninstall_retains_home_marker_when_restore_fails
        test_uninstall_retains_invalid_home_marker
        test_uninstall_bounds_stalled_home_restore
        test_uninstall_completes_home_when_doze_cleanup_needs_retry
        test_uninstall_retains_nonregular_home_markers
        test_uninstall_retains_nonregular_doze_markers
        test_uninstall_rejects_trailing_blank_home_marker
        test_uninstall_rejects_trailing_blank_home_query
        test_uninstall_rejects_invalid_android_home_markers
        test_uninstall_preserves_choice_made_during_previous_home_validation
        test_uninstall_retries_failed_or_unconfirmed_home_removal
        test_uninstall_bounds_stalled_home_removal
        test_uninstall_completes_doze_when_home_removal_needs_retry
        ;;
    all)
        test_merge_cases
        test_status_reports_healthy_state
        test_status_reports_stale_cleanup_helper_as_invalid
        test_status_reports_other_home_holder
        test_status_reports_no_home_holder
        test_status_reports_unknown_home_holder
        test_status_reports_disabled_package_as_disabled
        test_status_reports_disabled_component_as_disabled
        test_status_reports_unknown_when_package_state_query_fails
        test_status_reports_unknown_when_component_state_query_fails
        test_status_reports_stale_when_accessibility_service_crashed
        test_status_reports_stale_when_accessibility_service_confirmed_unbound
        test_status_output_contract_ignores_log_noise
        test_status_reports_stale_guard_as_degraded
        test_status_reports_stale_guard_when_pid_identity_mismatches
        test_status_reports_missing_module
        test_home_role_owned_is_idempotent
        test_home_role_reconciles_other_holder
        test_home_role_reconciles_no_holder
        test_home_role_query_failure_is_safe
        test_home_role_malformed_output_is_safe
        test_home_role_multiple_holders_are_safe
        test_home_role_rejects_invalid_android_package_names
        test_home_marker_rejects_invalid_android_package_names
        test_android_package_name_length_boundary
        test_home_role_invalid_marker_is_safe
        test_home_role_marker_write_failure_is_safe
        test_home_role_set_failure_retains_marker
        test_home_role_unconfirmed_set_retains_marker
        test_home_role_bounds_stalled_query
        test_home_role_bounds_stalled_set
        test_home_role_rejects_trailing_blank_query_output
        test_home_role_rejects_trailing_blank_marker
        test_home_marker_concurrent_publish_does_not_clobber
        test_home_marker_sync_failure_blocks_takeover
        test_home_role_preserves_choice_after_takeover_state_publish
        test_home_marker_sync_is_bounded
        test_home_marker_uses_default_busybox_applets
        test_guard_requires_cleanup_helper_before_home_takeover
        test_guard_rejects_stale_cleanup_helper_when_refresh_fails
        test_repair_preserves_and_enables
        test_repair_is_idempotent
        test_accessibility_applied_write_errors_are_compensated
        test_accessibility_initial_writes_roll_back_after_module_deactivation
        test_accessibility_failed_compensation_is_recovered_on_uninstall
        test_repair_retains_noncanonical_accessibility_transaction
        test_repair_confirms_binding_after_crash
        test_repair_confirms_binding_after_confirmed_unbound
        test_rebind_preserves_caregiver_change_when_module_deactivates_after_remove
        test_rebind_preserves_caregiver_change_while_module_remains_active
        test_rebind_stops_after_module_deactivates_during_restore
        test_rebind_restores_original_enabled_state_after_interruption
        test_action_marks_persistent_accessibility_crash_failed
        test_action_marks_persistent_confirmed_unbound_failed
        test_repair_does_not_rebind_initial_enable_when_unbound
        test_repair_ignores_partial_accessibility_diagnostic
        test_repair_bounds_stalled_accessibility_diagnostic
        test_command_timeout_sanitizes_non_positive_overrides
        test_repair_keeps_unknown_rebind_confirmation_nonfatal
        test_repair_leaves_bound_or_binding_accessibility_service_untouched
        test_repair_ignores_unavailable_accessibility_diagnostic
        test_missing_package_is_safe
        test_optional_failure_does_not_block_accessibility
        test_settings_read_failure_is_safe
        test_package_enable_failure_is_reported
        test_doze_query_failure_is_safe
        test_doze_add_claims_ownership
        test_doze_add_nonzero_after_apply_retains_ownership
        test_doze_marker_directory_race_blocks_add
        test_doze_same_boot_pending_absence_does_not_redispatch
        test_doze_visible_pending_state_promotes_to_owned
        test_doze_cross_boot_pending_absence_retries_once
        test_doze_transaction_blocks_cleanup_while_add_is_in_flight
        test_home_launch_is_fixed
        test_kiosk_home_command_requires_active_module
        test_kiosk_home_bounds_stalled_launch
        test_kiosk_home_cleans_stalled_descendant_after_caller_exit
        test_guard_runs_initial_repair_and_one_health_cycle
        test_guard_retries_transient_startup_failures
        test_guard_ignores_pid_from_previous_boot
        test_guard_respects_live_guard_same_boot
        test_guard_reclaims_dead_same_boot_lock
        test_guard_reclaims_live_pid_with_mismatched_start_time
        test_guard_keeps_matching_live_owner_active
        test_guard_keeps_live_owner_active_when_identity_unreadable
        test_guard_publishes_owner_start_time_before_pid
        test_guard_preserves_incomplete_lock_for_service_retry
        test_service_retries_incomplete_lock
        test_service_restarts_non_lock_guard_failure
        test_service_reclaims_lock_after_owner_disappears
        test_service_stops_when_module_disabled_or_removing
        test_guard_rejects_inactive_module_before_initial_repair
        test_guard_stops_home_enforcement_after_disable_or_remove
        test_action_rejects_disabled_or_removing_module
        test_action_rolls_back_home_when_module_deactivates_during_set
        test_action_rolls_back_latest_home_when_marker_predates_takeover
        test_action_persists_latest_home_when_inactive_rollback_fails
        test_uninstall_recovers_latest_home_after_late_set_completion
        test_action_removes_home_after_mid_set_deactivation_when_prior_was_none
        test_repeated_home_takeover_never_clobbers_original_holder
        test_manual_yinxing_choice_after_inactive_rollback_is_preserved
        test_home_transaction_lock_serializes_concurrent_actions
        test_uninstall_waits_for_unpublished_home_transaction
        test_home_transaction_lock_reclaims_dead_owner
        test_home_transaction_lock_rejects_symlink
        test_guard_promotes_visible_pending_home_state
        test_guard_waits_for_same_boot_pending_home_absence
        test_guard_rebaselines_cross_boot_pending_home
        test_action_stops_after_module_deactivates_during_doze_add
        test_action_stops_after_module_deactivates_during_first_appop
        test_action_stops_after_module_deactivates_during_package_probe
        test_action_stops_after_module_deactivates_during_accessibility_read
        test_guard_prevents_concurrent_processes
        test_action_reuses_repair_and_launch
        test_action_bounds_stalled_package_query
        test_cleanup_helper_waits_for_module_removal
        test_cleanup_helper_stays_for_first_boot
        test_cleanup_schedule_failure_preserves_existing_helper
        test_cleanup_directory_target_is_rejected
        test_uninstall_reports_cleanup_schedule_failure
        test_uninstall_defers_cleanup_until_boot_completed
        test_uninstall_retains_marker_when_doze_remove_fails
        test_uninstall_cleanup_bounds_stalled_doze_remove
        test_uninstall_resolves_pending_doze_state
        test_uninstall_retains_same_boot_pending_doze_absence
        test_uninstall_accepts_nonzero_after_applied_doze_remove
        test_uninstall_retries_unconfirmed_doze_remove
        test_uninstall_clears_absent_owned_doze_state
        test_uninstall_clears_unarmed_home_evidence_without_mutation
        test_uninstall_rejects_owned_home_state_without_original
        test_uninstall_retains_same_boot_pending_home_absence
        test_uninstall_waits_for_live_home_transaction
        test_uninstall_recovers_global_only_accessibility_transaction
        test_uninstall_retains_malformed_accessibility_transaction
        test_uninstall_retains_nonregular_accessibility_transactions
        test_uninstall_retains_malformed_marker
        test_uninstall_restores_previous_home_holder
        test_uninstall_removes_owned_home_when_previous_was_none
        test_uninstall_preserves_newer_home_choice
        test_uninstall_does_not_remove_preexisting_yinxing_home
        test_uninstall_retains_home_marker_when_previous_package_is_missing
        test_uninstall_retains_home_marker_when_restore_fails
        test_uninstall_retains_invalid_home_marker
        test_uninstall_bounds_stalled_home_restore
        test_uninstall_completes_home_when_doze_cleanup_needs_retry
        test_uninstall_retains_nonregular_home_markers
        test_uninstall_retains_nonregular_doze_markers
        test_uninstall_rejects_trailing_blank_home_marker
        test_uninstall_rejects_trailing_blank_home_query
        test_uninstall_rejects_invalid_android_home_markers
        test_uninstall_preserves_choice_made_during_previous_home_validation
        test_uninstall_retries_failed_or_unconfirmed_home_removal
        test_uninstall_bounds_stalled_home_removal
        test_uninstall_completes_doze_when_home_removal_needs_retry
        test_module_package
        if [[ -z "${YINXING_TEST_SHELL:-}" ]] && command -v busybox >/dev/null 2>&1; then
            YINXING_TEST_SHELL=busybox bash "$0" all
        fi
        ;;
    *)
        fail "unknown mode: $MODE"
        ;;
esac
