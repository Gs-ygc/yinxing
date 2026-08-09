# Root Accessibility Binding Stall Preview 16 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect and recover a persistently binding Yinxing accessibility service on the fixed rooted OnePlus 15 target with durable bounded evidence, then publish a verified Preview 16 release.

**Architecture:** Keep the existing three fixed Root bridge paths and the existing `repair_accessibility()` transaction. Add one private atomic evidence marker in `bin/common.sh`; count same-boot `Binding services` observations across Guard/action invocations, trigger the reviewed remove/restore rebind after two observations, and stop after two attempts. `status.sh` reads the marker without mutating it, while uninstall paths remove only this diagnostic state.

**Tech Stack:** POSIX `/system/bin/sh`, standalone BusyBox `ash`, the existing Bash fixture `tools/test-yinxing-guard.sh`, Kotlin/JUnit Android tests, Gradle Debug packaging, KernelSU ZIP tooling, GitHub CLI.

## Global Constraints

- Target remains OnePlus 15 China ColorOS 16, KernelSU Root, Android user 0.
- Root command allowlist remains exactly `status.sh`, `action.sh`, and `kiosk-home.sh`, all without APK-supplied arguments.
- New behavior uses no new Android command; it only reuses `dumpsys accessibility`, `settings`, and the reviewed rebind sequence.
- Marker values are `binding|<sanitized-boot-id>|<observations>|<rebind-attempts>`; numeric fields are limited to 0..100000.
- Defaults are threshold 2 and maximum rebind attempts 2; invalid, empty, zero, or non-numeric overrides use those defaults.
- Unknown or malformed Android diagnostics and unsafe marker paths never trigger speculative settings writes.
- Version is `1.10.0-root-preview.16`; APK `versionCode=32`; module `versionCode=16`.
- Every shell behavior test passes in host mode and recursive standalone BusyBox `ash` mode.
- No physical-device validation is claimed; no Android device is attached in this environment.

---

### Task 1: Create red binding-stall contract tests

**Files:**
- Modify: `tools/test-yinxing-guard.sh` fixture reset, accessibility tests, and mode dispatch.

**Interfaces:**
- Consumes: existing `repair_accessibility`, `accessibility_service_binding_state`, fake `dumpsys`, `CALLS`, `STATE_DIR`, `SERVICES`, and `ACCESSIBILITY_ENABLED`.
- Produces: named lifecycle tests and a focused `--preview16-binding-only` mode.

- [ ] **Step 1: Add deterministic fixture controls and cleanup.**

Add `ACCESSIBILITY_BINDING_STALL_MARKER="$TEST_ROOT/state/accessibility_binding_stall"` beside the existing exported state paths. Extend `reset_fixture()` to remove the marker, its `.tmp.*` files, controls for a static binding dump, bound transition, and marker symlink. Keep the fake Android command fixed to `dumpsys accessibility`.

- [ ] **Step 2: Write the first failing behavior test.**

Add this test before production changes:

```bash
test_binding_stall_publishes_first_observation_without_toggle() {
    reset_fixture
    printf '%s\n' "$ACCESSIBILITY_COMPONENT" > "$SERVICES"
    printf '1\n' > "$ACCESSIBILITY_ENABLED"
    cat > "$TEST_ROOT/accessibility_dump" <<EOF
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{$ACCESSIBILITY_COMPONENT}
  Crashed services:{}
  Client list info:{}
]
EOF
    YINXING_GUARD_BINDING_STALL_THRESHOLD=2 repair_accessibility || \
        fail "first binding observation should remain non-fatal"
    assert_equals "binding|fixture-boot|1|0" \
        "$(tr -d '\n' < "$ACCESSIBILITY_BINDING_STALL_MARKER")" \
        "first binding observation marker"
    assert_not_contains "$CALLS" \
        "settings --user 0 put secure enabled_accessibility_services"
    pass "binding stall publishes first observation without toggle"
}
```

- [ ] **Step 3: Add the remaining red lifecycle tests.**

Add `test_binding_stall_rebinds_once_at_threshold`, `test_binding_stall_resets_observation_after_unresolved_rebind`, `test_binding_stall_stops_after_maximum_rebinds`, `test_binding_stall_resets_budget_on_new_boot`, `test_binding_stall_clears_when_bound`, `test_binding_stall_rejects_unsafe_marker`, `test_status_reports_persistent_binding_stall`, and `test_uninstall_removes_binding_stall_marker_only`. Use threshold 2 and max 2. Assert one remove/restore pair at the threshold, marker `binding|fixture-boot|0|1` when still binding, no third toggle after the second attempt, reset to `binding|next-boot|1|0` after a boot change, marker removal after a bound observation, and no settings write for malformed or symlink evidence. The status test expects stale at observation 2 and enabled at observation 1. The uninstall test creates an accessibility transaction marker and proves it remains untouched.

- [ ] **Step 4: Register focused and full modes.**

Add the new tests to `--preview16-binding-only` and to `all` beside the existing binding diagnostic tests. Share the existing host/BusyBox dispatch.

- [ ] **Step 5: Run the red test.**

Run:

```bash
bash tools/test-yinxing-guard.sh --preview16-binding-only
```

Expected: the first test fails because Preview 15 has no stall marker. Do not change production code in this step.

- [ ] **Step 6: Commit the red tests.**

```bash
git add tools/test-yinxing-guard.sh
git commit -m "test: define accessibility binding stall preview 16"
```

### Task 2: Implement strict durable binding evidence

**Files:**
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh` constants and marker helpers.
- Test: focused binding tests.

**Interfaces:**
- Consumes: `STATE_DIR`, `current_guard_boot_id`, `ensure_state_dir`, `run_guard_command`, `HOME_MARKER_SYNC_COMMAND`, and `module_is_active`.
- Produces: `ACCESSIBILITY_BINDING_STALL_MARKER`, `read_accessibility_binding_stall()`, `write_accessibility_binding_stall()`, `clear_accessibility_binding_stall()`, `accessibility_binding_stall_threshold()`, `accessibility_binding_stall_max_rebinds()`, and `accessibility_binding_stall_is_persistent()`.

- [ ] **Step 1: Add constants and numeric override helpers.**

Define the marker beside `ACCESSIBILITY_TRANSACTION_MARKER`. Implement both configuration helpers so only decimal strings greater than zero are accepted and values above 100000 are capped; invalid input returns the documented defaults 2.

- [ ] **Step 2: Implement strict parsing.**

`read_accessibility_binding_stall()` requires a regular non-symlink file, exactly one newline-terminated line, the `binding|` prefix, a sanitized boot field no longer than 128 characters, and two decimal fields in range. Reject extra pipes, blank fields, extra lines, and values outside the range.

- [ ] **Step 3: Implement atomic write and clear.**

`write_accessibility_binding_stall(value)` validates first, refuses an existing symlink/directory, writes mode 0600 to `$MARKER.tmp.$$`, renames it, reads it back, runs the existing fixed sync command, and reads it back again. On failure remove only the temporary file. `clear_accessibility_binding_stall()` validates an existing marker before removal, syncs the state directory, and confirms absence.

- [ ] **Step 4: Add read-only persistence classification.**

`accessibility_binding_stall_is_persistent()` reads the marker and compares its boot id with `current_guard_boot_id`; it succeeds only when current-boot observations reach the threshold or attempts reach the maximum. It must not write or clear state so `status.sh` can call it safely.

- [ ] **Step 5: Run focused parser tests.**

Run host and recursive BusyBox modes:

```bash
bash tools/test-yinxing-guard.sh --preview16-binding-only
YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh --preview16-binding-only
```

- [ ] **Step 6: Commit marker primitives.**

```bash
git add root/kernelsu/yinxing_guard/bin/common.sh
git commit -m "feat: add durable accessibility stall evidence"
```

### Task 3: Integrate bounded observation and rebind behavior

**Files:**
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh` `repair_accessibility()`.
- Test: focused binding lifecycle tests.

**Interfaces:**
- Consumes: marker primitives from Task 2 and existing `rebind_accessibility_service()`.
- Produces: the Preview 16 repair state table from the design specification.

- [ ] **Step 1: Keep the threshold regression red.**

Run the focused test and confirm the second binding observation currently has zero settings writes. Keep this assertion as the gate.

- [ ] **Step 2: Add an internal observation helper.**

For a fully-enabled target, read the marker, reset boot-mismatched evidence to 0/0, increment observations, and publish the next marker. Below threshold return success without mutation. At threshold, refuse mutation if attempts are exhausted; otherwise publish the incremented attempt count before returning a distinct rebind-needed status. A publication failure before a would-be settings mutation returns failure.

- [ ] **Step 3: Route binding through the helper.**

In `repair_accessibility()`, preserve first-enable asynchronous behavior. For fully-enabled `binding`, invoke the helper; on rebind-needed, create the existing accessibility transaction and call `rebind_accessibility_service "$current" "$merged" "$enabled"` exactly once. Re-read binding afterward. Clear evidence on `bound`; for still-`binding` write observations 0 while retaining the attempt count. For `unknown`, `crashed`, or `unbound`, clear evidence and use the existing non-destructive/error path. Preserve all compensation and transaction cleanup.

- [ ] **Step 4: Handle non-binding transitions.**

Before existing `crashed` or `unbound` recovery, clear valid stall evidence. For `bound`, clear it and continue. For `unknown`, clear only a valid marker; a clear failure returns nonzero without changing settings. Malformed or symlink evidence is never replaced by a fresh counter.

- [ ] **Step 5: Run focused host and BusyBox tests.**

```bash
bash tools/test-yinxing-guard.sh --preview16-binding-only
YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh --preview16-binding-only
```

Expected: all lifecycle tests pass, including exactly two rebind attempts and no third toggle.

- [ ] **Step 6: Commit the state machine.**

```bash
git add root/kernelsu/yinxing_guard/bin/common.sh tools/test-yinxing-guard.sh
git commit -m "fix: recover persistent accessibility binding stalls"
```

### Task 4: Wire status and uninstall lifecycle

**Files:**
- Modify: `root/kernelsu/yinxing_guard/bin/status.sh`.
- Modify: `root/kernelsu/yinxing_guard/uninstall.sh`.
- Modify: `root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh`.
- Test: status and uninstall coverage in `tools/test-yinxing-guard.sh`.

**Interfaces:**
- Consumes: `accessibility_binding_stall_is_persistent()` and marker path.
- Produces: threshold-aware stale status and diagnostic-state cleanup.

- [ ] **Step 1: Make status read-only and threshold-aware.**

In the enabled branch of `accessibility_state()`, preserve stale for `crashed|unbound`; map `binding` to stale only when the read-only persistence helper succeeds. A first observation, invalid marker, boot-mismatched marker, or unavailable diagnostic retains existing enabled/unknown behavior.

- [ ] **Step 2: Remove diagnostic state on uninstall.**

Add the marker and `.tmp.*` glob to runtime-state removal lists in both uninstall scripts. Do not add it to any list that restores accessibility settings.

- [ ] **Step 3: Run lifecycle tests.**

```bash
bash tools/test-yinxing-guard.sh --status-only
bash tools/test-yinxing-guard.sh --preview16-binding-only
YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh --status-only
YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh --preview16-binding-only
```

- [ ] **Step 4: Commit lifecycle wiring.**

```bash
git add root/kernelsu/yinxing_guard/bin/status.sh root/kernelsu/yinxing_guard/uninstall.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh tools/test-yinxing-guard.sh
git commit -m "fix: expose and clean accessibility stall state"
```

### Task 5: Bump version and update release documentation

**Files:**
- Modify: `app/build.gradle.kts`.
- Modify: `root/kernelsu/yinxing_guard/module.prop`.
- Modify: both shell `MODULE_VERSION` literals.
- Modify: package assertions in `tools/test-yinxing-guard.sh`.
- Create: `docs/release/yinxing-root-preview-16.md`.

**Interfaces:**
- Consumes: completed shell behavior and test contracts.
- Produces: Preview 16 source metadata, release notes, and packaging assertions.

- [ ] **Step 1: Update exact version literals.**

Set APK `versionCode=32`, APK `versionName=1.10.0-root-preview.16`, module `versionCode=16`, module version string, and both shell `MODULE_VERSION` values to `1.10.0-root-preview.16`. Update package expectations from 15 to 16 while retaining generated test package name `9.9.9-test`.

- [ ] **Step 2: Write release notes.**

Document the state machine, threshold/max defaults, install and rollback steps, status values, verification commands and times, asset SHA-256 values after packaging, release URL after publication, and the explicit absence of a physical OnePlus device.

- [ ] **Step 3: Commit version and documentation.**

```bash
git add app/build.gradle.kts root/kernelsu/yinxing_guard/module.prop root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh tools/test-yinxing-guard.sh docs/release/yinxing-root-preview-16.md
git commit -m "chore: prepare root accessibility stall preview 16"
```

### Task 6: Complete verification and review

**Files:**
- Modify: `.planning/2026-08-07-android-build-verification/task_plan.md`.
- Modify: `.planning/2026-08-07-android-build-verification/findings.md`.
- Modify: `.planning/2026-08-07-android-build-verification/progress.md`.

**Interfaces:**
- Consumes: Preview 16 source and release assets.
- Produces: evidence-backed local verification and reviewer sign-off.

- [ ] **Step 1: Run static checks.**

Run `bash -n` and `busybox ash -n` for every module shell script, `git diff --check`, and fixed-command scans proving the APK allowlist still has only the three fixed paths.

- [ ] **Step 2: Run shell suites.**

Run focused modes, then `bash tools/test-yinxing-guard.sh all` and the same command with `YINXING_TEST_SHELL=busybox`; record wall/user/sys timing and PASS count.

- [ ] **Step 3: Run Android tests and build.**

Use the isolated cache and forced tasks:

```bash
env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home bash ./gradlew :app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon --console=plain
```

Parse every JUnit XML file for test/failure/error/skipped totals and inspect APK metadata, debug signature, and ZIP contents.

- [ ] **Step 4: Request review and resolve findings.**

Send the completed diff and verification output to the existing review agent. Treat Critical/Important findings as blocking; add a focused regression test for each fix and rerun affected suites.

- [ ] **Step 5: Package deterministic assets.**

Build the module ZIP with `tools/package-yinxing-guard.sh`, normalize ZIP timestamps using the established Preview 15 procedure, generate `SHA256SUMS.txt`, and verify embedded shell hashes match the source tree.

- [ ] **Step 6: Update planning evidence.**

Append final commit, timings, test totals, hashes, review result, release URL, and the no-device caveat to the three `.planning` files. Keep the Goal active and mark this iteration waiting for OnePlus 15 feedback.

### Task 7: Publish and verify the GitHub Release

**Remote artifacts:**
- `Gs-ygc/yinxing` `main`, feature branch, tag `v1.10.0-root-preview.16`, and prerelease assets.

**Interfaces:**
- Consumes: verified APK, KernelSU ZIP, and checksum file.
- Produces: an installable, checksum-verifiable, rollback-capable Preview 16 release.

- [ ] **Step 1: Push source and tag.**

Push the feature branch and `main` to `https://github.com/Gs-ygc/yinxing.git`, create annotated tag `v1.10.0-root-preview.16` at the published commit, and verify remote branch/tag equality with `git ls-remote`.

- [ ] **Step 2: Create the prerelease.**

Use `gh release create --repo Gs-ygc/yinxing v1.10.0-root-preview.16` with the Debug APK, KernelSU ZIP, checksum file, and Preview 16 release notes. Keep it prerelease and state fixed-device scope and rollback commands.

- [ ] **Step 3: Download and verify fresh assets.**

Download all assets into a new temporary directory, run `sha256sum -c`, `cmp` each binary against the local file, `unzip -t` the module, and rerun APK metadata/signature checks. Record release JSON with `isPrerelease=true` and the expected target commit.

- [ ] **Step 4: Final handoff.**

Report URL, assets, verification results, build/test times, install/rollback sequence, and no-device limitation in Chinese. End with the required XML options block and leave the Goal active for real-device feedback.
