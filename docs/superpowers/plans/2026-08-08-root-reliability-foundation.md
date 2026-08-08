# Root Reliability Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a rollback-capable Preview 1 for the fixed OnePlus 15/ColorOS 16/KernelSU device that restores Yinxing's accessibility registration and applies a narrowly allowlisted keepalive policy at boot.

**Architecture:** Add a standalone KernelSU module under `root/kernelsu/yinxing_guard`. Its POSIX shell library performs idempotent, fixed-target state repairs; `service.sh` runs the low-frequency guard and `action.sh` performs a one-shot caregiver repair. The Android APK remains the existing launcher and is versioned as a Debug preview; no generic Root executor is added to the APK in this slice.

**Tech Stack:** Android Gradle Plugin 9.1.1, Kotlin 2.2.0, Android SDK 36, POSIX shell/KernelSU module scripts, host Bash tests with fake Android commands, `zip`, `sha256sum`, GitHub CLI.

## Global Constraints

- Target device: OnePlus 15, China ColorOS 16, KernelSU, already Rooted.
- Preserve every pre-existing entry in `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES`.
- Never accept shell command text from app Intents, files, network input, or user text.
- Do not disable unrelated packages/services, change SELinux policy, or modify `/system` in Preview 1.
- No production code is written before its focused test has failed for the expected missing-behavior reason.
- APK preview uses the existing debug signing path because no release keystore is available in this workspace.
- Every release claim requires a fresh command with exit status and artifact inspection.

## Files and Responsibilities

- Create: `root/kernelsu/yinxing_guard/module.prop` — stable KernelSU module metadata.
- Create: `root/kernelsu/yinxing_guard/skip_mount` — explicit systemless/no-mount marker.
- Create: `root/kernelsu/yinxing_guard/service.sh` — KernelSU late-start entry point.
- Create: `root/kernelsu/yinxing_guard/action.sh` — one-shot repair action.
- Create: `root/kernelsu/yinxing_guard/uninstall.sh` — remove only the module-owned Doze whitelist marker/state.
- Create: `root/kernelsu/yinxing_guard/bin/common.sh` — constants, logging, command wrappers, state repair, and launcher start functions.
- Create: `root/kernelsu/yinxing_guard/bin/guard.sh` — boot wait, lock acquisition, initial repair, and health loop.
- Create: `tools/test-yinxing-guard.sh` — deterministic host test harness with fake `settings`, `pm`, `cmd`, `am`, and `getprop`.
- Create: `tools/package-yinxing-guard.sh` — reproducible ZIP builder and content validator.
- Modify: `app/build.gradle.kts:43-47` — increment Preview 1 `versionCode` and `versionName`.
- Create: `docs/release/yinxing-root-preview-1.md` — installation, acceptance, limitations, and rollback notes.

## Task 1: Establish Failing Shell Tests

**Files:**
- Create: `tools/test-yinxing-guard.sh`
- Test target: `root/kernelsu/yinxing_guard/bin/common.sh`

**Interfaces:**
- Consumes: test-only fake command directory and temporary state directory.
- Produces: executable assertions for `repair_state`, `merge_accessibility_services`, and `launch_home` that later scripts must satisfy.

- [ ] **Step 1: Write the failing test harness**

Create a Bash script that creates a temporary fake command directory and state files. The first line after setup sources `root/kernelsu/yinxing_guard/bin/common.sh`; the file is intentionally absent at this point. Add assertions for these behaviors:

```bash
assert_contains() { grep -F -- "$2" "$1" >/dev/null; }
assert_not_contains() { ! grep -F -- "$2" "$1" >/dev/null; }

# Empty setting gets exactly the Yinxing service and accessibility is enabled.
# Existing `talkback:other` stays intact and Yinxing is appended once.
# A second repair is idempotent and does not append a duplicate.
# Missing package exits non-zero and emits no settings/launch mutation.
# A failed optional app-op still leaves accessibility repair successful.
```

Fake commands must log argv to `$TEST_ROOT/calls.log`, maintain `$TEST_ROOT/accessibility_services`, and return controlled statuses through flags such as `$TEST_ROOT/fail_appops` and `$TEST_ROOT/package_missing`.

- [ ] **Step 2: Run the focused test and verify the expected RED failure**

Run:

```bash
bash tools/test-yinxing-guard.sh
```

Expected: non-zero exit because `root/kernelsu/yinxing_guard/bin/common.sh` does not exist. Fix only test-harness mistakes if the failure is different; do not add production files yet.

## Task 2: Implement the Idempotent Root Policy

**Files:**
- Create: `root/kernelsu/yinxing_guard/module.prop`
- Create: `root/kernelsu/yinxing_guard/skip_mount`
- Create: `root/kernelsu/yinxing_guard/bin/common.sh`
- Create: `root/kernelsu/yinxing_guard/bin/guard.sh`
- Create: `root/kernelsu/yinxing_guard/service.sh`
- Create: `root/kernelsu/yinxing_guard/action.sh`
- Create: `root/kernelsu/yinxing_guard/uninstall.sh`
- Test: `tools/test-yinxing-guard.sh`

**Interfaces:**
- `merge_accessibility_services(current, component)` prints the original colon-delimited value plus the component exactly once.
- `repair_state()` returns success only when the package exists and the required accessibility setting write succeeds; optional Doze/app-op failures are logged and do not abort the repair.
- `launch_home()` runs only the fixed `com.yinxing.launcher/.feature.home.MainActivity` component for user 0.
- `guard.sh` calls `repair_state` once after `sys.boot_completed=1`, launches HOME once, then repeats `repair_state` at `YINXING_GUARD_INTERVAL_SECONDS` (default 60).

- [ ] **Step 1: Implement the smallest pure merge helper**

Add `merge_accessibility_services` to `common.sh`. Treat `null`, empty output, and whitespace-only output as empty. Use exact colon-delimited membership (`case ":$current:"`) so a service named `...Service2` cannot match `...Service`. Quote the fixed component before passing it to `settings`.

- [ ] **Step 2: Run the focused test and verify GREEN for merge cases**

Run:

```bash
bash tools/test-yinxing-guard.sh --merge-only
```

Expected: empty, existing, duplicate, and substring-collision cases pass.

- [ ] **Step 3: Implement package/component and accessibility repair**

`repair_accessibility` must:

```sh
if ! pm path --user 0 "$PACKAGE_NAME" >/dev/null 2>&1; then
    log "package_missing"
    return 1
fi
pm enable --user 0 "$PACKAGE_NAME" >/dev/null 2>&1 || log "package_enable_failed"
pm enable --user 0 "$ACCESSIBILITY_COMPONENT" >/dev/null 2>&1 || log "service_enable_failed"
current=$(settings --user 0 get secure enabled_accessibility_services 2>/dev/null || true)
merged=$(merge_accessibility_services "$current" "$ACCESSIBILITY_COMPONENT")
if [ "$merged" != "$current" ]; then
    settings --user 0 put secure enabled_accessibility_services "$merged" || return 1
fi
settings --user 0 put secure accessibility_enabled 1 || return 1
```

The implementation must not clear or replace unrelated services. It must log each failed command with a stable action name, never command output containing user data.

- [ ] **Step 4: Add optional keepalive policy and verify failure isolation**

Implement `repair_keepalive` with independent commands:

```sh
cmd deviceidle whitelist +com.yinxing.launcher >/dev/null 2>&1 || log "doze_whitelist_failed"
cmd appops set --user 0 com.yinxing.launcher RUN_IN_BACKGROUND allow >/dev/null 2>&1 || log "background_appop_unsupported"
cmd appops set --user 0 com.yinxing.launcher RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1 || log "any_background_appop_unsupported"
```

`repair_state` calls accessibility repair first, then optional keepalive policy. The focused test must prove an app-op failure does not prevent accessibility repair or later checks.

- [ ] **Step 5: Implement boot entry, lock, loop, action, and uninstall behavior**

`guard.sh` waits for `getprop sys.boot_completed` with a bounded sleep interval, writes a PID/boot marker under `/data/adb/yinxing_guard`, and exits if a live guard already owns the marker. It performs one repair and one HOME launch, then sleeps 60 seconds between health passes. Test-only overrides are accepted through `YINXING_GUARD_BOOT_WAIT_SECONDS`, `YINXING_GUARD_INTERVAL_SECONDS`, and `YINXING_GUARD_MAX_CYCLES`.

`service.sh` sets a restricted Android command `PATH`, starts `guard.sh` once, and exits. `action.sh` performs one repair and HOME launch. `uninstall.sh` removes the Doze whitelist only when the module-owned marker says this module added it, then removes its exact runtime state directory; it does not touch accessibility settings.

- [ ] **Step 6: Run all focused shell tests and syntax checks**

Run:

```bash
bash tools/test-yinxing-guard.sh
sh -n root/kernelsu/yinxing_guard/service.sh
sh -n root/kernelsu/yinxing_guard/action.sh
sh -n root/kernelsu/yinxing_guard/uninstall.sh
sh -n root/kernelsu/yinxing_guard/bin/common.sh
sh -n root/kernelsu/yinxing_guard/bin/guard.sh
```

Expected: all assertions pass and every syntax command exits 0.

## Task 3: Add Reproducible Module Packaging

**Files:**
- Create: `tools/package-yinxing-guard.sh`
- Modify: `tools/test-yinxing-guard.sh`

**Interfaces:**
- Command: `bash tools/package-yinxing-guard.sh <output-zip> [module-version]`.
- Produces: a ZIP whose root contains `module.prop`, `skip_mount`, `service.sh`, `action.sh`, `uninstall.sh`, and `bin/` scripts; no host tests or `.git` files.

- [ ] **Step 1: Add a failing packaging assertion**

Extend the test harness to call the packaging script with an explicit temporary output path and assert the ZIP contains the required files, executable script modes, and no `tools/` or test fixtures. Run it before creating the packager and verify the expected missing-script failure.

- [ ] **Step 2: Implement packaging with explicit paths**

Use `zip -X -r` from the module's parent directory. Reject output paths that resolve inside the module source, remove only the exact requested output, and run `unzip -t` before returning success. If a version argument is supplied, write it into a temporary staged copy's `module.prop` rather than mutating the source.

- [ ] **Step 3: Run packaging and content tests**

Run:

```bash
bash tools/test-yinxing-guard.sh --package-only
```

Expected: ZIP content, permissions, and clean staging assertions pass.

## Task 4: Version and Device Release Notes

**Files:**
- Modify: `app/build.gradle.kts:43-47`
- Create: `docs/release/yinxing-root-preview-1.md`

- [ ] **Step 1: Bump the APK to `versionCode = 17`, `versionName = "1.10.0-root-preview.1"`**

Keep the application ID and signing configuration unchanged. Do not update the stable `docs/app-release.apk` or `docs/update.json` because this preview is Debug-signed and may not upgrade over a private-key stable install.

- [ ] **Step 2: Write exact installation and rollback instructions**

Document APK-first installation, KernelSU module installation, reboot, expected log tag `YinxingGuard`, the six device checks from the design, the Debug-signing clean-install limitation, and the module disable/uninstall recovery path. State clearly that device behavior is not verified on the build host.

- [ ] **Step 3: Run unit tests before implementation claims**

Run the focused shell tests and the existing Kotlin unit suite after the version change; record counts and failures in the progress log.

## Task 5: Build and Release Verification

**Files:**
- Create during verification only: `build/release-preview-1/` (ignored build output)
- No committed APK or private key changes.

- [ ] **Step 1: Package the module and calculate checksums**

Run:

```bash
mkdir -p build/release-preview-1
bash tools/package-yinxing-guard.sh build/release-preview-1/yinxing-guard-1.10.0-root-preview.1.zip
sha256sum app/build/outputs/apk/debug/app-debug.apk build/release-preview-1/yinxing-guard-1.10.0-root-preview.1.zip > build/release-preview-1/SHA256SUMS.txt
```

- [ ] **Step 2: Run the full local verification set**

Run with the known Java proxy properties and `ANDROID_HOME`:

```bash
bash gradlew :app:testDebugUnitTest :app:assembleDebug --no-daemon --console=plain
```

Also run `bash tools/test-yinxing-guard.sh` and `git diff --check`. Record direct exit codes, Gradle task results, APK path/size, ZIP test result, and checksums.

- [ ] **Step 3: Commit source changes and push the fork**

Stage only the Root module, packaging/test scripts, version metadata, release notes, and design/plan documents. Commit with:

```bash
git commit -m "feat: add KernelSU root reliability preview"
git push origin main
```

Verify `git status`, `git log -1`, and `git ls-remote origin refs/heads/main` after the push.

- [ ] **Step 4: Create a GitHub prerelease with exact artifacts**

Create tag `v1.10.0-root-preview.1` and upload only the freshly verified Debug APK, KernelSU ZIP, and `SHA256SUMS.txt`:

```bash
git tag -a v1.10.0-root-preview.1 -m "Yinxing Root reliability preview 1"
git push origin v1.10.0-root-preview.1
gh release create v1.10.0-root-preview.1 \
  app/build/outputs/apk/debug/app-debug.apk \
  build/release-preview-1/yinxing-guard-1.10.0-root-preview.1.zip \
  build/release-preview-1/SHA256SUMS.txt \
  --prerelease --title "银杏 Root 保活预览 1" --notes-file docs/release/yinxing-root-preview-1.md
```

Verify the release URL, asset names, tag target, and `gh release view v1.10.0-root-preview.1` output before reporting it.

## Ongoing Goal Handoff

After Preview 1 is released, leave the goal active for the next turn. Treat user device feedback as the next input, then add a new iteration phase and release tag rather than rewriting the first preview in place.
