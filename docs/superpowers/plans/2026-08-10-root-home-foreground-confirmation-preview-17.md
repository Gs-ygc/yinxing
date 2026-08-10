# Root HOME Foreground Confirmation Preview 17 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended). Steps use checkbox ( - [ ] ) syntax for tracking.

**Goal:** Require a bounded foreground postcondition for Root HOME launches and expose the result through the existing schema-2 home state.

**Architecture:** Add a strict, read-only dumpsys activity activities parser to the shared KernelSU shell helper. launch_home dispatches the existing fixed component, polls for the exact resumed/focused target, and returns success only after confirmation. guard.sh has a two-attempt process bound and distinguishes known-other from unknown diagnostics. status.sh composes role, resolver, and foreground evidence without adding a public field or command path.

**Tech Stack:** POSIX /system/bin/sh, KernelSU BusyBox 1.36.1, Bash fixture harness, Kotlin/JUnit 4, Gradle 9.3.1, Android SDK 36, GitHub CLI.

## Global Constraints

- Target only the managed OnePlus 15 China ColorOS 16, KernelSU, Root, Android user 0.
- Keep exactly three fixed, no-argument Root paths and route every Android command through run_guard_command.
- Accept only explicit mResumedActivity:/mFocusedActivity: lines with a strict fixed component token; never search arbitrary dumpsys text.
- Unknown, malformed, conflicting, failed, or timed-out output is fail-closed and never causes a mutation or same-process retry.
- Preserve existing HOME role/resolver transactions, accessibility, Doze, lock, uninstall, caregiver-choice, APK parser, and UI behavior.
- Preview values are app versionCode=33, module versionCode=17, and version 1.10.0-root-preview.17.
- .planning/ is user-owned untracked state and is never committed.

### Task 1: Add red foreground fixtures and parser/launch regressions

**Files:**
- Modify: tools/test-yinxing-guard.sh fake dumpsys, fixture reset/setup, focused tests, and mode registration.
- Test: tools/test-yinxing-guard.sh.

**Interfaces:**
- Produces deterministic $TEST_ROOT/activity_dump and numbered
  $TEST_ROOT/activity_dump_sequence/* fixtures.
- The fake command logs dumpsys activity activities and retains existing
  accessibility dump behavior unchanged.

- [ ] **Step 1: Extend the fake dump command and reset controls.**

Add activity dump files, sequence counters, failure, and hang controls without
changing production code. Keep accessibility responses selected only for the
existing dumpsys accessibility command.

- [ ] **Step 2: Add strict parser tests before implementation.**

Cover target resumed/focused records, fully qualified target, known other,
missing/malformed/conflicting records, unrelated target text, timeout, and
command failure. Assert the expected target|other|unknown result.

- [ ] **Step 3: Add launch and Guard regressions.**

Require launch_home to fail when am succeeds but the foreground probe is
other/unknown; require bounded three-poll confirmation; require Guard to retry
one known-other failure but never exceed two starts, and never retry unknown
evidence in the same process. Keep existing launch tests green by providing an
explicit target fixture.

- [ ] **Step 4: Run the focused suite and commit the red harness.**

Expected: the new parser assertion fails before production implementation.

    git add tools/test-yinxing-guard.sh
    git commit -m "test: define root home foreground contract"

### Task 2: Implement strict foreground parsing and bounded confirmation

**Files:**
- Modify: root/kernelsu/yinxing_guard/bin/common.sh.
- Test: focused shell tests.

**Interfaces:**
- Produces read_home_foreground_state() returning target, other, or unknown.
- Produces confirm_home_foreground() with bounded sanitized attempts and delay settings.

- [ ] **Step 1: Implement fixed command capture and line parser.**

Run only dumpsys activity activities through the existing timeout wrapper.
Require a successful command, bounded output, and explicit resumed/focused
record framing. Normalize only the known short/full target class forms.

- [ ] **Step 2: Reject ambiguous evidence.**

Track resumed and focused states separately. Return target only when all
recognized fields agree on target; return other only when recognized fields
agree on a non-target; return unknown for missing, malformed, or conflicting
records. Keep parsing POSIX/BusyBox-compatible and free of arbitrary eval or
input arguments.

- [ ] **Step 3: Add confirmation polling.**

Use defaults of three attempts and one second between polls. Sanitize numeric
overrides with a hard upper bound. Re-check module activity before and after
each command/sleep. Log fixed verified/other/unknown events.

- [ ] **Step 4: Run host and BusyBox focused tests, then commit.**

    git add root/kernelsu/yinxing_guard/bin/common.sh tools/test-yinxing-guard.sh
    git commit -m "feat: confirm root home foreground activity"

### Task 3: Integrate launch retry and status semantics

**Files:**
- Modify: root/kernelsu/yinxing_guard/bin/guard.sh.
- Modify: root/kernelsu/yinxing_guard/bin/common.sh.
- Modify: root/kernelsu/yinxing_guard/bin/status.sh.
- Modify: tools/test-yinxing-guard.sh.

**Interfaces:**
- launch_home() returns success only after target confirmation.
- Guard process state bounds starts to two and retries only known-other evidence.
- Schema 2 remains nine lines; home=owned requires foreground target when the
  role holder is Yinxing.

- [ ] **Step 1: Keep the launch postcondition red.**

Run the new launch tests and confirm the current unconditional success fails
the postcondition assertions.

- [ ] **Step 2: Wire launch_home() to confirmation.**

Dispatch the fixed component, call the confirmation helper, and return
distinct status for known-other versus unknown. Preserve module-active checks
and avoid any second command outside the fixed probe.

- [ ] **Step 3: Bound Guard retry state.**

Add sanitized HOME_LAUNCH_MAX_ATTEMPTS=2 and a per-process attempt counter.
Mark HOME_LAUNCHED=1 only on verified success. Permit the next health cycle
after known-other failure; stop further starts after the bound or unknown
evidence. Existing repair failure still records last_repair=failed.

- [ ] **Step 4: Compose status without writes.**

When home_role_state() sees Yinxing as role holder, require resolver target
and foreground target for owned; map known other to other, and all probe
failures/conflicts to unknown. Do not query foreground for other/none role
holders. Keep RootHealthSnapshot schema 2 and its healthy predicate unchanged.

- [ ] **Step 5: Run focused status/Guard tests and commit.**

    git add root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/guard.sh root/kernelsu/yinxing_guard/bin/status.sh tools/test-yinxing-guard.sh
    git commit -m "fix: require verified foreground home"

### Task 4: Version metadata and release notes

**Files:**
- Modify: app/build.gradle.kts.
- Modify: root/kernelsu/yinxing_guard/module.prop.
- Modify: both shell MODULE_VERSION literals.
- Create: docs/release/yinxing-root-preview-17.md.
- Modify: package/version assertions in tools/test-yinxing-guard.sh.

- [ ] **Step 1: Bump Preview 17 metadata.**

Use app code 33 and module code 17. State that the APK is Debug-only, the
module must be enabled before APK installation, schema 2 remains compatible,
and foreground confirmation is a ColorOS-specific reliability measure rather
than physical-device proof.

- [ ] **Step 2: Run package/syntax checks and commit metadata.**

    git add app/build.gradle.kts root/kernelsu/yinxing_guard/module.prop root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/guard.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh tools/test-yinxing-guard.sh docs/release/yinxing-root-preview-17.md
    git commit -m "chore: bump root preview 17 metadata"

### Task 5: Full verification, packaging, and GitHub Release

**Files:**
- Modify: docs/release/yinxing-root-preview-17.md with final evidence only.
- Create locally: Preview 17 APK, KernelSU ZIP, and SHA256SUMS.txt.

- [ ] **Step 1: Run complete shell verification.**

Run shell syntax scans, fixed-command/allowlist scans, host plus recursive
BusyBox bash tools/test-yinxing-guard.sh all, and record exact pass/fail and
elapsed time.

- [ ] **Step 2: Run Android tests and forced Debug build.**

    time GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home bash ./gradlew :app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon --console=plain

Record task count and JUnit totals without masking the exit code.

- [ ] **Step 3: Package and inspect assets.**

Package the module deterministically, copy the Debug APK, create basename-only
SHA-256 sums, and verify ZIP layout/modes/timestamps, APK metadata, and v2
signature. Repack independently and compare bytes.

- [ ] **Step 4: Push source and publish a prerelease.**

Push the feature branch and fast-forward main on origin, create annotated tag
v1.10.0-root-preview.17, and publish exactly the APK, module ZIP, and checksums
to Gs-ygc/yinxing with gh release create --prerelease.

- [ ] **Step 5: Verify fresh remote downloads and update planning state.**

Download all release assets into a new directory, rerun checksums/archive/
metadata/signature checks, verify refs/tag/release JSON, and append exact
evidence to the user-owned .planning files. Keep the long-running Goal active
and leave the next device-feedback phase open.
