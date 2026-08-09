# Root Guard Owner Identity Recovery Preview 8 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with verification checkpoints.

**Goal:** Make same-boot Root Guard locks resilient to PID reuse without killing unrelated processes, then publish Preview 8.

**Architecture:** Add a `/proc/<pid>/stat` start-time helper in the shared shell library. Guard writes the token before the PID, uses token-aware stale-lock reclamation, and status uses the same comparison to report `guard=stale`. Legacy or unreadable identity evidence remains conservative and keeps the existing owner-active behavior.

**Tech Stack:** POSIX `/system/bin/sh`, standalone BusyBox `ash`, `awk`, Android `/proc`, Bash test harness, Kotlin/JUnit parser tests, Gradle 9.3.1, Android SDK 36.

## Global Constraints

- Keep the Root surface fixed to the existing `status.sh` and `action.sh` APK bridge.
- Never kill or signal an unrelated process; `kill -0` remains the only liveness probe.
- Preserve lock exit statuses `0`, `75`, `76`, and the existing non-lock retry behavior.
- Treat missing or unreadable `/proc` data and legacy locks without `start_time` as conservative owner-active evidence.
- Keep the eight-line health snapshot schema unchanged.
- All release artifacts are Debug APK + KernelSU ZIP with basename-only SHA-256 checksums.

---

### Task 1: Add red lock identity tests

**Files:**
- Modify: `tools/test-yinxing-guard.sh` fake fixtures, reset logic, and guard/status tests.

**Interfaces:**
- Consumes: current Preview 7 lock layout under `$YINXING_GUARD_STATE_DIR/guard.lock/<boot>`.
- Produces: failing tests for PID reuse, lock token publication, conservative unreadable identity, and stale status.

- [ ] **Step 1: Add a deterministic proc-stat fixture helper.**

Add a `write_proc_stat` helper after the fake command setup for the one test
that needs a readable synthetic stat file:

```bash
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
```

Reset must remove `$TEST_ROOT/proc`. Do not export the fake proc root globally:
normal tests must read the host's real `/proc`; individual unreadable-evidence
tests set `YINXING_GUARD_PROC_ROOT="$TEST_ROOT/proc"` only for their command.

- [ ] **Step 2: Write the failing PID-reuse test.**

Add `test_guard_reclaims_live_pid_with_mismatched_start_time`:

```bash
reset_fixture
printf 'same-boot-id\n' > "$TEST_ROOT/boot_id"
mkdir -p "$TEST_ROOT/state/guard.lock/same-boot-id"
/bin/sleep 30 &
LIVE_PID=$!
printf '%s\n' "$LIVE_PID" > "$TEST_ROOT/state/guard.lock/same-boot-id/pid"
printf 'same-boot-id\n' > "$TEST_ROOT/state/guard.lock/same-boot-id/boot_id"
write_proc_stat "$LIVE_PID" 111
YINXING_GUARD_BOOT_ID_FILE="$TEST_ROOT/boot_id" \
    YINXING_GUARD_BOOT_WAIT_SECONDS=0 \
    YINXING_GUARD_INTERVAL_SECONDS=0 \
    YINXING_GUARD_MAX_CYCLES=1 \
    run_module_script "$MODULE_ROOT/bin/guard.sh"
assert_equals "1" "$(grep -c '^am start ' "$CALLS" || true)" \
    "PID reuse must reclaim the stale lock"
kill "$LIVE_PID" 2>/dev/null || true
wait "$LIVE_PID" 2>/dev/null || true
LIVE_PID=""
pass "guard reclaims live PID with mismatched start time"
```

The Preview 7 code must fail this assertion by returning `76` before the
health cycle.

- [ ] **Step 3: Add token publication and conservative checks.**

Add tests that a normal one-cycle Guard writes a non-empty `start_time`, a lock
with a matching current token read from the live host `/proc` returns `76` and
performs no HOME launch, and a live PID whose current stat is absent still
returns `76` rather than reclaiming when the command sets the empty fake proc
root.

- [ ] **Step 4: Add stale status coverage and register all tests.**

Prepare a healthy status fixture with a live PID and a mismatched token; assert
`guard=stale`. Register all new tests in `--guard-only`, `--status-only`, and
`all` dispatch paths.

- [ ] **Step 5: Run red tests and commit.**

Run:

```bash
YINXING_TEST_SHELL=host bash tools/test-yinxing-guard.sh --guard-only
YINXING_TEST_SHELL=host bash tools/test-yinxing-guard.sh --status-only
```

Expected: the new PID-reuse and stale-status assertions fail against Preview 7
while existing assertions pass. Commit as
`test: cover root guard owner identity reuse`.

### Task 2: Implement token-aware owner identity

**Files:**
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh`.
- Modify: `root/kernelsu/yinxing_guard/bin/guard.sh`.
- Modify: `root/kernelsu/yinxing_guard/bin/status.sh`.
- Modify: `tools/test-yinxing-guard.sh` only if a fixture assertion needs exact integration details.

**Interfaces:**
- `process_start_time(pid)` returns a numeric token or no output.
- `guard_owner_identity_state(lock_dir, pid)` returns `match`, `mismatch`, or `unknown`.

- [ ] **Step 1: Implement `process_start_time`.**

In `common.sh`, add:

```sh
process_start_time() {
    process_pid="$1"
    process_proc_root="${YINXING_GUARD_PROC_ROOT:-/proc}"
    process_stat="$(cat "$process_proc_root/$process_pid/stat" 2>/dev/null || true)"
    [ -n "$process_stat" ] || return 1
    process_start="$(printf '%s\n' "$process_stat" | awk '{ sub(/^.*\\) /, ""); print $20; exit }')"
    case "$process_start" in
        ''|*[!0-9]*) return 1 ;;
        *) printf '%s\n' "$process_start" ;;
    esac
}
```

The helper must reject empty/non-numeric tokens and return nonzero without
logging when `/proc` is unavailable.

- [ ] **Step 2: Implement the identity classifier.**

Add `guard_owner_identity_state(lock_dir, pid)`:

```sh
guard_owner_identity_state() {
    identity_lock_dir="$1"
    identity_pid="$2"
    identity_expected="$(cat "$identity_lock_dir/start_time" 2>/dev/null || true)"
    [ -n "$identity_expected" ] || { printf 'unknown\n'; return 0; }
    case "$identity_expected" in
        ''|*[!0-9]*) printf 'unknown\n'; return 0 ;;
    esac
    identity_actual="$(process_start_time "$identity_pid" 2>/dev/null || true)"
    [ -n "$identity_actual" ] || { printf 'unknown\n'; return 0; }
    if [ "$identity_expected" = "$identity_actual" ]; then
        printf 'match\n'
    else
        printf 'mismatch\n'
    fi
}
```

- [ ] **Step 3: Publish and clean the token in `guard.sh`.**

During `mkdir "$LOCK_DIR"`, write `boot_id`, then the current process token if
available, then `pid`. If the boot/token/PID publication fails, remove all
three files and return the existing lock-write failure. Remove `start_time` in
`release_lock` and when reclaiming an old lock.

- [ ] **Step 4: Use the classifier in lock acquisition.**

When `kill -0` confirms a previous PID, call `guard_owner_identity_state`:

```sh
identity_state="$(guard_owner_identity_state "$LOCK_DIR" "$previous_pid")"
case "$identity_state" in
    mismatch)
        ;;
    match|unknown)
        LOCK_OWNER_ACTIVE=1
        log_event "guard_already_running"
        return 1
        ;;
esac
```

The existing exclusive reclaim directory/recheck then removes the stale lock
without signaling the process. The reclaim PID itself keeps the existing
conservative liveness check.

- [ ] **Step 5: Use the same classifier in `status.sh`.**

When a lock PID is live and the classifier returns `mismatch`, emit `stale`;
for `match` or `unknown`, emit `running`. Malformed PID handling remains
`unknown`.

- [ ] **Step 6: Run green shell tests and syntax checks.**

Run:

```bash
env YINXING_TEST_SHELL=host bash tools/test-yinxing-guard.sh all
env YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh all
bash -n root/kernelsu/yinxing_guard/service.sh root/kernelsu/yinxing_guard/action.sh root/kernelsu/yinxing_guard/uninstall.sh root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/guard.sh root/kernelsu/yinxing_guard/bin/status.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh
busybox ash -n root/kernelsu/yinxing_guard/service.sh root/kernelsu/yinxing_guard/action.sh root/kernelsu/yinxing_guard/uninstall.sh root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/guard.sh root/kernelsu/yinxing_guard/bin/status.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh
```

Expected: every test passes, including the mismatched PID recovery and stale
status checks. Commit as `fix: harden root guard owner identity`.

### Task 3: Version and release assets

**Files:**
- Modify: `app/build.gradle.kts` (`versionCode=24`, `versionName=1.10.0-root-preview.8`).
- Modify: `root/kernelsu/yinxing_guard/module.prop` (`versionCode=8`).
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh` and `bin/uninstall-cleanup.sh` (`MODULE_VERSION`).
- Modify: `tools/test-yinxing-guard.sh` package version assertions.
- Modify: `app/src/test/java/com/yinxing/launcher/common/root/RootHealthSnapshotTest.kt` only if a guard-state stale parser case is added.

**Interfaces:** Preview 8 package names are fixed to
`yinxing-1.10.0-root-preview.8-debug.apk` and
`yinxing-guard-1.10.0-root-preview.8.zip`.

- [ ] **Step 1: Add a stale guard parser assertion if absent.**

Use `validSnapshot().replace("guard=running", "guard=stale")` and assert the
parsed state is `DEGRADED` while preserving all other fields.

- [ ] **Step 2: Bump versions and package assertions.**

Update only the Preview 7 literals in the listed files; leave historical docs
unchanged. Run the focused parser test and module package test.

- [ ] **Step 3: Commit the version bump.**

Commit as `chore: bump root guard owner identity preview 8`.

### Task 4: Full verification and release notes

**Files:**
- Create: `docs/release/yinxing-root-preview-8.md`.
- Generated ignored artifacts: `.tmp_preview/root-preview-8/`.

- [ ] **Step 1: Run the forced Android build.**

Run with the configured proxy and shared Gradle cache:

```bash
JAVA_TOOL_OPTIONS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888' \
GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
/usr/bin/time -p bash gradlew :app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon --console=plain
```

Record Gradle result, external time, test count, failures, and warnings.

- [ ] **Step 2: Package and inspect assets.**

Copy the APK, run `tools/package-yinxing-guard.sh` with version
`1.10.0-root-preview.8`, create `SHA256SUMS.txt` inside the asset directory,
and verify `unzip -t`, `aapt2 dump badging`, APK v2 signature, module metadata,
root layout, executable modes, normalized timestamps, and deterministic ZIP
repack.

- [ ] **Step 3: Write release notes.**

Include the PID-reuse threat, conservative `/proc` fallback, install order,
rollback to Preview 7, build environment/time, test totals, asset hashes, and
the GitHub release URL.

- [ ] **Step 4: Commit the notes.**

Commit as `docs: record root guard owner identity preview 8`.

### Task 5: Publish and verify remotely

- [ ] **Step 1: Merge and push.**

Fast-forward `main`, push `origin main`, create annotated tag
`v1.10.0-root-preview.8`, and push the tag.

- [ ] **Step 2: Create the prerelease.**

Run `gh release create v1.10.0-root-preview.8 --repo Gs-ygc/yinxing --prerelease`
with the notes file and exactly the APK, module ZIP, and `SHA256SUMS.txt`.

- [ ] **Step 3: Fresh-download verification.**

Download all assets to a new `mktemp -d`, run checksum/archive/metadata/signature
checks, verify release JSON (`isDraft=false`, `isPrerelease=true`), and verify
`main`, the tag, and peeled tag resolve to the release commit.

- [ ] **Step 4: Update persistent planning files.**

Append Preview 8 evidence and findings to the existing `.planning` files without
adding the user-owned untracked directory to the release commit.

### Task 6: Device feedback loop

- [ ] **Step 1: Leave the goal active.**

The release is not the end of the long-running goal. Wait for OnePlus 15
feedback and use the next observed failure to select Preview 9.

## Self-review checklist

- Every step contains concrete paths, commands, and expected outcomes.
- Every new shell function and lock-file field has a red/green assertion.
- Legacy and unreadable identity evidence never causes an unsafe reclaim.
- The release cannot be called complete until local and fresh remote verification both pass.
