# Preview 24 Home App Failure Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the elderly home screen's transient external-app launch failure Toast with a persistent, large-target recovery dialog, then incorporate the user's pre-release device feedback by replacing the generic Root failure state with evidence-based caregiver diagnostics.

**Architecture:** Keep `HomeAppLauncher` as the single launch/gate owner. Add a small dialog helper following the existing phone fallback-dialog pattern, then let `HomeNavigator` own one dialog reference, retry through the same launcher, open the existing `SettingsActivity`, and clear the reference on dismiss/destroy. For Root observability, classify the already existing fixed `su -c status.sh` result across process, authorization/script, timeout/output, and protocol layers; do not add a second probe, service, timer, or module mutation.

**Tech Stack:** Kotlin, Android Views/XML, AppCompat `AlertDialog`, MaterialCardView, coroutines, Robolectric/JUnit.

## User-directed amendment (2026-08-11)

Before Preview 24 was published, the user rejected the generic “Root 不可用” diagnosis because it hid
whether `su`, KernelSU authorization, module scripts, timeout, exit status, or status parsing had failed.
Preview 24 therefore also includes the narrowly scoped APK diagnostic work in Task 5. The Root Guard module,
boot behavior, keepalive policy, accessibility recovery, BusyBox assets, and background scheduling remain unchanged.

## Global Constraints

- The managed target is OnePlus 15 / China ColorOS 16 / KernelSU; this slice must remain valid without Root.
- Successful app resolution and `startActivity` behavior must remain unchanged and must not gain a probe, delay, animation, coroutine, or polling loop.
- Failure copy must be elderly-readable, omit package names and exception text, and provide a named next action.
- Retry must reuse the existing `HomeAppLauncher` so its 1.2-second duplicate gate is released after failure.
- Never automatically remove, disable, reorder, or rewrite a caregiver-selected app entry.
- Both dialog actions must be large stable targets (minimum `68dp`) with visible text and accessibility descriptions.
- Every production behavior change needs a test that was observed failing before implementation; run focused tests before broader verification.
- The home-app slice must not touch Root. The user-directed diagnostic amendment may modify only the APK's
  existing Root command result model/repository/settings rendering; do not modify the KernelSU module, BusyBox,
  manifest, services, boot scripts, keepalive policy, or background scheduling.

---

### Task 1: Add the elderly failure-dialog surface

**Files:**
- Create: `app/src/main/res/layout/dialog_home_app_failure.xml`
- Modify: `app/src/main/res/values/strings.xml` (add the four dialog strings near `open_app_failed`)
- Create: `app/src/main/java/com/yinxing/launcher/feature/home/HomeAppFailureDialog.kt`
- Create: `app/src/test/java/com/yinxing/launcher/feature/home/HomeAppFailureDialogTest.kt`

**Interfaces:**
- Produces `internal fun AppCompatActivity.showHomeAppFailureDialog(item: HomeAppItem, onRetry: () -> Unit, onOpenSettings: () -> Unit): AlertDialog`.
- The helper sets the title with `getString(R.string.home_app_failure_title, item.appName)`, the message with `getString(R.string.home_app_failure_message)`, and wires `btn_home_app_retry` / `btn_home_app_settings`.
- The helper shows the dialog with the existing transparent-window/card treatment and returns the shown `AlertDialog` so the caller can track lifecycle.

- [ ] **Step 1: Write the failing layout/helper tests**

Add tests that inflate the helper through a Robolectric `AppCompatActivity` and assert:

```kotlin
assertEquals("无法打开相机", title.text.toString())
assertEquals(context.getString(R.string.home_app_failure_message), message.text.toString())
assertEquals(context.getString(R.string.home_app_failure_retry), retry.text.toString())
assertEquals(context.getString(R.string.home_app_failure_settings), settings.text.toString())
assertTrue(retry.minimumHeight >= dp(68))
assertTrue(settings.minimumHeight >= dp(68))
assertEquals(retry.text, retry.contentDescription)
assertEquals(settings.text, settings.contentDescription)
```

Also click each button and assert the corresponding real callback counter increments once and the dialog is no longer showing.

- [ ] **Step 2: Run the focused test and verify the expected RED failure**

Run:

```bash
bash gradlew :app:testDebugUnitTest --tests com.yinxing.launcher.feature.home.HomeAppFailureDialogTest --no-daemon
```

Expected: compilation or resource failure because the new layout, IDs, strings, and helper do not yet exist.

- [ ] **Step 3: Implement the minimal dialog surface**

Use `dialog_call_permission_fallback.xml` as the visual reference. Create a single vertical card with:

```xml
android:minHeight="68dp"
android:ellipsize="end"
android:maxLines="2"
```

for each action target/title as appropriate. Use neutral copy such as “这个应用可能被停用、卸载，或暂时没有响应。可以再试一次；仍然打不开时，请让家属到设置里检查首页应用。” Do not expose the package name or thrown exception. Make the dialog cancelable and set the window background transparent and width to 92% of the display, matching the existing helper.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the same command from Step 2. Expected: all dialog tests pass with no failures.

- [ ] **Step 5: Commit the independently testable surface**

```bash
git add app/src/main/res/layout/dialog_home_app_failure.xml app/src/main/res/values/strings.xml app/src/main/java/com/yinxing/launcher/feature/home/HomeAppFailureDialog.kt app/src/test/java/com/yinxing/launcher/feature/home/HomeAppFailureDialogTest.kt
git commit -m "feat: add elderly home app failure dialog"
```

### Task 2: Wire retry and caregiver recovery into HomeNavigator

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/feature/home/HomeNavigator.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/feature/home/MainActivity.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/feature/home/MainActivitySmokeTest.kt`
- Create: `app/src/test/java/com/yinxing/launcher/feature/home/HomeNavigatorFailureRecoveryTest.kt`

**Interfaces:**
- `HomeNavigator` keeps `private var appFailureDialog: AlertDialog?` and exposes `fun dismissTransientDialogs()` for Activity teardown.
- Its existing `HomeAppLauncher.onUnavailable` callback calls `showAppFailure(item)`; no launch-gate logic moves out of `HomeAppLauncher`.
- `showAppFailure` calls `showHomeAppFailureDialog`, retries with `appLauncher.open(item)`, and opens `Intent(activity, SettingsActivity::class.java)` for the caregiver action.
- `MainActivity.onDestroy()` calls `navigator.dismissTransientDialogs()` before the Activity is torn down.

- [ ] **Step 1: Write the failing integration tests**

Add tests that use a missing package and a registered package to prove:

```kotlin
// Missing package: a persistent dialog replaces the old Toast.
HomeNavigator(activity).openHomeItem(missingItem)
assertTrue(ShadowAlertDialog.getLatestAlertDialog().isShowing)

// Settings action reaches the existing caregiver Activity.
click(R.id.btn_home_app_settings)
assertEquals(SettingsActivity::class.java.name, shadowOf(activity).nextStartedActivity.component?.className)

// A failure releases the gate and a retry can launch after a resolver becomes available.
click(R.id.btn_home_app_retry)
assertEquals("pkg.camera", shadowOf(activity).nextStartedActivity.component?.packageName)
```

Update the existing `unavailableExternalAppShowsFailureWithoutStartingActivity` assertion to inspect the dialog title/actions rather than a Toast. Add a success assertion that no failure dialog is shown after a normal launch.

- [ ] **Step 2: Run the focused integration tests and verify RED**

```bash
bash gradlew :app:testDebugUnitTest --tests com.yinxing.launcher.feature.home.HomeNavigatorFailureRecoveryTest --tests com.yinxing.launcher.feature.home.MainActivitySmokeTest.unavailableExternalAppShowsFailureWithoutStartingActivity --no-daemon
```

Expected: tests fail because `HomeNavigator` still emits a Toast and does not expose the new dialog actions.

- [ ] **Step 3: Implement minimal wiring and lifecycle cleanup**

Replace only the `onUnavailable` Toast callback with the dialog helper. Dismiss any existing `appFailureDialog` before showing a replacement, clear the field from `setOnDismissListener`, and guard `isFinishing || isDestroyed`. Retry must dismiss first and then call the same `appLauncher.open(item)`; do not add a second launch path. The caregiver button opens `SettingsActivity`. Call `dismissTransientDialogs()` from `MainActivity.onDestroy()`.

- [ ] **Step 4: Run focused tests and then the home/phone smoke slice**

```bash
bash gradlew :app:testDebugUnitTest --tests com.yinxing.launcher.feature.home.HomeNavigatorFailureRecoveryTest --tests com.yinxing.launcher.feature.home.MainActivitySmokeTest --tests com.yinxing.launcher.feature.phone.PhoneCallLauncherTest --no-daemon
```

Expected: all selected tests pass; existing outgoing-call fallback behavior remains unchanged.

- [ ] **Step 5: Review the diff and commit the wiring**

```bash
git diff --check
git diff --stat main...HEAD
git add app/src/main/java/com/yinxing/launcher/feature/home/HomeNavigator.kt app/src/main/java/com/yinxing/launcher/feature/home/MainActivity.kt app/src/test/java/com/yinxing/launcher/feature/home/MainActivitySmokeTest.kt app/src/test/java/com/yinxing/launcher/feature/home/HomeNavigatorFailureRecoveryTest.kt
git commit -m "feat: make home app handoff failures recoverable"
```

### Task 3: Branch-level verification and review readiness

**Files:**
- Modify: `docs/superpowers/specs/2026-08-11-preview-24-home-app-failure-recovery-design.md` only if review finds a design correction.
- Modify: `docs/superpowers/plans/2026-08-11-preview-24-home-app-failure-recovery.md` to mark completed steps and record evidence.

- [x] **Step 1: Run the pre-amendment Android verification matrix (historical)**

```bash
bash gradlew testDebugUnitTest lintDebug assembleDebug --no-daemon --rerun-tasks
```

  Pre-amendment evidence: 80/80 tasks succeeded in 96.49 seconds; 59 JUnit XML files reported 449 tests, 0 failures,
  0 errors, and 0 skipped. `lintDebug` exited 1 with only the unchanged `RootCommandRunner.kt:72` and
  `:150` API 26 errors plus 135 warnings; no Preview24 file had a lint error.

- [x] **Step 2: Inspect the final UI/resource and behavioral diff**

Evidence before the user-directed Task 5 amendment: `git diff --check` passed; the focused tests assert one
successful launch, and both action targets are at least 68dp with content descriptions. Task 5 separately
verifies that its Root diagnostic change adds no timer, service, or background command.

- [x] **Step 3: Commit verification evidence and hand off for independent review**

Evidence: Task 2 commit `b336444` received an independent review with no findings; release packaging is
complete below. The known lint baseline is documented separately from the green test/build evidence.

### Task 4: Version, package, and publish Preview 24

**Files:**
- Modify: `app/build.gradle.kts` (`versionCode=40`, `versionName="1.10.0-root-preview.24"`)
- Create: `docs/release/yinxing-root-preview-24.md`
- Create: `out/release/yinxing-1.10.0-root-preview.24-debug.apk` (generated, not committed)
- Create: `out/release/SHA256SUMS.txt` (generated, not committed)

**Interfaces:**
- Produces one Debug APK and its checksum under the exact release names above.
- Publishes GitHub prerelease tag `v1.10.0-root-preview.24` with exactly those two assets.
- Links the unchanged Preview 18 KernelSU module; no Root module asset is rebuilt or uploaded.

- [x] **Step 1: Write release metadata and elderly acceptance notes**

Set the exact app metadata (done):

```kotlin
versionCode = 40
versionName = "1.10.0-root-preview.24"
```

Documented in `docs/release/yinxing-root-preview-24.md`.

- [x] **Step 2: Run final forced verification and classify lint**

Run in isolation with the known complete cache:

```bash
/usr/bin/time -f 'ELAPSED_SECONDS=%e EXIT_STATUS=%x' \
  env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest \
  --rerun-tasks --no-daemon --console=plain
```

Evidence after the user-directed diagnostic amendment: final forced run succeeded (97.39 seconds), 80/80 tasks
executed, and 59 JUnit XML files reported 462 tests, 0 failures, 0 errors, and 0 skipped. Final lint found the
same two inherited `Process.waitFor(timeout)` API 26 errors at current lines 106/184 plus 135 warnings; no new
diagnostic-specific lint finding was introduced.

- [x] **Step 3: Verify APK metadata, signature, checksums, and Root boundary**

Evidence: `aapt2` reports package `com.yinxing.launcher`, versionCode 40, versionName
`1.10.0-root-preview.24`, min/target 24/36; `apksigner` reports one Android Debug signer and v2=true.
`sha256sum -c` passed for `ec03e3b490ca91074086102a1e89e7a83d951078abf1f71b9dc4cd93cda186b1`;
the APK is 8,681,655 bytes. The branch diff has no `root/` module, manifest, service, or background-scheduling
change.

### Task 5: Replace generic Root failure output with evidence-based diagnostics

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/common/root/RootCommandRunner.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/common/root/RootHealthRepository.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/common/root/RootHealthSnapshot.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/feature/settings/SettingsRootHealthSheet.kt`
- Modify: `app/src/main/res/values/strings.xml`
- Modify: focused Root/repository/settings tests
- Create: `docs/superpowers/specs/2026-08-11-preview-24-root-failure-diagnostics-design.md`

- [x] **Step 1: Add failing tests for exact failure categories**

Evidence: focused compilation failed only because `KERNEL_SU_EXECUTABLE` and
`SCRIPT_EXECUTION_BLOCKED` did not exist. Earlier red runs likewise proved the missing reason/exit-code fields
and status-format mapping before implementation. Review-driven red tests then failed on generic permission and
internal dependency misclassification, and `SCRIPT_UNAVAILABLE` failed compilation before the AOSP ambiguity
state was implemented. A separate first attempt that timed out downloading Gradle is infrastructure noise, not
test evidence.

- [x] **Step 2: Implement classification without adding probes**

Evidence: the runner now uses KernelSU's `/system/bin/su` compatibility entry and classifies start failure,
direct Root Guard script denial/missing path, AOSP's ambiguous `inaccessible or not found`, unqualified
permission denial, timeout, output overflow, generic exit code, and status format. Review corrections removed
over-broad authorization and `not found` inference: only canonical errors ending in a fixed script path receive
a script-specific label, while the AOSP phrase remains explicitly ambiguous. The repository preserves both
status and recovery-action failures. UI badges and summaries show the observed reason, current UID where
KernelSU ambiguity is unavoidable, and the next action.

- [x] **Step 3: Run the complete Root/settings regression slice**

```bash
/usr/bin/time -p env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.common.root.*' \
  --tests com.yinxing.launcher.feature.settings.SettingsActivitySmokeTest \
  --no-daemon --console=plain
```

Evidence: 62 tests, 0 failures, 0 errors, 0 skipped; Gradle succeeded in 35.71 seconds.

- [x] **Step 4: Run final full verification and independent review**

Evidence: the final full build, lint classification, APK metadata/signature/hash checks, and `git diff --check`
are recorded above. Two independent review passes found three over-inference issues; each was fixed with a red
regression test. Final re-review reported no blocking code finding and confirmed no module/BusyBox/background
change. No ADB device was connected, so no OnePlus 15 runtime claim was made.

### Task 6: Push, tag, publish, and fresh-download verify

- [ ] **Step 1: Publish only after Task 5 verification**

Commit metadata/release notes, push the feature branch, fast-forward/push `main`, create annotated tag `v1.10.0-root-preview.24`, and publish a non-draft prerelease to `Gs-ygc/yinxing`. Download both remote assets into a fresh temporary directory and require checksum success, byte-for-byte APK equality, exact asset names/body, remote branch/tag equality, and no device claims when `adb devices -l` is empty.
