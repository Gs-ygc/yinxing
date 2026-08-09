# Root HOME Resolver Confirmation Preview 15 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the fixed Root Guard report and repair the Activity that actually resolves the user-0 HOME intent, while preserving strict fail-closed and rollback behavior.

**Architecture:** Keep `cmd role get-role-holders` as the ownership source and add one fixed `cmd package resolve-activity --brief --components` probe through the existing BusyBox timeout wrapper. Fold the probe into the existing schema-2 `home` state and HOME transaction confirmation; do not add an APK command or a new public field. Mirror the read/confirmation helper in the standalone uninstall script so recovery remains retryable after module removal.

**Tech Stack:** POSIX `/system/bin/sh`, KernelSU BusyBox 1.36.1, Bash fixture harness, Kotlin/JUnit 4, Gradle 9.3.1, Android SDK 36, GitHub CLI.

## Global Constraints

- Target only the managed OnePlus 15 China ColorOS 16, KernelSU, Root, Android user 0.
- Root commands remain fixed and allowlisted; no arbitrary shell, user arguments, coordinates, process selection, private ColorOS APIs, or new APK Root path.
- All Android commands continue through `run_guard_command` and the existing bounded process-group timeout.
- Unknown, malformed, multi-line, sentinel-alias, or timed-out resolver output is never interpreted as a package or mutation target.
- Existing accessibility, Doze, transaction-lock, caregiver-choice, and uninstall retry behavior must remain green.
- Version `1.10.0-root-preview.15`, app `versionCode=31`, module `versionCode=15`; Debug APK only unless a real release keystore appears.
- `.planning/` is user-owned untracked state and is never committed.

### Task 1: Add resolver fixtures and RED regressions

**Files:**
- Modify: `tools/test-yinxing-guard.sh:181-195` fake `cmd`, fixture reset and healthy setup helpers, status/Guard test registration near the mode dispatch at the end of the file.
- Test: `tools/test-yinxing-guard.sh` (new resolver-focused shell tests).

**Interfaces:**
- Produces fixture file `$TEST_ROOT/home_resolved_component` and controls `fail_home_resolver_query`, `hang_home_resolver_query`, `malformed_home_resolver_output`, and `ignore_home_resolver_set` for later tasks.
- The fake `cmd package resolve-activity` must log the exact command, emit the fixture or a derived component, and return the configured failure/timeout without changing role state.

- [ ] **Step 1: Extend the fake command and fixture reset without production changes.**

Add a `resolve-activity` branch before the existing `set-home-activity` branch. With `--components`, emit one component line derived from `$HOME_HOLDER` when no fixture is present (`com.yinxing.launcher/.feature.home.MainActivity` for Yinxing and `<holder>/.Launcher` otherwise); emit `No activity found` for an empty holder. Add the resolver controls and fixture file to `reset_fixture`, and make the set-home fake update the resolver fixture atomically with the holder.

- [ ] **Step 2: Add the strict parser and behavior tests before changing production code.**

Add tests that currently fail because no resolver helper exists:

```bash
test_home_resolver_target_is_owned() {
    reset_fixture
    printf 'com.yinxing.launcher/.feature.home.MainActivity\n' > "$TEST_ROOT/home_resolved_component"
    assert_equals target "$(read_home_resolved_component)" "target resolver component"
    assert_equals owned "$(home_role_state)" "target resolver state"
}

test_home_resolver_mismatch_is_degraded_and_repaired() {
    reset_fixture
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    printf 'com.oplus.launcher/.Launcher\n' > "$TEST_ROOT/home_resolved_component"
    repair_state || fail "known resolver mismatch should be repaired"
    assert_equals 'com.yinxing.launcher/.feature.home.MainActivity' \
        "$(tr -d '\n' < "$TEST_ROOT/home_resolved_component")" "resolver repair"
    assert_equals owned "$(home_role_state)" "repaired resolver state"
}

test_home_resolver_unknown_is_safe() {
    reset_fixture
    printf 'com.yinxing.launcher\n' > "$HOME_HOLDER"
    touch "$TEST_ROOT/fail_home_resolver_query"
    if repair_state; then fail "unknown resolver must not report repair success"; fi
    assert_not_contains "$CALLS" "cmd package set-home-activity"
}
```

Also cover `No activity found`, fully qualified target class, invalid package,
two lines/trailing blank, and a one-second stalled resolver; assert bounded
completion, no speculative `set-home-activity`, and `home=unknown` in status
when evidence is unavailable. Register parser/recovery tests in
`--guard-only`, status-only assertions in `--status-only`, and both groups in
the `all` branch. Run the focused red tests:

```bash
bash tools/test-yinxing-guard.sh --guard-only
```

Expected: FAIL at the first resolver assertion with the helper/state missing.

- [ ] **Step 3: Commit the red test harness.**

```bash
git add tools/test-yinxing-guard.sh
git commit -m "test: define root home resolver contract"
```

### Task 2: Implement strict bounded resolver parsing

**Files:**
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh` near `valid_android_package_name`, `read_home_role_holder`, and `home_role_state`.
- Test: `tools/test-yinxing-guard.sh` resolver tests from Task 1.

**Interfaces:**
- Produces `read_home_resolved_component()` returning a validated component line or the literal `none`; it returns nonzero for command failure or malformed evidence.
- Produces `home_resolver_state()` returning `target`, `other`, or `none`; it returns nonzero for unknown evidence.

- [ ] **Step 1: Implement the minimal fixed command and exact line framing.**

Run only:

```sh
cmd package resolve-activity --brief --components --user "$ANDROID_USER_ID" \
    -a android.intent.action.MAIN -c android.intent.category.HOME
```

Capture the command status with the existing `|` sentinel pattern. Remove
exactly one final newline; reject an empty post-trim value unless it is the
successful `No activity found` line. Reject any remaining newline, `|`, `null`,
`NULL`, whitespace-only value, or more than one slash.

- [ ] **Step 2: Add component validation and target normalization.**

Validate the package prefix with `valid_android_package_name`, require a
non-empty class token containing only Android component characters, and accept
only the known short or fully qualified Yinxing target as `target`. Return
`other` only for a structurally valid non-target component. Keep all parsing
inside shell variables; do not use unbounded `grep`/`sed` pipelines on command
output.

- [ ] **Step 3: Run focused tests and then commit the green parser.**

```bash
bash tools/test-yinxing-guard.sh --guard-only
git diff --check
git add root/kernelsu/yinxing_guard/bin/common.sh tools/test-yinxing-guard.sh
git commit -m "feat: verify resolved home activity"
```

Expected: parser tests pass while existing role-only tests remain green.

### Task 3: Integrate resolver state into HOME repair and status

**Files:**
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh` (`home_role_state`, `repair_home_role_locked`, post-set confirmation).
- Modify: `root/kernelsu/yinxing_guard/bin/status.sh` only if a small helper call is needed; preserve the nine-line schema-2 contract.
- Test: `tools/test-yinxing-guard.sh` status and HOME lifecycle regressions.

**Interfaces:**
- `home_role_state()` returns existing public values `owned|other|none|unknown`, with `owned` requiring role plus resolver target.
- `repair_home_role_locked()` must not mark a takeover `owned` or call `launch_home` until both confirmations succeed.

- [ ] **Step 1: Add RED assertions for role-owned route mismatch and takeover confirmation.**

Extend the tests so a role-owned Yinxing with a known other resolver invokes
the fixed `set-home-activity` once without creating
`home_previous_holder`; a takeover with `ignore_home_resolver_set` or a
post-set resolver mismatch fails, retains `pending` evidence, and does not
write `home_launched`. Add a status test proving role-owned plus unknown
resolver emits `home=unknown`.

- [ ] **Step 2: Make `home_role_state()` composite and fail closed.**

Preserve `other` and `none` directly from the role query. For Yinxing, call the
resolver helper and map `target -> owned`, `other -> other`, `none -> none`,
failure -> `unknown`. Do not mutate state from this status path.

- [ ] **Step 3: Gate every HOME mutation confirmation on the resolver.**

When current role is Yinxing, repair only a known `other`/`none` route with the
existing fixed component command, then re-read both role and resolver. For a
new takeover, retain all existing pending/marker comparisons and add the
resolver target check alongside the role check before promoting `owned`.
Unknown evidence returns failure without a new write and leaves durable
evidence intact. Ensure `launch_home` is reached only after the combined repair
returns success.

- [ ] **Step 4: Run the focused red/green suite and commit.**

```bash
bash tools/test-yinxing-guard.sh --status-only
bash tools/test-yinxing-guard.sh --guard-only
bash tools/test-yinxing-guard.sh --review-regressions-only
git add root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/status.sh tools/test-yinxing-guard.sh
git commit -m "fix: gate home recovery on resolved activity"
```

### Task 4: Mirror safe resolver confirmation in uninstall cleanup

**Files:**
- Modify: `root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh` (`read_home_resolved_component`, restore confirmation).
- Test: `tools/test-yinxing-guard.sh` uninstall HOME lifecycle tests.

**Interfaces:**
- Cleanup helper uses the same fixed command and parser rules but remains self-contained after the module directory disappears.
- Explicit known route mismatch/none keeps markers and the helper for retry; unknown resolver never selects a new rollback target.

- [ ] **Step 1: Add RED cleanup tests.**

Add a restore test where role confirmation says the previous package but the
resolver remains Yinxing/other; require cleanup to exit nonzero and preserve
the HOME markers. Add malformed and timeout tests with no extra HOME mutation.

- [ ] **Step 2: Copy the minimal parser and add post-restore route checking.**

Keep constants and validation local to `uninstall-cleanup.sh`; after a fixed
restore command, require role confirmation as today, then inspect the resolver.
Known non-target/none is a retryable failure. Unknown/malformed output leaves
the role restore in place but retains evidence; do not remove the helper.

- [ ] **Step 3: Run lifecycle and full shell tests, then commit.**

```bash
bash tools/test-yinxing-guard.sh --home-lifecycle-only
bash tools/test-yinxing-guard.sh --review-regressions-only
bash tools/test-yinxing-guard.sh all
git add root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh tools/test-yinxing-guard.sh
git commit -m "fix: verify home route during rollback"
```

### Task 5: Bump Preview 15 metadata and release documentation

**Files:**
- Modify: `app/build.gradle.kts` (`versionCode=31`, `versionName=1.10.0-root-preview.15`).
- Modify: `root/kernelsu/yinxing_guard/module.prop` (`versionCode=15`, version string).
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh` and `bin/uninstall-cleanup.sh` module version strings.
- Modify: `tools/test-yinxing-guard.sh` packager expectations from 14 to 15.
- Create: `docs/release/yinxing-root-preview-15.md` with install/rollback, fixed resolver behavior, AOSP command basis, test/build timings, hashes, and no-device caveat.
- Test: existing `RootHealthSnapshotTest`, `SettingsActivitySmokeTest`, shell package tests.

- [ ] **Step 1: Update version fixtures and add release-note skeleton.**

Keep the APK schema parser backward-compatible with schema 1/2; only version
fixtures and release copy change. State explicitly that Preview 15 is a Debug
APK, requires module-before-APK installation, and must be fully uninstalled
before downgrade.

- [ ] **Step 2: Run metadata/package tests and commit the version/docs change.**

```bash
bash tools/test-yinxing-guard.sh --package-only
git diff --check
git add app/build.gradle.kts root/kernelsu/yinxing_guard/module.prop root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh tools/test-yinxing-guard.sh docs/release/yinxing-root-preview-15.md
git commit -m "chore: bump root preview 15 metadata"
```

### Task 6: Full verification, packaging, and GitHub Release

**Files:**
- Modify: `docs/release/yinxing-root-preview-15.md` with final evidence only.
- Create: `out/release/yinxing-1.10.0-root-preview.15-debug.apk`, `out/release/yinxing-guard-1.10.0-root-preview.15.zip`, and `out/release/SHA256SUMS.txt` as local release artifacts (do not commit generated binaries unless repository policy requires it).

- [ ] **Step 1: Run syntax/scans and the complete module matrix.**

```bash
bash -n root/kernelsu/yinxing_guard/service.sh root/kernelsu/yinxing_guard/action.sh root/kernelsu/yinxing_guard/uninstall.sh root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/guard.sh root/kernelsu/yinxing_guard/bin/status.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh root/kernelsu/yinxing_guard/bin/kiosk-home.sh
time bash tools/test-yinxing-guard.sh all
```

Record exit 0, host/recursive BusyBox pass counts, and elapsed time.

- [ ] **Step 2: Run Android tests and forced Debug build with shared cache.**

```bash
time GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
    bash ./gradlew :app:testDebugUnitTest :app:assembleDebug \
    --rerun-tasks --no-daemon --console=plain
```

Record exact Gradle task result and test totals; do not pipe away the exit code.

- [ ] **Step 3: Package and inspect deterministic KernelSU assets.**

```bash
bash tools/package-yinxing-guard.sh out/release/yinxing-guard-1.10.0-root-preview.15.zip 1.10.0-root-preview.15
cp app/build/outputs/apk/debug/app-debug.apk out/release/yinxing-1.10.0-root-preview.15-debug.apk
sha256sum out/release/yinxing-1.10.0-root-preview.15-debug.apk out/release/yinxing-guard-1.10.0-root-preview.15.zip > out/release/SHA256SUMS.txt
```

Verify ZIP layout/modes/timestamps and byte-identical deterministic repacking;
verify APK package/version with `aapt2 dump badging` and Debug v2 signature
with `apksigner verify --verbose`.

- [ ] **Step 4: Review exact final tree and publish source/ref.**

Run `git diff --check`, inspect `git status`, commit any final release-note
timing/hash update, then push the feature branch and fast-forward `main` on
`origin`. Create annotated tag `v1.10.0-root-preview.15` and push it.

- [ ] **Step 5: Publish and remotely verify the prerelease.**

Use `gh release create v1.10.0-root-preview.15 --prerelease` with the APK,
module ZIP, and `SHA256SUMS.txt`. Verify `gh release view --json`, remote refs,
asset sizes/digests, fresh downloads, checksum equality, ZIP integrity, APK
metadata/signature, and the exact release URL before reporting the build.

- [ ] **Step 6: Update persistent planning state without committing it.**

Append the final source commit, tag, release URL, test/build timings, artifact
hashes, and the explicit empty `adb devices -l` result to
`.planning/2026-08-07-android-build-verification/progress.md`; mark the new
phase complete locally while keeping the long-running Goal active and the
device-feedback phase open.
