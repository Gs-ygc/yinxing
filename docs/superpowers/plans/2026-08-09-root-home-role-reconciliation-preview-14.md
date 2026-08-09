# Root HOME Role Reconciliation Preview 14 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the active KernelSU module continuously own Android's HOME role for user 0, report that ownership through Root health schema 2, and conditionally restore the prior launcher after module removal.

**Architecture:** Extend the existing module-only Android command boundary with exact AOSP role query/set calls and a root-owned atomic prior-holder marker. Keep rollback in the standalone boot-completed cleanup helper, and extend the APK's strict snapshot parser/UI without adding any APK Root command path.

**Tech Stack:** POSIX shell, KernelSU BusyBox `ash`, AOSP `cmd role`/`cmd package`, Bash behavior harness, Kotlin, Robolectric/JUnit 4, Gradle 9.3.1, Android SDK 36.

## Global Constraints

- Target only the managed OnePlus 15, China ColorOS 16, KernelSU, Android user 0.
- The APK Root allowlist remains exactly `status.sh`, `action.sh`, and `kiosk-home.sh`, with no arguments.
- All module-side `cmd` and `pm` calls must use `run_guard_command`; no unbounded fallback is allowed.
- Only the fixed Yinxing package/component may be selected for takeover; prior-holder restore input must come from validated root-owned system-observed state.
- Unknown, malformed, multiple-holder, timeout, or failed role evidence must be non-mutating and fail closed.
- Kiosk remains opt-in and the ordinary unrooted `RoleManager` flow remains available.
- Module uninstall may restore a prior holder only while Yinxing is still current; a newer caregiver choice wins.
- Preview 14 versions are APK `versionCode=30` / `1.10.0-root-preview.14` and module `versionCode=14` / `1.10.0-root-preview.14`.

## File Structure

- `tools/test-yinxing-guard.sh`: stateful HOME-role fake, RED/GREEN behavior tests, version/package assertions.
- `root/kernelsu/yinxing_guard/bin/common.sh`: shared exact role parsing, atomic prior-holder state, takeover and confirmation.
- `root/kernelsu/yinxing_guard/bin/status.sh`: schema-2 `home` observation.
- `root/kernelsu/yinxing_guard/uninstall.sh`: preserve/schedule deferred HOME rollback.
- `root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh`: standalone conditional HOME restoration plus existing Doze cleanup.
- `app/src/main/java/com/yinxing/launcher/common/root/RootHealthSnapshot.kt`: strict schema-1/schema-2 parser and health derivation.
- `app/src/test/java/com/yinxing/launcher/common/root/RootHealthSnapshotTest.kt`: parser compatibility and HOME health tests.
- `app/src/main/java/com/yinxing/launcher/feature/settings/SettingsRootHealthSheet.kt`: render HOME as the seventh health dimension.
- `app/src/test/java/com/yinxing/launcher/feature/settings/SettingsActivitySmokeTest.kt`: verify caregiver summary includes HOME.
- `app/src/main/res/values/strings.xml`: concise HOME-aware summary copy.
- `app/build.gradle.kts`, `root/kernelsu/yinxing_guard/module.prop`: Preview 14 versions.
- `docs/release/yinxing-root-preview-14.md`: release behavior, install/rollback, evidence and caveats.

---

### Task 1: HOME Role Harness and RED Reconciliation Contract

**Files:**
- Modify: `tools/test-yinxing-guard.sh:7-273`
- Modify: `tools/test-yinxing-guard.sh:275-830`
- Modify: `tools/test-yinxing-guard.sh:1470-1590`

**Interfaces:**
- Consumes: existing `run_module_script`, `run_guard_command`, `repair_state`, status and reset fixtures.
- Produces: exported `HOME_HOLDER` fixture file plus role query/set/remove failure and stall controls used by Tasks 2 and 3.

- [ ] **Step 1: Add a stateful fake HOME role without changing production code**

Initialize and export:

```bash
HOME_HOLDER="$TEST_ROOT/home_holder"
printf 'com.oplus.launcher\n' > "$HOME_HOLDER"
export HOME_HOLDER
```

Extend fake `cmd` before its device-idle branches:

```bash
if [[ "${1:-}" == "role" && "${2:-}" == "get-role-holders" ]]; then
    [[ -e "$TEST_ROOT/hang_home_role_query" ]] && /bin/sleep 5
    [[ -e "$TEST_ROOT/fail_home_role_query" ]] && exit 1
    [[ -f "$TEST_ROOT/malformed_home_role_output" ]] && cat "$TEST_ROOT/malformed_home_role_output" && exit 0
    [[ -s "$HOME_HOLDER" ]] && cat "$HOME_HOLDER"
    exit 0
fi
if [[ "${1:-}" == "package" && "${2:-}" == "set-home-activity" ]]; then
    [[ -e "$TEST_ROOT/hang_home_role_set" ]] && /bin/sleep 5
    [[ -e "$TEST_ROOT/fail_home_role_set" ]] && exit 1
    target="${!#}"
    [[ -e "$TEST_ROOT/ignore_home_role_set" ]] || printf '%s\n' "${target%%/*}" > "$HOME_HOLDER"
    exit 0
fi
if [[ "${1:-}" == "role" && "${2:-}" == "remove-role-holder" ]]; then
    [[ -e "$TEST_ROOT/fail_home_role_remove" ]] && exit 1
    : > "$HOME_HOLDER"
    exit 0
fi
```

Extend fake `pm path` so a restore target can be absent:

```bash
if [[ "${args[0]:-}" == "path" && "${args[-1]:-}" == "com.oplus.launcher" ]]; then
    [[ -e "$TEST_ROOT/previous_home_missing" ]] && exit 1
    printf '/system/priv-app/OplusLauncher/OplusLauncher.apk\n'
    exit 0
fi
```

Reset every new control and reset `HOME_HOLDER` to `com.oplus.launcher`; make `prepare_healthy_status_fixture` set it to `com.yinxing.launcher`.

- [ ] **Step 2: Add failing reconciliation and status tests**

Add tests with exact command assertions:

```bash
test_home_role_owned_is_idempotent() {
    reset_fixture
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    repair_state || fail "owned HOME should be healthy"
    assert_not_contains "$CALLS" "cmd package set-home-activity"
    [[ ! -e "$TEST_ROOT/state/home_previous_holder" ]] || fail "manual HOME ownership was claimed"
}

test_home_role_reconciles_other_holder() {
    reset_fixture
    repair_state || fail "another HOME holder should be reconciled"
    assert_equals "com.yinxing.launcher" "$(tr -d '\n' < "$HOME_HOLDER")" "HOME takeover"
    assert_equals "com.oplus.launcher" "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" "prior HOME marker"
    assert_equals "1" "$(grep -c '^cmd package set-home-activity --user 0 com.yinxing.launcher/.feature.home.MainActivity$' "$CALLS")" "fixed HOME takeover count"
}

test_home_role_reconciles_no_holder() {
    reset_fixture
    : > "$HOME_HOLDER"
    repair_state || fail "empty HOME should be reconciled"
    assert_equals "none" "$(tr -d '\n' < "$TEST_ROOT/state/home_previous_holder")" "empty HOME marker"
}
```

Add failure tests for query failure, malformed output (`bad holder`), two holder lines, an invalid existing marker, a state-directory shape that prevents atomic marker creation, set failure, ignored set/failed confirmation, a one-second stalled query, and a one-second stalled set. Every failure must assert no unconfirmed HOME mutation, no `am start`, `last_repair=failed` when called through `action.sh`, marker retention where applicable, and elapsed time below four seconds. The marker-write failure must prove the set command was never attempted; the stalled set must prove the durable prior-holder marker survives for rollback.

Update status tests to expect `schema=2`, `home=owned`, and exactly nine output lines. Add `home=other`, `home=none`, and `home=unknown` cases.

- [ ] **Step 3: Run the focused suite and verify RED**

Run:

```bash
bash tools/test-yinxing-guard.sh --guard-only
```

Expected: FAIL at the first HOME reconciliation assertion because `repair_state` does not query or set the role.

Run:

```bash
bash tools/test-yinxing-guard.sh --status-only
```

Expected: FAIL because `status.sh` still emits schema 1 with eight lines and no `home` field.

- [ ] **Step 4: Check fixture syntax and commit the reviewed RED contract**

Run:

```bash
bash -n tools/test-yinxing-guard.sh
git diff --check
```

Expected: both exit 0.

Commit:

```bash
git add tools/test-yinxing-guard.sh
git commit -m "test: define root home ownership contract"
```

---

### Task 2: Shared HOME Reconciliation and Status Schema 2

**Files:**
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh:3-442`
- Modify: `root/kernelsu/yinxing_guard/bin/status.sh:1-193`
- Modify: `tools/test-yinxing-guard.sh`

**Interfaces:**
- Consumes: `run_guard_command`, `ensure_state_dir`, `record_repair_result`, fixed `PACKAGE_NAME`, `HOME_COMPONENT`, `ANDROID_USER_ID`.
- Produces: `read_home_role_holder`, `home_role_state`, `repair_home_role`, `HOME_PREVIOUS_HOLDER_MARKER`, and schema-2 `home` output for Tasks 3 and 4.

- [ ] **Step 1: Implement exact shared role parsing and marker validation**

Add constants:

```sh
HOME_ROLE_NAME="android.app.role.HOME"
HOME_PREVIOUS_HOLDER_MARKER="$STATE_DIR/home_previous_holder"
```

Add helpers with these contracts:

```sh
valid_home_holder() {
    case "$1" in
        ''|none|.*|*.|*..*|*[!A-Za-z0-9_.]*) return 1 ;;
        *.*) [ "$1" != "$PACKAGE_NAME" ] ;;
        *) return 1 ;;
    esac
}

read_home_role_holder() {
    home_output="$(run_guard_command cmd role get-role-holders --user "$ANDROID_USER_ID" "$HOME_ROLE_NAME" 2>/dev/null)" || return 1
    [ -n "$home_output" ] || { printf 'none\n'; return 0; }
    case "$home_output" in
        *[!A-Za-z0-9_.]*|.*|*.|*..*) return 1 ;;
    esac
    case "$home_output" in *.*) printf '%s\n' "$home_output" ;; *) return 1 ;; esac
}

home_role_state() {
    holder="$(read_home_role_holder)" || { printf 'unknown\n'; return 0; }
    case "$holder" in
        "$PACKAGE_NAME") printf 'owned\n' ;;
        none) printf 'none\n' ;;
        *) printf 'other\n' ;;
    esac
}
```

Implement atomic `record_home_previous_holder(holder)` like `record_repair_result`: validate `none` or a non-Yinxing package, preserve an existing valid marker, reject an invalid marker, write a `home_previous_holder.tmp.$$` file with `0600`, and atomically `mv` it into place.

- [ ] **Step 2: Implement confirmed takeover in the repair pipeline**

Add:

```sh
repair_home_role() {
    holder="$(read_home_role_holder)" || { log_event "home_role_query_failed"; return 1; }
    if [ -f "$HOME_PREVIOUS_HOLDER_MARKER" ]; then
        saved="$(cat "$HOME_PREVIOUS_HOLDER_MARKER" 2>/dev/null || true)"
        [ "$saved" = "none" ] || valid_home_holder "$saved" || {
            log_event "home_role_marker_invalid"
            return 1
        }
    fi
    [ "$holder" = "$PACKAGE_NAME" ] && return 0
    record_home_previous_holder "$holder" || return 1
    run_guard_command cmd package set-home-activity --user "$ANDROID_USER_ID" "$HOME_COMPONENT" >/dev/null 2>&1 || {
        log_event "home_role_set_failed"
        return 1
    }
    confirmed="$(read_home_role_holder)" || { log_event "home_role_confirm_failed"; return 1; }
    [ "$confirmed" = "$PACKAGE_NAME" ] || { log_event "home_role_unconfirmed"; return 1; }
    log_event "home_role_repaired"
}
```

Call it after `repair_accessibility` and before optional keepalive:

```sh
repair_state() {
    repair_accessibility || return 1
    repair_home_role || return 1
    repair_keepalive
}
```

- [ ] **Step 3: Emit schema 2 and HOME state**

In `status.sh`, derive `home_value=unknown` when the module is absent; otherwise call `home_role_state`. Emit exactly:

```text
schema=2
version=...
module=...
guard=...
accessibility=...
home=owned|other|none|unknown
doze=...
cleanup=...
last_repair=...
```

- [ ] **Step 4: Run GREEN host and BusyBox-focused verification**

Run:

```bash
bash tools/test-yinxing-guard.sh --guard-only
bash tools/test-yinxing-guard.sh --status-only
YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh --guard-only
YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh --status-only
bash -n root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/status.sh tools/test-yinxing-guard.sh
busybox ash -n root/kernelsu/yinxing_guard/bin/common.sh
git diff --check
```

Expected: all commands exit 0; stalled role query returns inside the existing bound.

- [ ] **Step 5: Commit the reconciliation slice**

```bash
git add root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/status.sh tools/test-yinxing-guard.sh
git commit -m "feat: reconcile root home ownership"
```

---

### Task 3: Deferred Conditional HOME Rollback

**Files:**
- Modify: `tools/test-yinxing-guard.sh:1267-1410`
- Modify: `root/kernelsu/yinxing_guard/uninstall.sh:1-30`
- Modify: `root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh:1-80`

**Interfaces:**
- Consumes: `$STATE_DIR/home_previous_holder`, exact role query semantics from Task 2, Preview 13's local timeout supervisor.
- Produces: independently retryable HOME/Doze cleanup and user-choice-preserving rollback.

- [ ] **Step 1: Add failing uninstall behavior tests**

Add tests for these exact outcomes:

```bash
test_uninstall_restores_previous_home_holder
test_uninstall_removes_owned_home_when_previous_was_none
test_uninstall_preserves_newer_home_choice
test_uninstall_does_not_remove_preexisting_yinxing_home
test_uninstall_retains_home_marker_when_previous_package_is_missing
test_uninstall_retains_home_marker_when_restore_fails
test_uninstall_retains_invalid_home_marker
test_uninstall_bounds_stalled_home_restore
test_uninstall_completes_home_when_doze_cleanup_needs_retry
```

For previous-holder restoration, seed marker `com.oplus.launcher`, set current holder to Yinxing, run `uninstall.sh`, assert no immediate role mutation, then run the copied helper and require exactly one `cmd package set-home-activity --user 0 com.oplus.launcher` plus exact confirmation before marker/helper removal.

For a newer choice, seed marker `com.oplus.launcher`, set current holder to `com.example.caregiverlauncher`, and assert cleanup deletes only the marker with no set/remove command.

Run `bash tools/test-yinxing-guard.sh --guard-only`; expect the first new rollback test to fail because uninstall scheduling currently depends only on the Doze marker.

- [ ] **Step 2: Implement standalone validated HOME cleanup**

Mirror only the constants and exact parser required after module removal. Add `cleanup_home_role()`:

```sh
cleanup_home_role() {
    [ -f "$HOME_MARKER" ] || return 0
    previous="$(cat "$HOME_MARKER" 2>/dev/null || true)"
    [ "$previous" = "none" ] || valid_home_holder "$previous" || {
        log_event "uninstall_home_marker_invalid"
        return 1
    }
    current="$(read_home_role_holder)" || return 1
    if [ "$current" != "$PACKAGE_NAME" ]; then
        rm -f "$HOME_MARKER"
        log_event "uninstall_home_preserved_new_choice"
        return 0
    fi
    if [ "$previous" = "none" ]; then
        run_guard_command cmd role remove-role-holder --user "$ANDROID_USER_ID" "$HOME_ROLE_NAME" "$PACKAGE_NAME" >/dev/null 2>&1 || return 1
        confirmed="$(read_home_role_holder)" || return 1
        [ "$confirmed" != "$PACKAGE_NAME" ] || return 1
    else
        run_guard_command pm path --user "$ANDROID_USER_ID" "$previous" >/dev/null 2>&1 || return 1
        run_guard_command cmd package set-home-activity --user "$ANDROID_USER_ID" "$previous" >/dev/null 2>&1 || return 1
        confirmed="$(read_home_role_holder)" || return 1
        [ "$confirmed" = "$previous" ] || return 1
    fi
    rm -f "$HOME_MARKER"
}
```

Run HOME and Doze cleanup independently, collect a failure flag, and only delete runtime state/helper when neither ownership marker remains. Add `home_previous_holder.tmp.*` to temp cleanup, never remove the durable marker before successful/skip completion.

- [ ] **Step 3: Schedule cleanup for either ownership marker**

In `uninstall.sh`, preserve both durable markers and install the cleanup helper when either exists:

```sh
if [ -f "$doze_marker" ] || [ -f "$home_marker" ]; then
    install_cleanup_helper "$cleanup_source" || exit 1
else
    rm -f "$cleanup_target"
    rmdir "$STATE_DIR" 2>/dev/null || true
fi
```

- [ ] **Step 4: Run the full rollback matrix in both shells**

Run:

```bash
bash tools/test-yinxing-guard.sh --guard-only
YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh --guard-only
bash -n root/kernelsu/yinxing_guard/uninstall.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh tools/test-yinxing-guard.sh
busybox ash -n root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh
git diff --check
```

Expected: all exit 0; stalled restore remains below four seconds and retains retry state.

- [ ] **Step 5: Commit rollback behavior**

```bash
git add root/kernelsu/yinxing_guard/uninstall.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh tools/test-yinxing-guard.sh
git commit -m "feat: restore prior home on module removal"
```

---

### Task 4: Strict APK Schema 2 and HOME Health UI

**Files:**
- Modify: `app/src/test/java/com/yinxing/launcher/common/root/RootHealthSnapshotTest.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/common/root/RootHealthSnapshot.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/feature/settings/SettingsActivitySmokeTest.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/feature/settings/SettingsRootHealthSheet.kt:235-296`
- Modify: `app/src/main/res/values/strings.xml:256-278`

**Interfaces:**
- Consumes: schema-2 `home` line from Task 2.
- Produces: `RootHealthSnapshot.home`, exact schema compatibility, and a caregiver-visible HOME health dimension.

- [ ] **Step 1: Write RED schema tests**

Make the healthy fixture schema 2 with `home=owned`, then add:

```kotlin
@Test fun schemaTwoRequiresOwnedHomeForHealthy()
@Test fun schemaTwoOtherNoneAndUnknownHomeAreDegraded()
@Test fun schemaTwoRejectsMissingDuplicateAndUnknownHome()
@Test fun schemaOneRemainsParseableButDegradedWithUnknownHome()
@Test fun rejectsSchemaOneWithHomeAndSchemaTwoWithoutHome()
```

Schema-1 compatibility must assert a non-null snapshot, `home == "unknown"`, and `state == DEGRADED`. Run:

```bash
env GRADLE_OPTS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888 -Dkotlin.incremental=false' bash ./gradlew :app:testDebugUnitTest --tests com.yinxing.launcher.common.root.RootHealthSnapshotTest --no-daemon --console=plain
```

Expected: compilation/test failure because `home` and schema 2 are not implemented.

- [ ] **Step 2: Implement schema-dependent exact parsing**

Add `val home: String = "unknown"`. Replace the single key set with:

```kotlin
private val schemaOneKeys = setOf("schema", "version", "module", "guard", "accessibility", "doze", "cleanup", "last_repair")
private val schemaTwoKeys = schemaOneKeys + "home"
private val allKeys = schemaTwoKeys
```

Parse only keys in `allKeys`, then select the exact expected set from schema `1` or `2`. Allow `home` only as `owned`, `other`, `none`, or `unknown`. Derive healthy only when schema is `2` and home is `owned`; schema 1 active snapshots remain degraded. Preserve `MODULE_MISSING` precedence.

- [ ] **Step 3: Add HOME to the existing status summary**

Change the string to:

```xml
<string name="settings_root_entry_status_summary">模块 %1$s · 守护 %2$s · 无障碍 %3$s · 桌面 %4$s · 省电 %5$s · 清理 %6$s · 上次修复 %7$s</string>
```

Pass `rootValueLabel(snapshot.home)` as argument 4. Treat `owned` as ready and `other`/`none` as pending. Update degraded/healthy hub copy to mention desktop ownership.

Make `rootHealthStatusSummary` internal and add a Robolectric assertion that a schema-2 healthy snapshot renders `桌面 正常` while schema-1 renders `桌面 未知`.

- [ ] **Step 4: Run focused and full JVM tests**

Run:

```bash
env GRADLE_OPTS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888 -Dkotlin.incremental=false' bash ./gradlew :app:testDebugUnitTest --tests com.yinxing.launcher.common.root.RootHealthSnapshotTest --tests com.yinxing.launcher.feature.settings.SettingsActivitySmokeTest --no-daemon --console=plain
env GRADLE_OPTS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888 -Dkotlin.incremental=false' bash ./gradlew :app:testDebugUnitTest --no-daemon --console=plain
git diff --check
```

Expected: all tests pass with zero failures/errors.

- [ ] **Step 5: Commit APK schema/UI support**

```bash
git add app/src/main/java/com/yinxing/launcher/common/root/RootHealthSnapshot.kt app/src/test/java/com/yinxing/launcher/common/root/RootHealthSnapshotTest.kt app/src/main/java/com/yinxing/launcher/feature/settings/SettingsRootHealthSheet.kt app/src/test/java/com/yinxing/launcher/feature/settings/SettingsActivitySmokeTest.kt app/src/main/res/values/strings.xml
git commit -m "feat: surface root home ownership health"
```

---

### Task 5: Preview 14 Version, Review, Verification, and Release

**Files:**
- Modify: `app/build.gradle.kts:42-48`
- Modify: `root/kernelsu/yinxing_guard/module.prop`
- Modify: version fixtures in `tools/test-yinxing-guard.sh`
- Create: `docs/release/yinxing-root-preview-14.md`

**Interfaces:**
- Consumes: all Tasks 1-4 behavior and artifacts.
- Produces: reviewed source, deterministic APK/module assets, pushed branch/main/tag, and remotely verified GitHub prerelease.

- [ ] **Step 1: Bump exact Preview 14 versions and update package assertions**

Set APK code/name `30` / `1.10.0-root-preview.14`, module code/name `14` / `1.10.0-root-preview.14`, and both script `MODULE_VERSION` literals. Update module package tests to require code 14 and Preview 14 source metadata.

Run host and recursive BusyBox full suites and require exit 0:

```bash
/usr/bin/time -f 'ELAPSED_SECONDS=%e' bash tools/test-yinxing-guard.sh all
```

- [ ] **Step 2: Run source safety gates**

```bash
bash -n root/kernelsu/yinxing_guard/bin/*.sh root/kernelsu/yinxing_guard/*.sh tools/test-yinxing-guard.sh tools/package-yinxing-guard.sh
busybox ash -n root/kernelsu/yinxing_guard/bin/common.sh
busybox ash -n root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh
! rg -n '(^[[:space:]]*|\$\()(pm|settings|dumpsys|cmd|am|getprop)([[:space:]]|$)' root/kernelsu/yinxing_guard --glob '*.sh'
git diff --check
```

Expected: syntax/diff commands exit 0 and direct-command scan finds no unwrapped call.

- [ ] **Step 3: Run independent code review before release finalization**

Review the full branch diff against the design for Critical/Important findings, especially marker corruption, current-holder races, uninstall user-choice preservation, schema compatibility, timeout descendants, and Root authority expansion. Fix every Critical/Important issue with RED coverage, then rerun affected host/BusyBox/JVM tests.

- [ ] **Step 4: Force the full Android unit-test and Debug build**

```bash
env GRADLE_OPTS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888 -Dkotlin.incremental=false' /usr/bin/time -f 'ELAPSED_SECONDS=%e' bash ./gradlew :app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon --console=plain
```

Parse every `app/build/test-results/testDebugUnitTest/TEST-*.xml` with Ruby REXML and require failures, errors, and skipped all equal zero.

- [ ] **Step 5: Build and verify deterministic release assets**

Create `out/release/yinxing-1.10.0-root-preview.14-debug.apk`, `yinxing-guard-1.10.0-root-preview.14.zip`, and basename-only `SHA256SUMS.txt`. Verify:

- APK package `com.yinxing.launcher`, code 30/name Preview 14, min 24, target/compile 36;
- APK Signature Scheme v2;
- module 11 root entries, executable scripts, normalized 1980 timestamps, code 14/name Preview 14;
- second module package is byte-identical;
- `sha256sum -c SHA256SUMS.txt` exits 0.

- [ ] **Step 6: Write and commit release notes**

Document managed HOME takeover, schema 2, conditional prior-holder restoration, install order, uninstall-before-downgrade rollback, fixed Root authority, AOSP source basis, hashes, test/build times, Debug signature caveat, and no physical OnePlus 15 caveat.

Commit all final source and notes, then reproduce the full shell suite, forced Android build, APK, and module from the exact commit. Both rebuilt assets must be byte-identical to release candidates.

- [ ] **Step 7: Push and publish the rollback-capable prerelease**

Push feature branch and fast-forward `main`. Create/push annotated tag `v1.10.0-root-preview.14`, then publish a non-draft prerelease titled `银杏 Root 增强 Preview 14` with the three assets and committed notes. Do not mark it latest.

- [ ] **Step 8: Verify GitHub as a fresh consumer**

Download all assets into a new `mktemp -d`. Require checksum success, exact bytes, APK metadata/v2 signature, ZIP integrity/layout/modes/timestamps, exact Release body bytes, uploaded asset states/digests, prerelease state, and `main`/feature/peeled-tag equality. Confirm GitHub's latest endpoint is not Preview 14.

- [ ] **Step 9: Update persistent evidence and remain active for device feedback**

Record final commit, timings, test totals, hashes, Release URL, review fixes, and the outstanding OnePlus 15 acceptance checks in `.planning/`. Keep the persistent Goal active; device evidence must verify ColorOS role output, takeover, Home-key routing, module removal restoration, accessibility binding, and reboot keepalive.
