# Root Evidence Boundary Preview 18 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with verification checkpoints.

**Goal:** Make boot-scoped Root evidence fail closed when boot identity is unavailable and cap the HOME foreground dump before shell capture, then publish a verified Preview 18.

**Architecture:** Preserve the fixed KernelSU module plus APK bridge and existing transaction locks. Add one shared boot-identity validity contract to `common.sh` and the standalone cleanup helper, and route the fixed foreground dump through a bounded internal `head -c 65537` pipeline before the strict existing parser. The APK status schema and Root command allowlist remain unchanged.

**Tech Stack:** POSIX `/system/bin/sh`, KernelSU BusyBox `ash`, Bash host fixtures, Kotlin/Gradle Android Debug build, deterministic ZIP packaging, GitHub CLI release assets.

## Global Constraints

- Target only the managed OnePlus 15, China ColorOS 16, KernelSU, Root, Android user 0 baseline.
- Keep exactly the three fixed no-argument APK Root routes: `status.sh`, `action.sh`, and `kiosk-home.sh`.
- Keep the only new Android read as fixed `dumpsys activity activities`; no arbitrary shell input, package, component, coordinate, or process input.
- Treat unavailable boot identity, failed/timeout/pipe/truncated foreground output, and malformed markers as unknown and side-effect free.
- Preserve HOME, accessibility, Doze, transaction-lock, uninstall, and caregiver-choice rollback semantics.
- Release values: app `versionCode=34`, `versionName=1.10.0-root-preview.18`; module `versionCode=18`, `version=1.10.0-root-preview.18`.
- Every task ends with a focused test or source check before its commit.

---

### Task 1: Add red evidence-boundary regressions

**Files:**
- Modify: `tools/test-yinxing-guard.sh` fixture controls, focused test functions, and mode dispatch.

**Interfaces:**
- Consumes: existing `read_home_foreground_activity_state`, `home_foreground_evidence_state`, `write_home_foreground_evidence`, `read_accessibility_binding_stall`, `write_accessibility_binding_stall`, and `run_module_script` helpers.
- Produces: `--preview18-evidence-only` with red tests for unavailable boot identity and pre-capture foreground caps.

- [ ] **Step 1: Add fixture controls without changing production behavior.**

Add cleanup entries for `empty_boot_stat`, `activity_dump_large`, `activity_dump_over_cap`, and `head` call evidence. Add `YINXING_GUARD_BOOT_STAT_FILE` to the exported test environment and make the fake `head` log `head -c 65537` while delegating to `/usr/bin/head`. Add fake `dumpsys` cases that emit an exact-size stream and a stream beyond the cap.

- [ ] **Step 2: Write the unavailable-identity tests.**

Add tests that point `YINXING_GUARD_BOOT_ID_FILE` and `YINXING_GUARD_BOOT_STAT_FILE` at empty/unreadable fixtures, make the fake `getprop` return no `ro.runtime.firstboot`, and assert:

```bash
printf 'verified|unknown\\n' > "$TEST_ROOT/state/home_foreground_evidence"
assert_equals unknown "$(home_foreground_evidence_state)" "unavailable boot does not trust HOME evidence"
printf 'binding|unknown|2|0\\n' > "$TEST_ROOT/state/accessibility_binding_stall"
if accessibility_binding_stall_is_persistent; then fail "unknown boot trusted stall evidence"; fi
if write_home_foreground_evidence verified; then fail "unknown boot accepted foreground evidence"; fi
```

Also restore a valid `fixture-boot` source and assert the same marker becomes trusted only after identity is available. Use the standalone `status.sh` path once to prove the public field is `home_foreground=unknown`.

- [ ] **Step 3: Write the bounded-capture tests.**

Create a valid resumed/focused target pair padded to exactly 65536 bytes and assert `target`; create the same pair padded to 65537 bytes and assert `unknown`. Assert the fake `head` call contains exactly `head -c 65537`, and assert a larger producer completes within the existing one-second command budget without exposing more than 65537 bytes to the parser.

- [ ] **Step 4: Run the new mode and record the expected red failures.**

Run:

```bash
bash tools/test-yinxing-guard.sh --preview18-evidence-only
```

Expected: the new boot-unavailable assertion fails because `unknown` currently compares equal, and the over-cap producer assertion fails because the current implementation captures before checking.

- [ ] **Step 5: Commit the red test contract.**

```bash
git add tools/test-yinxing-guard.sh
git commit -m "test: add preview 18 evidence boundary regressions"
```

### Task 2: Implement fail-closed boot identity

**Files:**
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh:read_boot_id_from, marker validators, current_guard_boot_id, boot-scoped readers/writers`.
- Modify: `root/kernelsu/yinxing_guard/bin/status.sh:boot stat override wiring`.
- Modify: `root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh:valid marker parsers, read_current_boot_id, same-boot comparisons`.
- Test: `tools/test-yinxing-guard.sh` tests from Task 1.

**Interfaces:**
- Consumes: `YINXING_GUARD_BOOT_ID_FILE` and the new test-only `YINXING_GUARD_BOOT_STAT_FILE`.
- Produces: `current_guard_boot_id_is_known` and `current_boot_id_is_known` predicates; all boot-bearing marker contracts reject the reserved unavailable value.

- [ ] **Step 1: Add the test-only `/proc/stat` path and shared identity validator.**

Change the `btime` read to use `${YINXING_GUARD_BOOT_STAT_FILE:-/proc/stat}`. Add a validator accepting only non-empty sanitized IDs other than `unknown`, with the existing 128-byte and character limits. Add `current_guard_boot_id_is_known()` beside `current_guard_boot_id()`; it must re-read the configured sources and return nonzero when the sanitized result is `unknown`.

- [ ] **Step 2: Reject unavailable identity in active marker contracts.**

Update `valid_accessibility_binding_stall_value`, `valid_home_foreground_evidence`, `valid_home_takeover_state`, and `valid_doze_marker_value` to reject `unknown` boot fields. Make `write_home_foreground_evidence`, `observe_accessibility_binding_stall`, and every pending HOME/Doze publication check the known predicate before writing. Make `home_foreground_evidence_state` return `unknown` before comparing when identity is unavailable.

- [ ] **Step 3: Mirror the contract in standalone cleanup.**

Use the same test-only stat path in `read_current_boot_id`, reject `pending|unknown` in standalone HOME/Doze validators, and require a known current ID before same-boot pending comparisons. An invalid legacy marker is retained for retry/diagnostics and never authorizes rollback mutation.

- [ ] **Step 4: Run the focused green tests.**

Run:

```bash
bash tools/test-yinxing-guard.sh --preview18-evidence-only
YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh --preview18-evidence-only
```

Expected: all new unavailable-identity tests and all existing Preview 16/17 evidence tests pass in Host and standalone BusyBox modes.

- [ ] **Step 5: Commit the boot identity hardening.**

```bash
git add root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/status.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh tools/test-yinxing-guard.sh
git commit -m "fix: fail closed on unavailable boot identity"
```

### Task 3: Implement pre-capture foreground output cap

**Files:**
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh:read_home_foreground_activity_state`.
- Test: `tools/test-yinxing-guard.sh` bounded-capture tests.

**Interfaces:**
- Consumes: existing `run_guard_command` timeout/session cleanup and fixed `dumpsys activity activities` invocation.
- Produces: a parser input bounded by `head -c 65537`, with the existing `target|other|unknown` result contract.

- [ ] **Step 1: Replace the unbounded capture with a fixed internal pipeline.**

Invoke the fixed command through the existing timeout wrapper as an internal no-argument script:

```sh
run_guard_command sh -c 'dumpsys activity activities | head -c 65537'
```

Preserve the sentinel/status handling, `>65536` rejection, strict resumed/focused parsing, and timeout failure behavior. Do not accept pipeline text or any caller-supplied command fragments.

- [ ] **Step 2: Run the capture tests in both shells.**

Run the Host and BusyBox focused mode from Task 2. Expected: exact 65536-byte target output is accepted, 65537-byte output is unknown, large output is bounded, and the fixed `head -c 65537` call is observable.

- [ ] **Step 3: Commit the bounded probe.**

```bash
git add root/kernelsu/yinxing_guard/bin/common.sh tools/test-yinxing-guard.sh
git commit -m "fix: bound root home foreground capture"
```

### Task 4: Bump Preview 18 metadata and documentation

**Files:**
- Modify: `app/build.gradle.kts:versionCode/versionName`.
- Modify: `root/kernelsu/yinxing_guard/module.prop:version/versionCode`.
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh:MODULE_VERSION`.
- Modify: `root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh:MODULE_VERSION`.
- Modify: `tools/test-yinxing-guard.sh:package assertions`.
- Create: `docs/release/yinxing-root-preview-18.md`.
- Existing: `docs/superpowers/specs/2026-08-10-root-evidence-boundary-preview-18-design.md` (committed before implementation).
- Existing: `docs/superpowers/plans/2026-08-10-root-evidence-boundary-preview-18.md` (this plan).

**Interfaces:**
- Consumes: the Preview 18 implementation commits and test evidence.
- Produces: package metadata `1.10.0-root-preview.18`/34 and module metadata `1.10.0-root-preview.18`/18.

- [ ] **Step 1: Update version metadata and package expectations.**

Change all production version strings to Preview 18 and update the packager assertions from module code 17 to 18. Keep the test packager's synthetic `9.9.9-test` version while requiring `versionCode=18`.

- [ ] **Step 2: Write the release note skeleton.**

Document the two evidence-boundary fixes, APK-before-module installation order, physical-device validation checklist, and exact measured hashes/times before release. The final file must contain no unresolved placeholders.

- [ ] **Step 3: Run metadata and syntax checks.**

Run:

```bash
rg -n "preview\\.17|versionCode=17|versionCode = 33" app root tools docs/release docs/superpowers || true
sh -n root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh
git diff --check
```

Expected: no stale production Preview 17 metadata, syntax exit 0, and no whitespace errors.

- [ ] **Step 4: Commit Preview 18 metadata/docs.**

```bash
git add app/build.gradle.kts root/kernelsu/yinxing_guard tools/test-yinxing-guard.sh docs/release/yinxing-root-preview-18.md
git commit -m "chore: bump root preview 18 metadata"
```

### Task 5: Full verification, review, package, and release

**Files:**
- Modify: `docs/release/yinxing-root-preview-18.md` with measured evidence.
- Modify: `.planning/2026-08-07-android-build-verification/task_plan.md`, `findings.md`, and `progress.md` in the primary checkout.

**Interfaces:**
- Consumes: exact Preview 18 commit and all focused green tests.
- Produces: a rollback-capable GitHub prerelease with APK, KernelSU ZIP, and `SHA256SUMS.txt`.

- [ ] **Step 1: Run the complete shell matrix and Android tests/build.**

Run the exact commands from the populated Gradle cache:

```bash
/usr/bin/time -p -o out-preview18-shell.time bash tools/test-yinxing-guard.sh all
GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash ./gradlew :app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon --console=plain
```

Record PASS/FAIL counts, Gradle task result, JUnit totals, and wall times. Any failure returns to the relevant task before release.

- [ ] **Step 2: Run independent review at the exact source commit.**

Review the boot identity source order, reserved `unknown` rejection, standalone cleanup parity, fixed pipeline argument safety, timeout descendant cleanup, and regression coverage. Resolve Critical/Important findings before packaging.

- [ ] **Step 3: Package deterministic assets.**

Use `tools/package-yinxing-guard.sh` to create the module ZIP, repack it to prove byte identity, generate `SHA256SUMS.txt`, inspect APK metadata/signature, and verify ZIP modes/timestamps/layout. Build assets outside the module source tree.

- [ ] **Step 4: Publish source and Release.**

Push the exact feature commit and `main` to `origin`, create annotated tag `v1.10.0-root-preview.18`, upload APK/module/checksum assets, and keep the Release prerelease and non-draft.

- [ ] **Step 5: Re-download and verify the published assets.**

In a fresh directory, download all three assets with the GitHub credential obtained through `git credential fill`; run `sha256sum -c`, `cmp` against local candidates, `unzip -t`, `aapt dump badging`, and `apksigner verify --verbose --print-certs`. Never print the credential.

- [ ] **Step 6: Update persistent Goal records and wait for device feedback.**

Record Preview 18 findings, exact source/tag/Release URL, hashes, measured verification, and the absence/presence of an adb device. Set the next phase to Preview 18 device feedback; keep the Goal active.
