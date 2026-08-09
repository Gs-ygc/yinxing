# Root Kiosk Home Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with verification checkpoints.

**Goal:** Add one fixed, cancellable KernelSU Root fallback that restores the Yinxing home activity when Kiosk mode has already tried normal Android foreground recovery and ColorOS still shows a system launcher.

**Architecture:** The module exposes a no-argument `bin/kiosk-home.sh` script that checks the active module and calls the existing fixed `launch_home()` helper. The APK adds `RootCommand.KIOSK_HOME` and an IO-bound `RootHomeLauncher`; `KioskLauncherGuard` invokes it only from a generation-bound final fallback after confirming Kiosk mode, no active automation session, and a known system-launcher package. Latest window-package tracking prevents a stale launcher event from overriding a user app.

**Tech Stack:** POSIX `/system/bin/sh`, KernelSU module ZIP packager, Kotlin/JVM tests, Robolectric, Kotlin coroutines, Android AccessibilityService.

## Global Constraints

- Root execution must use only the literal `/data/adb/modules/yinxing_guard/bin/kiosk-home.sh` path; no arbitrary shell, arguments, coordinates, UIAutomator, private ColorOS APIs, or process killing.
- The fallback is eligible only when Kiosk mode is enabled, no WeChat automation session is active, and the latest/active package is a known system launcher.
- Root execution is optional and cancellable; missing Root/module, non-zero exit, timeout, or output overflow must leave existing Android recovery unchanged.
- The command is attempted at most once per Kiosk recovery generation and must never block the service main thread.
- Module scripts remain POSIX `sh` and BusyBox `ash` compatible; ZIP entries stay at archive root, executable, and timestamp-normalized.
- Preserve the Debug APK release policy and increment Preview 8 APK/module version codes to Preview 9 (`25`/`9`) with name `1.10.0-root-preview.9`.

---

### Task 1: Fixed Root Home Command

**Files:**
- Create: `root/kernelsu/yinxing_guard/bin/kiosk-home.sh`
- Modify: `tools/test-yinxing-guard.sh`
- Modify: `tools/package-yinxing-guard.sh` only if the required-file list needs the new script

**Interfaces:**
- Consumes: existing `common.sh` variables `MODULE_VERSION`, `MODULE_DIR`-style test override, `HOME_COMPONENT`, and `launch_home()`.
- Produces: executable module script at `bin/kiosk-home.sh`; active module runs exactly one fixed `am start --user 0 -n com.yinxing.launcher/.feature.home.MainActivity` and returns its status.

- [ ] **Step 1: Add red shell tests for the fixed command.**

  Extend the test harness with `test_kiosk_home_command_is_bounded` and register it in `--guard-only`/`all`:

  ```bash
  test_kiosk_home_command_is_bounded() {
      reset_fixture
      mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
      run_module_script "$MODULE_ROOT/bin/kiosk-home.sh"
      assert_equals "1" "$(grep -c '^am start --user 0 -n com.yinxing.launcher/.feature.home.MainActivity$' "$CALLS" || true)" \
          "kiosk home command must launch the fixed activity once"

      reset_fixture
      mkdir -p "$YINXING_GUARD_TEST_MODULE_DIR"
      touch "$YINXING_GUARD_TEST_MODULE_DIR/disable"
      if run_module_script "$MODULE_ROOT/bin/kiosk-home.sh"; then
          fail "disabled module kiosk command unexpectedly succeeded"
      fi
      assert_equals "0" "$(grep -c '^am start ' "$CALLS" || true)" \
          "disabled module must not launch HOME"

      reset_fixture
      if run_module_script "$MODULE_ROOT/bin/kiosk-home.sh"; then
          fail "missing module kiosk command unexpectedly succeeded"
      fi
      assert_equals "0" "$(grep -c '^am start ' "$CALLS" || true)" \
          "missing module must not launch HOME"
      pass "fixed kiosk home command"
  }
  ```

  Add package assertions that `bin/kiosk-home.sh` is present, executable, and no extra module directory is archived.

- [ ] **Step 2: Run the shell tests and confirm the new test fails.**

  Run: `bash tools/test-yinxing-guard.sh --guard-only`

  Expected: FAIL because `bin/kiosk-home.sh` does not exist and the package file list does not contain it.

- [ ] **Step 3: Implement the bounded module script.**

  Create `bin/kiosk-home.sh`:

  ```sh
  #!/system/bin/sh

  MODDIR=${0%/*}
  . "$MODDIR/common.sh"

  MODULE_DIR="${YINXING_GUARD_TEST_MODULE_DIR:-/data/adb/modules/yinxing_guard}"
  if [ ! -d "$MODULE_DIR" ] || [ -e "$MODULE_DIR/disable" ] || [ -e "$MODULE_DIR/remove" ]; then
      exit 1
  fi

  launch_home
  ```

  Add the script to the packager's required list and ordered ZIP input list, and chmod it alongside the other module scripts.

- [ ] **Step 4: Run host and BusyBox shell tests.**

  Run: `bash tools/test-yinxing-guard.sh --guard-only`

  Expected: PASS, including the fixed command test and existing guard/service cases.

- [ ] **Step 5: Commit the module slice.**

  ```bash
  git add root/kernelsu/yinxing_guard/bin/kiosk-home.sh tools/test-yinxing-guard.sh tools/package-yinxing-guard.sh
  git commit -m "feat: add fixed root kiosk home command"
  ```

### Task 2: Cancellable APK Root Bridge

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/common/root/RootCommandRunner.kt`
- Create: `app/src/main/java/com/yinxing/launcher/common/root/RootHomeLauncher.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/common/root/RootCommandRunnerTest.kt`
- Create: `app/src/test/java/com/yinxing/launcher/common/root/RootHomeLauncherTest.kt`

**Interfaces:**
- Consumes: `RootCommandRunner.run(command: RootCommand)` and `RootCommandResult`.
- Produces: `RootCommand.KIOSK_HOME`, `RootHomeLauncher.launchHome(): Boolean` as a suspend function, and `SuRootHomeLauncher` using `runInterruptible(Dispatchers.IO)`.

- [ ] **Step 1: Add red JVM tests for command routing and fallback result mapping.**

  Update `usesOnlyTheFixedStatusAndRecoveryPaths` to accept the exact kiosk path and add:

  ```kotlin
  @Test
  fun rootHomeLauncherMapsFixedCommandSuccessAndFailure() = runTest {
      val calls = mutableListOf<RootCommand>()
      val success = object : RootCommandRunner {
          override fun run(command: RootCommand): RootCommandResult {
              calls += command
              return RootCommandResult(exitCode = 0, output = "")
          }
      }
      assertTrue(SuRootHomeLauncher(success).launchHome())
      assertEquals(listOf(RootCommand.KIOSK_HOME), calls)

      val failed = object : RootCommandRunner {
          override fun run(command: RootCommand) = RootCommandResult(exitCode = 1, output = "")
      }
      assertFalse(SuRootHomeLauncher(failed).launchHome())
  }
  ```

  Add a cancellation test with a runner that blocks until interrupted; assert the coroutine returns cancellation rather than leaking a worker. Keep the existing process timeout/output-limit tests unchanged.

- [ ] **Step 2: Run focused tests and confirm they fail to compile.**

  Run: `env GRADLE_OPTS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888' bash ./gradlew :app:testDebugUnitTest --tests com.yinxing.launcher.common.root.RootCommandRunnerTest --tests com.yinxing.launcher.common.root.RootHomeLauncherTest --no-daemon --console=plain`

  Expected: FAIL because `KIOSK_HOME`, `RootHomeLauncher`, and `SuRootHomeLauncher` are not defined.

- [ ] **Step 3: Implement the fixed command and suspend bridge.**

  Add `KIOSK_HOME` with `shellPath = "/data/adb/modules/yinxing_guard/bin/kiosk-home.sh"`. Extract the existing success predicate into an internal `RootCommandResult.isSuccessful` property so both health and kiosk bridges use the same `exitCode == 0 && !timedOut && !outputLimitExceeded` contract.

  Implement `RootHomeLauncher.kt`:

  ```kotlin
  internal fun interface RootHomeLauncher {
      suspend fun launchHome(): Boolean
  }

  internal class SuRootHomeLauncher(
      private val runner: RootCommandRunner = SuRootCommandRunner(timeoutMillis = 1_200L)
  ) : RootHomeLauncher {
      override suspend fun launchHome(): Boolean = runInterruptible(Dispatchers.IO) {
          try {
              runner.run(RootCommand.KIOSK_HOME).isSuccessful
          } catch (_: Exception) {
              false
          }
      }
  }
  ```

  Preserve `CancellationException` propagation from `runInterruptible`; do not swallow coroutine cancellation as a normal Root failure.

- [ ] **Step 4: Run focused tests and confirm they pass.**

  Run the focused Gradle command from Step 2. Expected: PASS with no timeout/output-limit regressions.

- [ ] **Step 5: Commit the APK bridge slice.**

  ```bash
  git add app/src/main/java/com/yinxing/launcher/common/root/RootCommandRunner.kt app/src/main/java/com/yinxing/launcher/common/root/RootHomeLauncher.kt app/src/test/java/com/yinxing/launcher/common/root/RootCommandRunnerTest.kt app/src/test/java/com/yinxing/launcher/common/root/RootHomeLauncherTest.kt
  git commit -m "feat: add cancellable root kiosk bridge"
  ```

### Task 3: Generation-Bound Kiosk Integration

**Files:**
- Modify: `app/src/main/java/com/google/android/accessibility/selecttospeak/KioskLauncherGuard.kt`
- Modify: `app/src/main/java/com/google/android/accessibility/selecttospeak/SelectToSpeakService.kt`
- Modify: `app/src/test/java/com/google/android/accessibility/selecttospeak/KioskLauncherGuardTest.kt`

**Interfaces:**
- Consumes: `RootHomeLauncher.launchHome()` and the existing `AutomationCallbackGeneration`/Kiosk preferences.
- Produces: latest-window package tracking, a cancellable `rootFallbackJob`, and one Root attempt per recovery generation.

- [ ] **Step 1: Add red Kiosk tests.**

  Inject `RootHomeLauncher` into `KioskLauncherGuard` with a default `SuRootHomeLauncher`, and add a recording fake in the test file. Cover these behaviors:

  ```kotlin
  @Test
  fun latestUserAppWindowSuppressesStaleLauncherRecovery() = runTest {
      val rootLauncher = RecordingRootHomeLauncher()
      val guard = newGuard(rootLauncher, activeSession = { false })
      assertTrue(guard.onWindowStateChanged(SYSTEM_HOME_PACKAGE, "Launcher"))
      assertFalse(guard.onWindowStateChanged("com.example.caregiver", "MainActivity"))
      advanceTimeBy(1_500L)
      runCurrent()
      assertEquals(0, rootLauncher.calls)
      assertNull(shadowOf(service).nextStartedActivity)
  }

  @Test
  fun rootFallbackRunsOnceWhenSystemLauncherStillVisible() = runTest {
      val rootLauncher = RecordingRootHomeLauncher(result = true)
      val guard = newGuard(rootLauncher, activeSession = { false })
      assertTrue(guard.onWindowStateChanged(SYSTEM_HOME_PACKAGE, "Launcher"))
      advanceTimeBy(1_500L)
      runCurrent()
      assertEquals(1, rootLauncher.calls)
  }

  @Test
  fun shutdownCancelsRootFallback() = runTest {
      val rootLauncher = RecordingRootHomeLauncher()
      val guard = newGuard(rootLauncher, activeSession = { false })
      assertTrue(guard.onWindowStateChanged(SYSTEM_HOME_PACKAGE, "Launcher"))
      guard.shutdown()
      advanceTimeBy(1_500L)
      runCurrent()
      assertEquals(0, rootLauncher.calls)
  }
  ```

  The fake must suspend on a `CompletableDeferred` when needed so the test can verify cancellation. Keep the existing transient-system-window and active-session expectations.

- [ ] **Step 2: Run focused Kiosk tests and confirm they fail.**

  Run: `env GRADLE_OPTS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888' bash ./gradlew :app:testDebugUnitTest --tests com.google.android.accessibility.selecttospeak.KioskLauncherGuardTest --no-daemon --console=plain`

  Expected: FAIL because the guard has no latest-window tracking, root fallback job, or injected launcher.

- [ ] **Step 3: Implement latest-window protection and Root fallback.**

  Add `rootHomeLauncher: RootHomeLauncher = SuRootHomeLauncher()` to the guard constructor, a `rootFallbackJob`, and a `latestWindowPackage` field. Update the field at the start of `onWindowStateChanged`; clear it in `shutdown`/`init` before a new lifecycle. Use the active root package when available, otherwise the latest observed package, then the original trigger only when no newer event exists.

  After the existing direct launch/pending-intent retry confirms a known system launcher still owns the active window, schedule one generation-bound job:

  ```kotlin
  rootFallbackJob = scope.launch {
      delay(ROOT_HOME_FALLBACK_DELAY_MS)
      if (!canExecuteRecovery(generation)) return@launch
      val activePackage = readActivePackage() ?: latestWindowPackage
      if (activePackage !in systemLauncherPackages) return@launch
      rootHomeLauncher.launchHome()
      if (callbackGeneration.isCurrent(generation)) rootFallbackJob = null
  }
  ```

  Recheck generation, Kiosk preference, active session, and package immediately before the suspend call. Cancel `rootFallbackJob` whenever the generation is invalidated. Log only fixed success/failure metadata; do not surface Root errors as terminal automation failures.

- [ ] **Step 4: Run focused Kiosk and Root tests.**

  Run both focused Gradle commands from Tasks 2 and 3. Expected: PASS, including cancellation and active-session suppression.

- [ ] **Step 5: Commit the Kiosk integration.**

  ```bash
  git add app/src/main/java/com/google/android/accessibility/selecttospeak/KioskLauncherGuard.kt app/src/main/java/com/google/android/accessibility/selecttospeak/SelectToSpeakService.kt app/src/test/java/com/google/android/accessibility/selecttospeak/KioskLauncherGuardTest.kt
  git commit -m "feat: add root-backed kiosk recovery fallback"
  ```

### Task 4: Preview 9 Versioning, Full Verification, and Release

**Files:**
- Modify: `app/build.gradle.kts`
- Modify: `root/kernelsu/yinxing_guard/module.prop`
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh`
- Modify: `root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh`
- Modify: `tools/test-yinxing-guard.sh`
- Create: `docs/release/yinxing-root-preview-9.md`
- Generate (ignored): `out/release/yinxing-1.10.0-root-preview.9-debug.apk`, `out/release/yinxing-guard-1.10.0-root-preview.9.zip`, `out/release/SHA256SUMS.txt`

**Interfaces:**
- Consumes: Tasks 1-3 passing on commit history.
- Produces: Preview 9 APK/module with synchronized version `1.10.0-root-preview.9`, code `25`/`9`, and a rollback-capable GitHub Release.

- [ ] **Step 1: Add version red assertions and update version metadata.**

  Update the source/version assertions from Preview 8 to Preview 9. Run `rg -n 'root-preview\.8|versionCode=8|versionCode = 24' app root tools` and ensure only historical release docs retain Preview 8 references.

- [ ] **Step 2: Run all local verification.**

  Run:

  ```bash
  bash tools/test-yinxing-guard.sh all
  bash -n tools/test-yinxing-guard.sh
  for script in root/kernelsu/yinxing_guard/*.sh root/kernelsu/yinxing_guard/bin/*.sh; do sh -n "$script"; busybox ash -n "$script"; done
  git diff --check
  ```

  Expected: host and BusyBox suites pass with no syntax or whitespace errors.

- [ ] **Step 3: Run Android tests and Debug build.**

  Run:

  ```bash
  env GRADLE_OPTS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888' \
    bash ./gradlew :app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon --console=plain
  ```

  Record direct Gradle status, external elapsed seconds, JUnit totals, `aapt2 dump badging`, and `apksigner verify --verbose`.

- [ ] **Step 4: Package and verify release assets.**

  Package the module with `bash tools/package-yinxing-guard.sh out/release/yinxing-guard-1.10.0-root-preview.9.zip 1.10.0-root-preview.9`, copy the Debug APK, write basename checksums, then verify `sha256sum -c`, `unzip -t`, root archive layout, executable modes, normalized timestamps, and deterministic repack.

- [ ] **Step 5: Write release notes and commit release source.**

  Include the fixed Root command, eligibility/cancellation semantics, install order, Debug-signing caveat, rollback to Preview 8, exact test/build timings, commit, and SHA-256 values in `docs/release/yinxing-root-preview-9.md`. Commit all source/docs changes with `feat: add root-backed kiosk recovery fallback` or a focused release commit.

- [ ] **Step 6: Merge, push, tag, publish, and remotely verify.**

  Fast-forward `main`, push `origin main`, create annotated tag `v1.10.0-root-preview.9`, push it, and run:

  ```bash
  gh release create v1.10.0-root-preview.9 --repo Gs-ygc/yinxing --verify-tag \
    --title '银杏 Root Kiosk 回桌面预览 9' \
    --notes-file docs/release/yinxing-root-preview-9.md \
    out/release/yinxing-1.10.0-root-preview.9-debug.apk \
    out/release/yinxing-guard-1.10.0-root-preview.9.zip \
    out/release/SHA256SUMS.txt
  ```

  Verify `git ls-remote`, `gh release view --json`, GitHub asset digests, and the Release URL before reporting the build ready for OnePlus 15 testing.
