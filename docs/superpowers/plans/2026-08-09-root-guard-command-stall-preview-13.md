# Root Guard Command Stall Resilience Preview 13 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bound every Android command used by the Root module so a ColorOS Binder stall cannot leave the background Guard alive but permanently unable to repair accessibility or keepalive state.

**Architecture:** Add one internal BusyBox `timeout -k 1` helper in `bin/common.sh` with a sanitized two-second default and wrap only existing literal Android command call sites. The standalone uninstall cleanup script gets the same local wrapper because it must survive module removal; external APK Root routing and output/status schemas remain unchanged.

**Tech Stack:** KernelSU BusyBox `ash` standalone mode, POSIX shell, Bash host harness, BusyBox `timeout` applet, Gradle 9.3.1, Android SDK Build Tools 36.0.0.

## Global Constraints

- Keep exactly three fixed, no-argument Root paths: `status.sh`, `action.sh`, and `kiosk-home.sh`.
- Do not add arbitrary shell, user-supplied arguments, package/component input, coordinates, process targeting, or private ColorOS APIs.
- The internal timeout helper is called only at literal source-controlled call sites and is not exposed through the APK bridge.
- Default internal Android command timeout is `2` seconds; malformed or non-positive test overrides fall back to `2`.
- A timed-out accessibility diagnostic remains `unknown` and side-effect free.
- A timed-out package/settings operation follows its existing failure path; optional Doze/app-op failures remain nonfatal; HOME timeout remains a failed fixed launch.
- Preserve Preview 12's confirmed-unbound, first-enable, bounded confirmation, lock, and supervisor behavior.
- Preview values are APK code/name `29`/`1.10.0-root-preview.13` and module code/name `13`/`1.10.0-root-preview.13`.

---

### Task 1: Red regressions for stalled Android commands

**Files:**
- Modify: `tools/test-yinxing-guard.sh`

**Interfaces:**
- Consumes: current fake `pm`, `settings`, `dumpsys`, `cmd`, and `am` scripts, `CALLS`, `TEST_ROOT`, `run_module_script`, and existing assertion helpers.
- Produces: host and recursive BusyBox behavior tests that fail on Preview 12 because fake commands block for five seconds instead of being bounded.

- [ ] **Step 1: Add deliberate stall switches to existing fake commands.**

In the generated fake scripts, before their normal behavior, add marker checks:

```bash
if [[ -e "$TEST_ROOT/hang_dumpsys" ]]; then /bin/sleep 5; fi
if [[ -e "$TEST_ROOT/hang_pm_path" && "${args[0]:-}" == "path" ]]; then /bin/sleep 5; fi
if [[ -e "$TEST_ROOT/hang_am" ]]; then /bin/sleep 5; fi
if [[ -e "$TEST_ROOT/hang_deviceidle_remove" &&
      "${1:-}" == "deviceidle" && "${2:-}" == "whitelist" &&
      "${3:-}" == -com.yinxing.launcher ]]; then /bin/sleep 5; fi
```

Use the existing `reset_fixture()` cleanup list for all four marker files. Do not replace existing fake behavior or use the harness's fake `sleep`; explicit `/bin/sleep` makes the missing timeout observable.

- [ ] **Step 2: Add the stalled-diagnostic RED test.**

Add `test_repair_bounds_stalled_accessibility_diagnostic()` after the partial-diagnostic test. Set the target in `SERVICES`, set `ACCESSIBILITY_ENABLED` to `1`, create `hang_dumpsys`, set `YINXING_GUARD_COMMAND_TIMEOUT_SECONDS=1`, and run `repair_state`. Measure with Bash's `SECONDS` and require elapsed `< 4`, no secure-setting write, and no `accessibility_service_rebind` event. Current Preview 12 should exceed the bound and fail the elapsed assertion.

- [ ] **Step 3: Add bounded package-query/action and HOME tests.**

Add `test_action_bounds_stalled_package_query()` with `hang_pm_path`. Run `action.sh` under the one-second test override, require nonzero exit, `last_repair=failed`, elapsed `< 4`, no secure-setting write, and no `am start`.

Add `test_kiosk_home_bounds_stalled_launch()` with `hang_am`. Run the fixed `bin/kiosk-home.sh` path under the same override, require nonzero exit, elapsed `< 4`, and exactly one attempted `am start`.

- [ ] **Step 4: Add standalone cleanup timeout coverage.**

Add `test_uninstall_cleanup_bounds_stalled_doze_remove()` with an active cleanup marker and module `remove` marker plus `hang_deviceidle_remove`. Run `bin/uninstall-cleanup.sh` under the one-second override, require nonzero exit, elapsed `< 4`, marker preservation, and no removal of the cleanup script.

- [ ] **Step 5: Register tests and prove RED.**

Register the diagnostic test in `--guard-only` and `all`; register the action, Kiosk, and cleanup tests in `--guard-only` and `all` next to their nearest counterparts. Run:

```bash
bash tools/test-yinxing-guard.sh --guard-only
```

Expected: existing tests pass until the first new elapsed assertion reports a stalled command exceeding the bound. Also run `bash -n tools/test-yinxing-guard.sh` and `git diff --check`.

- [ ] **Step 6: Commit the red slice.**

```bash
git add tools/test-yinxing-guard.sh
git commit -m "test: cover root command stalls"
```

Only the host harness may be changed in this commit.

---

### Task 2: Internal timeout wrapper and green module matrix

**Files:**
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh`
- Modify: `root/kernelsu/yinxing_guard/bin/status.sh`
- Modify: `root/kernelsu/yinxing_guard/bin/guard.sh`
- Modify: `root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh`
- Modify: `tools/test-yinxing-guard.sh` only if a fixture assertion needs correction

**Interfaces:**
- Consumes: Task 1 stall fixtures and existing fixed command call sites.
- Produces: internal `run_guard_command()` plus bounded behavior for all listed Android commands; no new external command path.

- [ ] **Step 1: Add and validate the shared helper.**

Near the constants in `common.sh`, add:

```sh
GUARD_COMMAND_TIMEOUT_SECONDS="${YINXING_GUARD_COMMAND_TIMEOUT_SECONDS:-2}"
case "$GUARD_COMMAND_TIMEOUT_SECONDS" in
    ''|*[!0-9]*|0) GUARD_COMMAND_TIMEOUT_SECONDS=2 ;;
esac

run_guard_command() {
    timeout -k 1 "$GUARD_COMMAND_TIMEOUT_SECONDS" "$@"
}
```

The helper must not fall back to an unbounded direct invocation if `timeout` is unavailable; the resulting nonzero status is safer and is handled by existing callers.

- [ ] **Step 2: Wrap common/status/guard commands without changing semantics.**

Replace only command prefixes at existing call sites:

```sh
run_guard_command pm path --user "$ANDROID_USER_ID" "$PACKAGE_NAME"
run_guard_command settings --user "$ANDROID_USER_ID" get secure accessibility_enabled
run_guard_command dumpsys accessibility
run_guard_command cmd deviceidle whitelist
run_guard_command am start --user "$ANDROID_USER_ID" -n "$HOME_COMPONENT"
run_guard_command getprop sys.boot_completed
```

Keep all arguments, output capture, log event names, and return branches unchanged. In `status.sh`, use the sourced helper for `pm path`, `pm list packages`, and `pm dump`. In `guard.sh`, use it for `getprop sys.boot_completed`. In `common.sh`, cover secure settings, package enable/path, accessibility dump, Doze/appops, HOME launch, and boot-id fallback `getprop`.

- [ ] **Step 3: Add the standalone cleanup wrapper.**

Because `uninstall-cleanup.sh` cannot source `common.sh` after module removal, add the same sanitized constant and helper locally, then replace only its fixed `cmd deviceidle whitelist -com.yinxing.launcher` call. Preserve marker and self-removal behavior.

- [ ] **Step 4: Run focused green tests and syntax checks.**

```bash
bash tools/test-yinxing-guard.sh --guard-only
bash tools/test-yinxing-guard.sh --status-only
bash -n root/kernelsu/yinxing_guard/bin/*.sh tools/test-yinxing-guard.sh tools/package-yinxing-guard.sh
busybox ash -n root/kernelsu/yinxing_guard/bin/common.sh
git diff --check
```

All new stall tests must complete within their `< 4` second assertions in both host and recursive BusyBox execution; all existing behavior tests must remain green.

- [ ] **Step 5: Run and commit the full module matrix.**

```bash
/usr/bin/time -f 'ELAPSED_SECONDS=%e' bash tools/test-yinxing-guard.sh all
```

Require zero failures and commit:

```bash
git add root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/status.sh root/kernelsu/yinxing_guard/bin/guard.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh tools/test-yinxing-guard.sh
git commit -m "fix: bound root guard android commands"
```

---

### Task 3: Preview 13 version, Android verification, and release

**Files:**
- Modify: `app/build.gradle.kts`
- Modify: `root/kernelsu/yinxing_guard/module.prop`
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh`
- Modify: `root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh`
- Modify: `tools/test-yinxing-guard.sh`
- Create: `docs/release/yinxing-root-preview-13.md`

**Interfaces:**
- Consumes: Task 2 bounded module behavior and Preview 12 release procedure.
- Produces: tag `v1.10.0-root-preview.13`, APK/module/checksum assets, release notes, and fresh remote verification evidence.

- [ ] **Step 1: Bump exact version sources and assertions.**

Set APK `versionCode = 29`, `versionName = "1.10.0-root-preview.13"`; module `version=1.10.0-root-preview.13`, `versionCode=13`; and both module `MODULE_VERSION` constants to the same name. Update package-test assertions to `versionCode=13` and Preview 13. Require:

```bash
if rg -n 'root-preview\.12|versionCode=12|versionCode = 28' app root tools --glob '!app/build/**'; then exit 1; fi
```

- [ ] **Step 2: Commit the version slice.**

```bash
git add app/build.gradle.kts root/kernelsu/yinxing_guard/module.prop root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh tools/test-yinxing-guard.sh
git commit -m "chore: bump root preview 13 version"
```

- [ ] **Step 3: Run final shell and Android verification.**

```bash
/usr/bin/time -f 'ELAPSED_SECONDS=%e' bash tools/test-yinxing-guard.sh all
bash -n root/kernelsu/yinxing_guard/bin/*.sh tools/test-yinxing-guard.sh tools/package-yinxing-guard.sh
busybox ash -n root/kernelsu/yinxing_guard/bin/common.sh
env GRADLE_OPTS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888 -Dkotlin.incremental=false' /usr/bin/time -f 'ELAPSED_SECONDS=%e' bash ./gradlew :app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon --console=plain
```

Parse `app/build/test-results/testDebugUnitTest/TEST-*.xml` with Ruby `REXML`; require `failures=0`, `errors=0`, and `skipped=0`.

- [ ] **Step 4: Build deterministic assets and verify metadata.**

Create `out/release/yinxing-1.10.0-root-preview.13-debug.apk`, package `yinxing-guard-1.10.0-root-preview.13.zip`, and write basename-only `SHA256SUMS.txt`. Verify APK code/name 29/Preview13, v2 signature, ZIP integrity, root entries, executable modes, 1980 timestamps, module metadata, and a second byte-identical package.

- [ ] **Step 5: Write notes, review, merge, publish, and remotely verify.**

Write `docs/release/yinxing-root-preview-13.md` with the internal timeout behavior, unchanged Root authority, install module-first order, Preview 12 rollback, Debug caveat, timings/test totals/hashes, official KernelSU assumption, and no-device caveat. Review the full diff from Preview 12, fix all Critical/Important findings, rerun final-source and merged-main verification, fast-forward/push `main` and the feature branch, create annotated tag `v1.10.0-root-preview.13`, publish a non-draft prerelease with `--verify-tag`, then download all assets fresh and verify checksums, exact bytes, APK/ZIP, Release body/state, and remote refs.
