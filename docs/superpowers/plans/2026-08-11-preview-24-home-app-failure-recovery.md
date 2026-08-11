# Preview 24 Home App Failure Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the elderly home screen's transient external-app launch failure Toast with a persistent, large-target recovery dialog that offers an immediate retry and a caregiver settings route without changing successful launches.

**Architecture:** Keep `HomeAppLauncher` as the single launch/gate owner. Add a small dialog helper following the existing phone fallback-dialog pattern, then let `HomeNavigator` own one dialog reference, retry through the same launcher, open the existing `SettingsActivity`, and clear the reference on dismiss/destroy. No new service, timer, Root command, or package mutation is introduced.

**Tech Stack:** Kotlin, Android Views/XML, AppCompat `AlertDialog`, MaterialCardView, Robolectric/JUnit.

## Global Constraints

- The managed target is OnePlus 15 / China ColorOS 16 / KernelSU; this slice must remain valid without Root.
- Successful app resolution and `startActivity` behavior must remain unchanged and must not gain a probe, delay, animation, coroutine, or polling loop.
- Failure copy must be elderly-readable, omit package names and exception text, and provide a named next action.
- Retry must reuse the existing `HomeAppLauncher` so its 1.2-second duplicate gate is released after failure.
- Never automatically remove, disable, reorder, or rewrite a caregiver-selected app entry.
- Both dialog actions must be large stable targets (minimum `68dp`) with visible text and accessibility descriptions.
- Every production behavior change needs a test that was observed failing before implementation; run focused tests before broader verification.
- Do not touch Root, KernelSU module, BusyBox, manifest, services, or background scheduling.

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

- [x] **Step 1: Run the complete Android verification matrix**

```bash
bash gradlew testDebugUnitTest lintDebug assembleDebug --no-daemon --rerun-tasks
```

  Evidence: 80/80 tasks succeeded in 96.49 seconds; 59 JUnit XML files reported 449 tests, 0 failures,
  0 errors, and 0 skipped. `lintDebug` exited 1 with only the unchanged `RootCommandRunner.kt:72` and
  `:150` API 26 errors plus 135 warnings; no Preview24 file had a lint error.

- [x] **Step 2: Inspect the final UI/resource and behavioral diff**

Evidence: `git diff --check` passed; the focused tests assert one successful launch, both action targets
are at least 68dp with content descriptions, and the source diff contains no new timers/services/Root strings.

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

Evidence: final forced run succeeded (104.46 seconds); tests remained 449/0/0/0. Final lint classification is
two pre-existing RootCommandRunner API errors and no error in changed files.

- [x] **Step 3: Verify APK metadata, signature, checksums, and Root boundary**

Evidence: `aapt2` reports package `com.yinxing.launcher`, versionCode 40, versionName
`1.10.0-root-preview.24`, min/target 24/36; `apksigner` reports one Android Debug signer and v2=true.
`sha256sum -c` passed for `38f12bc412f2bd82e7156f112803dac857c4b22fd074844fddf76881c3755381`.
Root boundary scan is clean.

- [ ] **Step 4: Push, tag, publish, and fresh-download verify**

Commit metadata/release notes, push the feature branch, fast-forward/push `main`, create annotated tag `v1.10.0-root-preview.24`, and publish a non-draft prerelease to `Gs-ygc/yinxing`. Download both remote assets into a fresh temporary directory and require checksum success, byte-for-byte APK equality, exact asset names/body, remote branch/tag equality, and no device claims when `adb devices -l` is empty.
