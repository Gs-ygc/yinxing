# Confirmed-Unbound Accessibility Recovery Preview 12 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover an already-enabled Yinxing AccessibilityService that a structurally recognized `dumpsys accessibility` report proves is unbound, while preserving first-enable and unknown-output safety.

**Architecture:** The fixed KernelSU parser gains internal `unbound` only when all three expected binding-state headers are present and the target is absent. `status.sh` maps it to existing `stale`; repair reuses the existing exact rebind only for a target already fully enabled before the cycle, and confirmation treats persistent `unbound` like persistent `crashed`. APK protocol, Root command paths, budgets, and external status schema do not change.

**Tech Stack:** KernelSU BusyBox/POSIX shell, Bash host harness, Gradle 9.3.1 Debug JVM build, KernelSU ZIP packager, Android SDK Build Tools 36.0.0.

## Global Constraints

- Target the fixed OnePlus 15 China ColorOS 16 device with KernelSU on a user-controlled rooted appliance.
- Keep exactly three fixed, no-argument Root paths: `status.sh`, `action.sh`, and `kiosk-home.sh`. Do not add arbitrary shell, arguments, package/component input, coordinates, app/system process targeting, or private ColorOS APIs.
- Only simultaneous presence of `Bound services`, `Binding services`, and `Crashed services`, with no fixed target in any of them, may yield `unbound`; missing, failed, truncated, or vendor-renamed output remains `unknown`.
- `unbound` may rebind only when pre-repair `enabled_accessibility_services` already contained the target and pre-repair `accessibility_enabled` was `1`.
- A persistent post-rebind `unbound` fails within the existing bounded confirmation loop. `unknown` confirmation remains non-fatal and side-effect free.
- Preserve process/output failure handling, app-facing schema, Kiosk behavior, Android UI, and exact existing component-list semantics.
- Preview values are APK code `28`/name `1.10.0-root-preview.12` and module code `12`/name `1.10.0-root-preview.12`.

---

### Task 1: Red Shell Regressions for Confirmed Unbound

**Files:**
- Modify: `tools/test-yinxing-guard.sh`

**Interfaces:**
- Consumes: `repair_state()`, `action.sh`, `status.sh`, fake `dumpsys`, the dump-sequence fixture, `CALLS`, and current assertion helpers.
- Produces: observable host/BusyBox coverage for stale health, exact rebind, bounded persistent failure, first-enable protection, and partial-output safety.

- [ ] **Step 1: Add the complete-empty stale-health regression.**

Insert `test_status_reports_stale_when_accessibility_service_confirmed_unbound()` after the existing crashed-status test. It calls `prepare_healthy_status_fixture`, writes this exact dump, runs `status.sh`, and asserts `accessibility=stale`:

```text
User state[
  Bound services:{}
  Enabled services:{$ACCESSIBILITY_COMPONENT}
  Binding services:{}
  Crashed services:{}
  Client list info:{}
]
```

- [ ] **Step 2: Add successful and persistent exact-rebind regressions.**

Add `test_repair_confirms_binding_after_confirmed_unbound()` after the crashed-rebind test. Initialize `SERVICES` to `talkback:other:$ACCESSIBILITY_COMPONENT` and `ACCESSIBILITY_ENABLED` to `1`. Write response 1 as the complete-empty dump above and response 2 with `Binding services:{$ACCESSIBILITY_COMPONENT}`. Run:

```bash
YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS=2 \
YINXING_GUARD_REBIND_CONFIRM_SECONDS=0 \
    repair_state || fail "confirmed unbound service should be rebound"
```

Require two dumpsys calls, two service-list writes, removal value `talkback:other`, restored value `talkback:other:$ACCESSIBILITY_COMPONENT`, `accessibility_service_rebind_confirmed`, and `accessibility_service_rebound`.

Add `test_action_marks_persistent_confirmed_unbound_failed()` after the persistent-crash action test. Give sequence responses 1 through 3 the exact complete-empty dump, run `action.sh` with two attempts/zero seconds, and require failure, `last_repair=failed`, three dumpsys calls, two service-list writes, no `am start`, and `accessibility_service_rebind_persisted`.

- [ ] **Step 3: Add first-enable and partial-diagnostic safety regressions.**

Add `test_repair_does_not_rebind_initial_enable_when_unbound()` with empty services, `accessibility_enabled=0`, complete-empty dump, and `repair_state`. Require target membership once, exactly one service-list write, and no rebind log.

Add `test_repair_ignores_partial_accessibility_diagnostic()` with already-enabled target and a dump containing only `Bound services`, `Enabled services`, and `Binding services` headers. Require success with no secure-setting write and no rebind log.

- [ ] **Step 4: Register tests and prove RED.**

Add the health test after the crashed-status test in `--status-only` and `all`. Add the four repair/action tests after nearest existing counterparts in `--guard-only` and `all`. Run:

```bash
bash tools/test-yinxing-guard.sh all
```

Expected: current code reports complete-empty state as `accessibility=enabled`, skips the expected rebind, and lets persistent unbound action succeed. First-enable and partial-output tests characterize existing safety behavior.

- [ ] **Step 5: Validate and commit the red slice.**

```bash
git diff --check
git status --short
git add tools/test-yinxing-guard.sh
git commit -m "test: cover confirmed unbound accessibility"
```

Expected: diff check exits 0 and only `tools/test-yinxing-guard.sh` is changed before commit.

---

### Task 2: Structural Parser and Bounded Unbound Recovery

**Files:**
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh`
- Modify: `root/kernelsu/yinxing_guard/bin/status.sh`
- Modify: `tools/test-yinxing-guard.sh`

**Interfaces:**
- Consumes: Task 1 regressions, `accessibility_service_binding_state()`, `confirm_accessibility_service_rebind()`, `repair_accessibility()`, and `accessibility_state()`.
- Produces: internal `unbound`, existing external `stale`, and one bounded exact rebind only for a target fully enabled before this repair cycle.

- [ ] **Step 1: Make complete dump structure an explicit parser condition.**

In `accessibility_service_binding_state()`, replace the three header actions with:

```awk
/^[[:space:]]*Bound services:/ { seen_bound = 1; section = "bound" }
/^[[:space:]]*Binding services:/ { seen_binding = 1; section = "binding" }
/^[[:space:]]*Crashed services:/ { seen_crashed = 1; section = "crashed" }
```

Keep `Enabled services`/`Client list info` resets and target-match precedence. Immediately before final `unknown`, add:

```awk
} else if (seen_bound && seen_binding && seen_crashed) {
    print "unbound"
```

- [ ] **Step 2: Make post-rebind unbound bounded failure evidence.**

In `confirm_accessibility_service_rebind()`, change only the retry label:

```sh
crashed)
```

to:

```sh
crashed|unbound)
```

Keep its current bounded attempts, sleep, `accessibility_service_rebind_persisted`, and unknown/nonfatal branch unchanged.

- [ ] **Step 3: Gate unbound rebind with immutable pre-repair state.**

After successful reads of `current` and `enabled` in `repair_accessibility()`, add:

```sh
target_was_enabled=0
case ":$current:" in
    *":$ACCESSIBILITY_COMPONENT:"*) target_was_enabled=1 ;;
esac
if [ "$target_was_enabled" -eq 1 ] && [ "$enabled" = "1" ]; then
    target_was_fully_enabled=1
else
    target_was_fully_enabled=0
fi
```

Replace the post-state single-crashed check with:

```sh
case "$binding_state" in
    crashed)
        rebind_accessibility_service "$current" "$merged" || return 1
        ;;
    unbound)
        if [ "$target_was_fully_enabled" -eq 1 ]; then
            rebind_accessibility_service "$current" "$merged" || return 1
        fi
        ;;
esac
```

- [ ] **Step 4: Map unbound to existing stale status.**

In the fully enabled branch of `status.sh`, use:

```sh
case "$(accessibility_service_binding_state)" in
    crashed|unbound) printf 'stale\n' ;;
    *) printf 'enabled\n' ;;
esac
```

Do not add an external status value or modify APK parsing.

- [ ] **Step 5: Run the complete module matrix green.**

```bash
/usr/bin/time -f 'ELAPSED_SECONDS=%e' bash tools/test-yinxing-guard.sh all
bash -n root/kernelsu/yinxing_guard/bin/*.sh tools/test-yinxing-guard.sh tools/package-yinxing-guard.sh
busybox ash -n root/kernelsu/yinxing_guard/bin/common.sh
git diff --check
```

Expected: host and recursive BusyBox pass stale status, transition, persistent failure, first-enable, partial-output, and all existing tests.

- [ ] **Step 6: Commit minimal production code.**

```bash
git add root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/status.sh tools/test-yinxing-guard.sh
git commit -m "fix: recover confirmed unbound accessibility"
```

---

### Task 3: Preview 12 Version, Verification, and Release

**Files:**
- Modify: `app/build.gradle.kts`
- Modify: `root/kernelsu/yinxing_guard/module.prop`
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh`
- Modify: `root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh`
- Modify: `tools/test-yinxing-guard.sh`
- Create: `docs/release/yinxing-root-preview-12.md`

**Interfaces:**
- Consumes: Task 2 module behavior, Debug APK output, `tools/package-yinxing-guard.sh`, and Preview 11's verified release procedure.
- Produces: tag `v1.10.0-root-preview.12`, APK/module/checksum assets, release notes, and fresh remote verification evidence.

- [ ] **Step 1: Bump all exact version sources.**

Set `app/build.gradle.kts` to:

```kotlin
versionCode = 28
versionName = "1.10.0-root-preview.12"
```

Set `module.prop` to `version=1.10.0-root-preview.12` and `versionCode=12`. Set both `MODULE_VERSION` constants to `1.10.0-root-preview.12`, and update package-test source/ZIP assertions to code 12 and Preview 12. Require no stale values:

```bash
rg -n 'root-preview\.11|versionCode=11|versionCode = 27' app root tools --glob '!app/build/**'
```

- [ ] **Step 2: Commit the version slice.**

```bash
git add app/build.gradle.kts root/kernelsu/yinxing_guard/module.prop root/kernelsu/yinxing_guard/bin/common.sh root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh tools/test-yinxing-guard.sh
git commit -m "chore: bump root preview 12 version"
```

- [ ] **Step 3: Run final shell and Android verification.**

```bash
/usr/bin/time -f 'ELAPSED_SECONDS=%e' bash tools/test-yinxing-guard.sh all
bash -n root/kernelsu/yinxing_guard/bin/*.sh tools/test-yinxing-guard.sh tools/package-yinxing-guard.sh
busybox ash -n root/kernelsu/yinxing_guard/bin/common.sh
env GRADLE_OPTS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888 -Dkotlin.incremental=false' \
    /usr/bin/time -f 'ELAPSED_SECONDS=%e' \
    bash ./gradlew :app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon --console=plain
```

Parse `app/build/test-results/testDebugUnitTest/TEST-*.xml` using Ruby `REXML`, recording totals and requiring zero failures, errors, and skips.

- [ ] **Step 4: Generate deterministic assets and verify metadata.**

Create `out/release/yinxing-1.10.0-root-preview.12-debug.apk`, `out/release/yinxing-guard-1.10.0-root-preview.12.zip`, and basename-only `out/release/SHA256SUMS.txt`. Copy the Debug APK and run:

```bash
bash tools/package-yinxing-guard.sh out/release/yinxing-guard-1.10.0-root-preview.12.zip 1.10.0-root-preview.12
```

Verify `aapt2 dump badging` reports code 28/name Preview 12, `apksigner verify --verbose` validates v2, `unzip -t` passes, root entries/modes/1980 timestamps and module metadata are correct, and a second package matches with `cmp -s`.

- [ ] **Step 5: Write release notes and commit.**

Create `docs/release/yinxing-root-preview-12.md` containing exact assets/versions, the complete-three-header rule, first-enable gate, bounded persistent failure, unchanged Root authority, module-first installation, Debug caveat, Preview 11 rollback, timings/test totals/hashes, and no-local-device caveat. Then:

```bash
git diff --check
git add docs/release/yinxing-root-preview-12.md
git commit -m "docs: add root preview 12 release notes"
```

- [ ] **Step 6: Review, reproduce, merge, publish, and remotely verify.**

Review the full diff from `v1.10.0-root-preview.11` for authority expansion, unknown-output regression, first-enable behavior, version coverage, and test gaps. Fix every Critical/Important finding and rerun covering tests. Rerun forced Android build on final source and compare its APK and newly packaged module byte-for-byte with candidates.

From main, preserve `.planning/`, fetch `origin`, prove `origin/main` is an ancestor, fast-forward merge this branch, push feature and `main`, create/push annotated `v1.10.0-root-preview.12`, then publish a non-draft Release titled `银杏 Root 增强 Preview 12` with `--verify-tag`, committed notes, APK, ZIP, and checksums. Download assets to a fresh `mktemp -d` and verify checksums, ZIP, APK badging/signature, exact bytes, release body, and remote `main`/feature/peeled-tag refs. Append exact release evidence plus remaining OnePlus 15 validation to user-owned `.planning` files without committing them.
