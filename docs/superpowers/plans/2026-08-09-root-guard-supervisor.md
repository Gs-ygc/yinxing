# Root Guard Supervisor Preview 5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the KernelSU Root Guard repairing the launcher after transient late-boot failures by supervising and safely restarting its existing guard loop.

**Architecture:** Extend the module's existing `service.sh` background loop into a small supervisor. It will classify guard exit codes, use a bounded restart backoff for unexpected failures, and stop when the module is disabled or removed. The existing `guard.sh` lock and fixed repair commands remain unchanged.

**Tech Stack:** POSIX shell / KernelSU BusyBox `ash`, host Bash harness, `zip`, Android Gradle/Kotlin Debug build.

## Global Constraints

- Preserve the fixed Root allowlist: `settings`, `pm`, `cmd deviceidle`, `cmd appops`, and the fixed `am start` component only.
- Keep `service.sh` non-blocking and do not add arbitrary shell execution or firmware/system-app changes.
- Treat exit code `75` as the existing incomplete-lock retry path; treat exit code `0` as a deliberate stop; restart other non-zero failures after a bounded delay.
- Stop retrying when `$MODDIR` is absent or contains `disable` or `remove`.
- Run host and recursive `ASH_STANDALONE=1` module suites, shell syntax checks, Android unit tests, and a forced Debug build before release.
- Publish a Debug APK and KernelSU module ZIP with checksums, acceptance notes, and rollback to Preview 4.

---

### Task 1: Add Red Supervisor Tests

**Files:**
- Modify: `tools/test-yinxing-guard.sh:494-523`

**Interfaces:**
- Consumes: existing fake Android commands, `run_module_script`, and module fixture state.
- Produces: regression coverage proving a non-75 guard failure is retried and a disabled/removing module is not restarted.

- [ ] **Step 1: Write the failing restart test**

Add `test_service_restarts_non_lock_guard_failure` immediately after the existing incomplete-lock service test. Seed `package_missing_once`, set `YINXING_GUARD_BOOT_WAIT_SECONDS=0`, `YINXING_GUARD_INTERVAL_SECONDS=0`, `YINXING_GUARD_MAX_CYCLES=1`, and `YINXING_GUARD_RESTART_SECONDS=0`; run `service.sh` in the current test shell and poll `CALLS` until `am start` appears. Assert exactly one successful HOME launch and that the fake `pm path` was called at least twice.

- [ ] **Step 2: Write the failing stop test**

Add `test_service_stops_when_module_is_disabled_after_failure`. Seed `package_missing_once`, run a background helper that waits for the first `pm path` call and creates `$TEST_ROOT/modules/yinxing_guard/disable`, then run `service.sh` with zero retry delay. Assert one failed `pm path` attempt, no `am start`, and that the service command returns without leaving a retry process.

- [ ] **Step 3: Run the focused harness and observe RED**

Run the full host harness:

```bash
bash tools/test-yinxing-guard.sh
```

Expected: the new restart assertion fails because the current supervisor exits after the first non-75 failure; record the exact failing test name before implementing the loop.

- [ ] **Step 4: Commit the red tests**

```bash
git add tools/test-yinxing-guard.sh
git commit -m "test: cover root guard supervisor restart"
```

### Task 2: Implement the Supervisor Loop

**Files:**
- Modify: `root/kernelsu/yinxing_guard/service.sh:7-22`

**Interfaces:**
- Consumes: `MODULE_DIR` state, existing `LOCK_RETRY_SECONDS`, and `log_event` from `bin/common.sh`.
- Produces: `module_is_active` and a supervisor loop that restarts non-zero guard failures with `YINXING_GUARD_RESTART_SECONDS` (default `30`).

- [ ] **Step 1: Add numeric restart-delay parsing and module state check**

Implement `module_is_active()` with directory/`disable`/`remove` checks. Parse `YINXING_GUARD_RESTART_SECONDS` using the same digits-only fallback style as `LOCK_RETRY_SECONDS`; invalid values use `30`.

- [ ] **Step 2: Replace the one-shot retry condition**

Keep the existing background subshell, but use this exit classification:

```sh
while module_is_active; do
    sh "$MODDIR/bin/guard.sh"
    guard_status=$?
    module_is_active || exit 0
    case "$guard_status" in
        0) exit 0 ;;
        75) sleep "$LOCK_RETRY_SECONDS" ;;
        *) log_event "guard_unexpected_exit=$guard_status"; sleep "$RESTART_SECONDS" ;;
    esac
done
```

Do not call any new privileged command. Preserve the existing detached background behavior and redirect supervisor output.

- [ ] **Step 3: Run the full harness and observe GREEN**

Run `bash tools/test-yinxing-guard.sh` and then `YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh`. Expected: both new tests pass in host and standalone BusyBox modes.

- [ ] **Step 4: Commit the implementation**

```bash
git add root/kernelsu/yinxing_guard/service.sh
git commit -m "fix: supervise transient root guard failures"
```

### Task 3: Version and Release Documentation

**Files:**
- Modify: `app/build.gradle.kts:46-47` (set `versionCode=21`, `versionName="1.10.0-root-preview.5"`)
- Modify: `root/kernelsu/yinxing_guard/module.prop:3-4` (set version and `versionCode=5`)
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh:9`
- Modify: `root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh:6`
- Modify: `tools/test-yinxing-guard.sh:717-722` (update source and generated package version assertions)
- Create: `docs/release/yinxing-root-preview-5.md`

**Interfaces:**
- Consumes: the supervisor behavior and final test/build timing.
- Produces: a versioned, rollback-capable release note with asset names, installation order, safety boundaries, and final SHA-256 values.

- [ ] **Step 1: Bump versions and fixture expectations**

Use `versionCode=21`, `versionName=1.10.0-root-preview.5`, module `versionCode=5`, and `MODULE_VERSION="1.10.0-root-preview.5"` in both module scripts. Update both the source-version assertion and the generated package's expected `versionCode` from 4 to 5; keep the generated test version name `9.9.9-test` unchanged.

- [ ] **Step 2: Write acceptance notes after artifact generation**

Document the transient-failure supervisor, disable/remove stop behavior, fixed Root boundary, exact test/build results, install order (APK then KernelSU ZIP then reboot), Preview 4 rollback, and the statement that no OnePlus 15 is connected to the build host.

- [ ] **Step 3: Commit versioned source and notes**

```bash
git add app/build.gradle.kts root/kernelsu/yinxing_guard tools/test-yinxing-guard.sh docs/release/yinxing-root-preview-5.md
git commit -m "release: prepare root automation preview 5"
```

### Task 4: Full Verification and Release

**Files:**
- Create (ignored): `.tmp_preview/root-preview-5/*`
- Modify (local only): `.planning/2026-08-07-android-build-verification/*`

**Interfaces:**
- Consumes: final source commit and module packager.
- Produces: pushed `main`, annotated `v1.10.0-root-preview.5`, GitHub prerelease with APK/module/checksums, and fresh remote-download evidence.

- [ ] **Step 1: Run module and syntax verification**

Run `bash tools/test-yinxing-guard.sh` and `YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh`, then `sh -n` and `bash -n` for every module script and `git diff --check`. Require exit 0.

- [ ] **Step 2: Run the forced Android verification**

Run:

```bash
/usr/bin/time -p env JAVA_TOOL_OPTIONS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888' \
  GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon --console=plain
```

Require direct exit 0, `BUILD SUCCESSFUL`, and report the summed test XML totals.

- [ ] **Step 3: Generate and inspect release assets**

Copy `app/build/outputs/apk/debug/app-debug.apk` to the versioned asset name, run `tools/package-yinxing-guard.sh` with the Preview 5 version, create `SHA256SUMS.txt`, and verify with `sha256sum -c`, `unzip -t`, `aapt2 dump badging`, and `apksigner verify --verbose` (v2 expected for Debug).

- [ ] **Step 4: Commit final notes, push, and tag**

After inserting final hashes/timing into the release note, commit it, fast-forward `main`, push `origin main`, create annotated tag `v1.10.0-root-preview.5`, and push the tag.

- [ ] **Step 5: Create and remotely verify the Release**

Use `gh release create --prerelease` with the APK, module ZIP, checksums, and release note. Download all assets into a fresh `mktemp -d`, run checksum/archive/layout/signature checks again, and confirm `origin/main` and the peeled tag point to the release commit.

- [ ] **Step 6: Update persistent logs**

Mark the Preview 5 phase complete/awaiting device feedback in `task_plan.md`, append exact commands/results and hashes to `progress.md`, and record the supervisor decision and any test harness caveats in `findings.md`. Keep `.planning/` uncommitted.
