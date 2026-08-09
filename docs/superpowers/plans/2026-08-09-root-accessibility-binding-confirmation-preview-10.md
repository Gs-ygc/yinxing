# Root Accessibility Binding Confirmation Preview 10 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Confirm that the fixed Yinxing accessibility service leaves `Crashed services` after one Root rebind, fail a persistently confirmed crash, and publish Preview 10.

**Architecture:** The existing shell harness gains numbered `dumpsys accessibility` responses so tests can drive real state transitions. `common.sh` adds a read-only, bounded confirmation loop called after the existing exact remove/restore sequence; bound or binding succeeds, persistent crashed fails, and unknown vendor output remains non-destructive. APK Root routing and Kiosk behavior stay unchanged.

**Tech Stack:** POSIX `/system/bin/sh`, KernelSU standalone BusyBox `ash`, Bash test harness, Gradle 9.3.1, Kotlin/JVM tests, Android Debug APK packaging, GitHub CLI.

## Global Constraints

- Target OnePlus 15 China ColorOS 16 with KernelSU on a user-controlled rooted appliance.
- Root commands remain the literal fixed paths `status.sh`, `action.sh`, and `kiosk-home.sh`; no arbitrary shell, arguments, package, component, coordinates, process killing, or private ColorOS API.
- A recovery performs exactly one remove/restore pair for only the fixed Yinxing accessibility component and preserves all unrelated services.
- Confirmation performs at most five read-only polls by default, one second apart only while the state remains confirmed `crashed`.
- `bound` and `binding` succeed; final confirmed `crashed` fails; `unknown` stays non-destructive and succeeds without another settings toggle.
- Module scripts remain POSIX `sh` and standalone BusyBox `ash` compatible; module ZIP entries remain rooted, executable, timestamp-normalized, and deterministic.
- Preview 10 versions are APK `versionCode=26`, module `versionCode=10`, and `versionName=1.10.0-root-preview.10`.
- Release assets remain a Debug APK, KernelSU module ZIP, basename-only `SHA256SUMS.txt`, release notes, annotated tag, and fresh remote-download verification.

---

### Task 1: Transition Harness And Failing Recovery Tests

**Files:**
- Modify: `tools/test-yinxing-guard.sh`

**Interfaces:**
- Consumes: existing fake `dumpsys`, `repair_state()`, `action.sh`, `ACCESSIBILITY_COMPONENT`, `CALLS`, and fixture reset.
- Produces: numbered response directory `$TEST_ROOT/accessibility_dump_sequence`, call counter `$TEST_ROOT/accessibility_dump_sequence_calls`, and three regressions that expose missing post-rebind confirmation.

- [ ] **Step 1: Teach the fake diagnostic to emit numbered responses.**

Before its existing single-file fallback, extend fake `dumpsys` with:

```bash
'if [[ -d "$TEST_ROOT/accessibility_dump_sequence" ]]; then' \
'  sequence_call="$(cat "$TEST_ROOT/accessibility_dump_sequence_calls" 2>/dev/null || printf 0)"' \
'  sequence_call=$((sequence_call + 1))' \
'  printf "%s\n" "$sequence_call" > "$TEST_ROOT/accessibility_dump_sequence_calls"' \
'  sequence_response="$TEST_ROOT/accessibility_dump_sequence/$sequence_call"' \
'  [[ -f "$sequence_response" ]] || sequence_response="$TEST_ROOT/accessibility_dump_sequence/last"' \
'  [[ -f "$sequence_response" ]] && cat "$sequence_response"' \
'  exit 0' \
'fi' \
```

Add `$TEST_ROOT/accessibility_dump_sequence_calls` to the reset file list and `$TEST_ROOT/accessibility_dump_sequence` to the reset directory list.

- [ ] **Step 2: Replace the immediate-success crash test with a delayed-binding regression.**

Rename `test_repair_rebinds_crashed_accessibility_service` to `test_repair_confirms_binding_after_crash`. Create sequence files 1 and 2 with the literal crashed section and file 3 with the literal binding section. Invoke:

```bash
YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS=3 \
YINXING_GUARD_REBIND_CONFIRM_SECONDS=0 \
    repair_state
```

Assert observable behavior:

```bash
assert_equals "3" "$(grep -c '^dumpsys accessibility$' "$CALLS" || true)" \
    "rebind should poll until binding is observed"
assert_equals "2" "$(grep -c '^settings --user 0 put secure enabled_accessibility_services' "$CALLS" || true)" \
    "binding confirmation must not repeat the remove/restore pair"
assert_contains "$CALLS" "accessibility_service_rebind_confirmed"
```

Retain assertions that TalkBack is preserved, the exact Yinxing list is removed/restored, `accessibility_enabled` is reasserted, and `accessibility_service_rebound` is logged.

- [ ] **Step 3: Add persistent-crash action coverage.**

Add `test_action_marks_persistent_accessibility_crash_failed`. Seed enabled settings and numbered dump files 1, 2, and 3 with the literal crashed section. Run `action.sh` with two confirmation attempts and zero delay:

```bash
if YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS=2 \
    YINXING_GUARD_REBIND_CONFIRM_SECONDS=0 \
    run_module_script "$MODULE_ROOT/action.sh"; then
    fail "persistent accessibility crash unexpectedly reported recovery success"
fi
```

Assert:

```bash
assert_equals "failed" "$(tr -d '\n' < "$TEST_ROOT/state/last_repair")" \
    "persistent crash should record failed repair"
assert_equals "3" "$(grep -c '^dumpsys accessibility$' "$CALLS" || true)" \
    "persistent crash should stop at the confirmation bound"
assert_equals "2" "$(grep -c '^settings --user 0 put secure enabled_accessibility_services' "$CALLS" || true)" \
    "persistent crash must not repeat settings toggles"
assert_not_contains "$CALLS" "am start"
assert_contains "$CALLS" "accessibility_service_rebind_persisted"
```

- [ ] **Step 4: Add unknown-confirmation safety coverage.**

Add `test_repair_keeps_unknown_rebind_confirmation_nonfatal`. Seed response 1 as crashed and response 2 as an empty file. Run `repair_state` with two attempts and zero delay. Assert success, exactly two diagnostic calls, exactly two service-list writes, `accessibility_service_rebind_unverified`, and no `accessibility_service_rebind_persisted` log.

- [ ] **Step 5: Register all three tests and observe RED.**

Replace the renamed test in the `all` case, add the two new tests immediately after it, and leave status-only/guard-only dispatch unchanged.

Run:

```bash
bash tools/test-yinxing-guard.sh all
```

Expected: FAIL in `test_repair_confirms_binding_after_crash` because the current implementation performs only the initial diagnostic and does not log confirmation. The recursive BusyBox run is not expected to start after the host failure.

- [ ] **Step 6: Commit the red tests.**

```bash
git add tools/test-yinxing-guard.sh
git commit -m "test: require accessibility rebind confirmation"
```

---

### Task 2: Bounded Post-Rebind Confirmation

**Files:**
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh`
- Test: `tools/test-yinxing-guard.sh`

**Interfaces:**
- Consumes: `accessibility_service_binding_state(): bound|binding|crashed|unknown`, `log_event()`, and optional environment values `YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS` / `YINXING_GUARD_REBIND_CONFIRM_SECONDS`.
- Produces: `confirm_accessibility_service_rebind(): 0|1`; `rebind_accessibility_service()` returns failure only after a final confirmed crash or an existing settings-write failure.

- [ ] **Step 1: Add the minimal confirmation helper.**

Place this after `accessibility_service_binding_state()`:

```sh
confirm_accessibility_service_rebind() {
    confirm_attempts="${YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS:-5}"
    case "$confirm_attempts" in
        ''|*[!0-9]*|0) confirm_attempts=5 ;;
    esac
    confirm_seconds="${YINXING_GUARD_REBIND_CONFIRM_SECONDS:-1}"
    case "$confirm_seconds" in
        ''|*[!0-9]*) confirm_seconds=1 ;;
    esac

    confirm_attempt=1
    while [ "$confirm_attempt" -le "$confirm_attempts" ]; do
        confirm_state="$(accessibility_service_binding_state)"
        case "$confirm_state" in
            bound|binding)
                log_event "accessibility_service_rebind_confirmed"
                return 0
                ;;
            unknown)
                log_event "accessibility_service_rebind_unverified"
                return 0
                ;;
            crashed)
                if [ "$confirm_attempt" -ge "$confirm_attempts" ]; then
                    log_event "accessibility_service_rebind_persisted"
                    return 1
                fi
                sleep "$confirm_seconds"
                ;;
            *)
                log_event "accessibility_service_rebind_unverified"
                return 0
                ;;
        esac
        confirm_attempt=$((confirm_attempt + 1))
    done
    return 1
}
```

- [ ] **Step 2: Bind confirmation to the existing one-shot rebind.**

After restoring the merged service list and reasserting `accessibility_enabled=1`, call:

```sh
if ! confirm_accessibility_service_rebind; then
    return 1
fi
log_event "accessibility_service_rebound"
return 0
```

Do not add another settings write inside or after confirmation.

- [ ] **Step 3: Run the focused host shell suite.**

Run:

```bash
bash tools/test-yinxing-guard.sh all
```

Expected: host tests and the recursive `ASH_STANDALONE=1 busybox ash` suite both PASS, including delayed binding, persistent crash, and unknown confirmation.

- [ ] **Step 4: Run syntax and diff checks.**

```bash
bash -n root/kernelsu/yinxing_guard/bin/*.sh tools/test-yinxing-guard.sh tools/package-yinxing-guard.sh
busybox ash -n root/kernelsu/yinxing_guard/bin/common.sh
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit the implementation.**

```bash
git add root/kernelsu/yinxing_guard/bin/common.sh
git commit -m "feat: confirm accessibility service rebind"
```

---

### Task 3: Preview 10 Version, Full Verification, And Release

**Files:**
- Modify: `app/build.gradle.kts`
- Modify: `root/kernelsu/yinxing_guard/module.prop`
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh`
- Modify: `root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh`
- Modify: `tools/test-yinxing-guard.sh`
- Create: `docs/release/yinxing-root-preview-10.md`

**Interfaces:**
- Consumes: verified Preview 10 source, Debug APK output `app/build/outputs/apk/debug/app-debug.apk`, and module packager `tools/package-yinxing-guard.sh`.
- Produces: tag `v1.10.0-root-preview.10`, source commit on `origin/main`, GitHub Release APK/ZIP/checksum assets, and remote verification evidence.

- [ ] **Step 1: Bump exact version metadata and package assertions.**

Set:

```kotlin
versionCode = 26
versionName = "1.10.0-root-preview.10"
```

Set module `version=1.10.0-root-preview.10`, `versionCode=10`, and both shell `MODULE_VERSION` constants to `1.10.0-root-preview.10`. Update package-test source and ZIP assertions to code 10 / Preview 10. Run:

```bash
rg -n 'root-preview\.9|versionCode=9|versionCode = 25' app root tools --glob '!app/build/**'
```

Expected: no current-version hits remain outside historical docs/plans.

- [ ] **Step 2: Commit the version slice.**

```bash
git add app/build.gradle.kts root/kernelsu/yinxing_guard/module.prop root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh tools/test-yinxing-guard.sh
git commit -m "chore: bump root preview 10 version"
```

- [ ] **Step 3: Run fresh release verification.**

Run the complete module suite and syntax checks, then:

```bash
env GRADLE_OPTS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888 -Dkotlin.incremental=false' \
    /usr/bin/time -f 'ELAPSED_SECONDS=%e' \
    bash ./gradlew :app:testDebugUnitTest :app:assembleDebug \
    --rerun-tasks --no-daemon --console=plain
```

Expected: exit 0, every test report has zero failures/errors/skips, and `assembleDebug` succeeds. Record exact test count and elapsed time from fresh output/XML.

- [ ] **Step 4: Generate deterministic release assets and basename checksums.**

```bash
mkdir -p out/release
cp app/build/outputs/apk/debug/app-debug.apk \
    out/release/yinxing-1.10.0-root-preview.10-debug.apk
bash tools/package-yinxing-guard.sh \
    out/release/yinxing-guard-1.10.0-root-preview.10.zip \
    1.10.0-root-preview.10
(
    cd out/release
    sha256sum \
        yinxing-1.10.0-root-preview.10-debug.apk \
        yinxing-guard-1.10.0-root-preview.10.zip \
        > SHA256SUMS.txt
)
```

Verify with `aapt2 dump badging`, `apksigner verify --verbose`, `unzip -t`, ZIP root-entry/mode/timestamp checks, and a second packager output compared with `cmp -s`.

- [ ] **Step 5: Write and commit release notes.**

Create `docs/release/yinxing-root-preview-10.md` containing:

- exact APK/module versions and filenames;
- bounded confirmation state table and unchanged Root allowlist;
- KernelSU-module-first installation order and Debug-signing caveat;
- rollback to Preview 9;
- exact host/BusyBox/Gradle timings and Android test count;
- APK/module SHA-256 values;
- explicit statement that no OnePlus 15 was connected for local verification.

Run `git diff --check`, then commit the notes with `docs: add root preview 10 release notes`.

- [ ] **Step 6: Fast-forward main, push source and annotated tag.**

From the main worktree, require only the user-owned `.planning/` path to be untracked. Run:

```bash
git merge --ff-only feat/root-accessibility-binding-confirmation-preview-10
git push origin main
git tag -a v1.10.0-root-preview.10 -m "Yinxing Root Guard Preview 10"
git push origin v1.10.0-root-preview.10
```

Expected: remote `main` and peeled tag resolve to the same release source commit.

- [ ] **Step 7: Publish and remotely verify GitHub assets.**

Create the Release with `gh release create --verify-tag`, the committed notes file, and all three assets. Then verify:

```bash
git ls-remote origin \
    refs/heads/main \
    refs/tags/v1.10.0-root-preview.10 \
    'refs/tags/v1.10.0-root-preview.10^{}'
gh release view v1.10.0-root-preview.10 --repo Gs-ygc/yinxing \
    --json url,tagName,name,isDraft,isPrerelease,assets
```

Download all three assets into a fresh `mktemp -d` directory. From that directory run `sha256sum -c SHA256SUMS.txt`, `unzip -t` on the module ZIP, `aapt2 dump badging`, and `apksigner verify --verbose`. The downloaded digests must equal the committed release notes and local asset digests.

- [ ] **Step 8: Update persistent goal records.**

Append Preview 10 source commit, tag, Release URL, test/build timings, hashes, design findings, and the remaining OnePlus 15 validation requirement to the active `.planning` task, findings, and progress files. Keep Phase 19 complete for local/release verification and the device-feedback phase in progress.
