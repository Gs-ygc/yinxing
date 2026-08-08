# Root Guard Owner Recheck Preview 6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the KernelSU Root Guard supervisor alive after a duplicate-owner exit so it can reclaim a dead owner and restore the existing repair loop.

**Architecture:** Preserve `bin/guard.sh` as the only lock owner and leave its exit behavior unchanged. Extend `service.sh` with a validated owner-recheck delay; status `0` becomes a low-frequency retry, status `75` keeps the existing short retry, and other failures keep Preview 5's diagnostic/backoff path. The host/BusyBox harness proves a live owner disappearing and the supervisor taking ownership.

**Tech Stack:** POSIX shell / KernelSU BusyBox `ash`, host Bash harness, `zip`, Android Gradle/Kotlin Debug build, GitHub CLI.

## Global Constraints

- Target remains the user-controlled OnePlus 15 China ColorOS 16 KernelSU device.
- Do not change `guard.sh` lock creation, PID validation, or dead-owner reclamation.
- Do not add arbitrary Root shell commands, coordinate input, package allowlists, or system-image changes.
- Module state (`disable`/`remove`/directory absence) must stop the supervisor before another Guard launch.
- Release assets must be a Debug APK, deterministic KernelSU ZIP, and basename-only SHA-256 file.

---

### Task 1: Add the owner-disappearance regression test

**Files:**
- Modify: `tools/test-yinxing-guard.sh:528-557` and the `--guard-only`/`all` dispatch lists
- Test fixture only: existing `$TEST_ROOT/state/guard.lock` and fake command environment

**Interfaces:**
- Consumes: current `service.sh` behavior and the existing lock fixture helpers.
- Produces: `test_service_reclaims_lock_after_owner_disappears`, an observable test that requires a second Guard launch after the first status-0 duplicate-owner result.

- [ ] **Step 1: Write the failing test**

Add a test that creates an active current-boot lock, starts a helper process that removes the lock after a short real delay while staying alive, then invokes `service.sh` with `YINXING_GUARD_OWNER_RETRY_SECONDS=0`, `YINXING_GUARD_LOCK_RETRY_SECONDS=0`, `YINXING_GUARD_BOOT_WAIT_SECONDS=0`, `YINXING_GUARD_INTERVAL_SECONDS=0`, and `YINXING_GUARD_MAX_CYCLES=1`. Poll `CALLS` for `am start`, assert it appears exactly once, and clean up the helper PID.

```bash
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
    pass "service reclaims lock after owner disappears"
}
```

Register it immediately after `test_service_restarts_non_lock_guard_failure` in both dispatch paths.

- [ ] **Step 2: Run the focused harness and verify RED**

Run:

```bash
bash tools/test-yinxing-guard.sh --guard-only
```

Expected: the existing Preview 5 implementation fails with `service did not reclaim lock after owner disappeared`, while the prior guard tests remain green.

- [ ] **Step 3: Commit the failing test**

```bash
git add tools/test-yinxing-guard.sh
git commit -m "test: cover root guard owner recheck"
```

### Task 2: Implement bounded owner recheck in the supervisor

**Files:**
- Modify: `root/kernelsu/yinxing_guard/service.sh:10-45`
- Test: `tools/test-yinxing-guard.sh` from Task 1

**Interfaces:**
- Consumes: `YINXING_GUARD_OWNER_RETRY_SECONDS` and `module_is_active()`.
- Produces: a supervisor that retries status `0` after a validated owner delay and retains all Preview 5 branches unchanged.

- [ ] **Step 1: Add numeric owner-delay parsing**

Immediately after `RESTART_SECONDS` parsing, add:

```sh
OWNER_RETRY_SECONDS=${YINXING_GUARD_OWNER_RETRY_SECONDS:-30}
case "$OWNER_RETRY_SECONDS" in
    ''|*[!0-9]*) OWNER_RETRY_SECONDS=30 ;;
esac
```

- [ ] **Step 2: Change only the status-0 branch**

Replace the `0) exit 0 ;;` branch with:

```sh
            0)
                sleep "$OWNER_RETRY_SECONDS"
                ;;
```

Keep the module-state check before the `case`, the `75` lock retry, and the unexpected-failure diagnostic/backoff byte-for-byte equivalent.

- [ ] **Step 3: Run the focused harness and verify GREEN**

Run both shells:

```bash
bash tools/test-yinxing-guard.sh --guard-only
YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh --guard-only
```

Expected: all guard, retry, owner-reclaim, disable/remove, cleanup, and action cases pass with exit code 0.

- [ ] **Step 4: Run syntax and diff checks**

```bash
for file in root/kernelsu/yinxing_guard/service.sh root/kernelsu/yinxing_guard/action.sh root/kernelsu/yinxing_guard/uninstall.sh root/kernelsu/yinxing_guard/bin/*.sh; do sh -n "$file"; done
git diff --check
```

- [ ] **Step 5: Commit the implementation**

```bash
git add root/kernelsu/yinxing_guard/service.sh tools/test-yinxing-guard.sh
git commit -m "fix: keep root guard supervisor after duplicate owner"
```

### Task 3: Version Preview 6 and prepare release notes

**Files:**
- Modify: `app/build.gradle.kts` (`versionCode=22`, `versionName=1.10.0-root-preview.6`)
- Modify: `root/kernelsu/yinxing_guard/module.prop` (`version=1.10.0-root-preview.6`, `versionCode=6`)
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh` and `bin/uninstall-cleanup.sh` module version constants
- Modify: `tools/test-yinxing-guard.sh` package expectations
- Create: `docs/release/yinxing-root-preview-6.md`

**Interfaces:**
- Consumes: the tested supervisor behavior and Preview 5 release/rollback wording.
- Produces: version-matched APK/module metadata and acceptance notes with placeholders forbidden; hashes are filled after packaging.

- [ ] **Step 1: Bump version metadata and fixtures**

Update only the Preview 5 literals to Preview 6 and increment both version codes by one. Keep package ID, module ID, and all fixed Root paths unchanged.

- [ ] **Step 2: Write acceptance notes**

Document the owner-recheck behavior, install order (APK then KernelSU ZIP then reboot), Debug-signing limitation, rollback to Preview 5, no-device boundary, and checks for module disable/remove plus owner disappearance. State that the supervisor does not force the launcher while another app is intentionally active.

- [ ] **Step 3: Run version/package tests**

```bash
bash tools/test-yinxing-guard.sh --package-only
```

Expected: package version `1.10.0-root-preview.6`, `versionCode=6`, fixed root layout, modes, and normalized timestamps all pass.

- [ ] **Step 4: Commit version and notes**

```bash
git add app/build.gradle.kts root/kernelsu/yinxing_guard tools/test-yinxing-guard.sh docs/release/yinxing-root-preview-6.md
git commit -m "release: prepare root automation preview 6"
```

### Task 4: Full verification, packaging, and remote release

**Files:**
- Create (ignored): `.tmp_preview/root-preview-6/*`
- Modify (local only): `.planning/2026-08-07-android-build-verification/*`

**Interfaces:**
- Consumes: the final Preview 6 commit and module packager.
- Produces: pushed `main`, annotated `v1.10.0-root-preview.6`, GitHub prerelease with APK/module/checksums, and fresh remote-download evidence.

- [ ] **Step 1: Run module and syntax verification**

```bash
bash tools/test-yinxing-guard.sh
YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh
```

Require both exit 0 and rerun `sh -n`, `bash -n`, BusyBox `ash -n`, and `git diff --check` for every module script.

- [ ] **Step 2: Run the forced Android verification**

```bash
/usr/bin/time -p env JAVA_TOOL_OPTIONS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888' \
  GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon --console=plain
```

Require direct exit 0, `BUILD SUCCESSFUL`, and report summed XML totals.

- [ ] **Step 3: Generate and inspect assets**

Copy `app/build/outputs/apk/debug/app-debug.apk` to `yinxing-1.10.0-root-preview.6-debug.apk`, package the module with `tools/package-yinxing-guard.sh`, and create `SHA256SUMS.txt` from inside the asset directory so it contains basenames. Verify `sha256sum -c`, both `unzip -t` checks, `aapt2 dump badging`, `apksigner verify --verbose` (v2 true), root ZIP entries, executable modes, and normalized timestamps.

- [ ] **Step 4: Push source, tag, and release**

Fast-forward `main`, push `origin main`, create annotated tag `v1.10.0-root-preview.6`, push the tag, and run:

```bash
gh release create v1.10.0-root-preview.6 --repo Gs-ygc/yinxing \
  --title '银杏 Root 保活监督预览 6' \
  --notes-file docs/release/yinxing-root-preview-6.md --prerelease \
  .tmp_preview/root-preview-6/yinxing-1.10.0-root-preview.6-debug.apk \
  .tmp_preview/root-preview-6/yinxing-guard-1.10.0-root-preview.6.zip \
  .tmp_preview/root-preview-6/SHA256SUMS.txt
```

- [ ] **Step 5: Fresh remote verification**

Download all three assets into a new temporary directory, run checksum/archive/layout/metadata/signature checks again, assert the Release is prerelease and not draft, and confirm `origin/main` plus the peeled tag point to the release commit.

- [ ] **Step 6: Update persistent logs**

Append exact Preview 6 tests, timing, hashes, release URL, remote verification, and the owner-race finding to `.planning/2026-08-07-android-build-verification/{task_plan,progress,findings}.md`. Keep `.planning/` uncommitted and leave the goal active for device feedback.

