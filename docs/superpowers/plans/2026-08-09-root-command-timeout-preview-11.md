# Root Command Timeout Preview 11 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the fixed Root recovery command enough time to complete Preview 10 accessibility confirmation without weakening status or Kiosk failure bounds, then publish Preview 11.

**Architecture:** Each existing `RootCommand` owns its literal allowlisted path and finite timeout. `SuRootCommandRunner` uses the command budget in production while retaining one optional uniform timeout override for deterministic tests; the process/output/cancellation implementation and Root authority surface remain unchanged.

**Tech Stack:** Kotlin/JVM, Java `Process`, kotlinx coroutines, JUnit 4, POSIX `/system/bin/sh`, KernelSU standalone BusyBox `ash`, Gradle 9.3.1, Android Debug APK packaging, GitHub CLI.

## Global Constraints

- Target OnePlus 15 China ColorOS 16 with KernelSU on a user-controlled rooted appliance.
- Root commands remain exactly the no-argument fixed paths `status.sh`, `action.sh`, and `kiosk-home.sh`; no arbitrary shell, arguments, package, component, coordinates, process killing, or private ColorOS API.
- Production timeout budgets are exactly `STATUS=3_000L`, `RECOVER=12_000L`, and `KIOSK_HOME=1_200L` milliseconds.
- A supplied `SuRootCommandRunner(timeoutMillis=...)` remains a positive, uniform test/caller override; `null` selects the command budget.
- Process interruption, output limit, error-stream merge, graceful/forced termination, and fail-closed result semantics remain unchanged.
- Preview 10's five accessibility confirmation polls, one-second confirmed-crash intervals, one exact remove/restore pair, and unknown-output safety remain unchanged.
- Preview 11 versions are APK `versionCode=27`, module `versionCode=11`, and `versionName=1.10.0-root-preview.11`.
- Release assets remain a Debug APK, KernelSU module ZIP, basename-only `SHA256SUMS.txt`, committed notes, annotated tag, and fresh remote-download verification.

---

### Task 1: Recovery Timeout Regression

**Files:**
- Modify: `app/src/test/java/com/yinxing/launcher/common/root/RootCommandRunnerTest.kt`

**Interfaces:**
- Consumes: current default `SuRootCommandRunner()`, fixed `RootCommand.RECOVER`, and existing `withFakeSu()` host-process fixture.
- Produces: real-process regressions proving four-second recovery succeeds while two-second Kiosk and four-second status commands remain bounded.

- [ ] **Step 1: Add the real-process recovery regression.**

Insert after `usesOnlyTheFixedStatusRecoveryAndKioskPaths()`:

```kotlin
@Test
fun defaultRecoveryTimeoutCoversBoundedRebindConfirmation() {
    withFakeSu(
        """
        case "${'$'}2" in
            /data/adb/modules/yinxing_guard/action.sh) /bin/sleep 4 ;;
            *) exit 64 ;;
        esac
        """.trimIndent()
    ) { executable ->
        val runner = SuRootCommandRunner(
            maxOutputBytes = 1_024,
            suExecutable = executable.toString()
        )

        val result = runner.run(RootCommand.RECOVER)

        assertFalse("recovery hit the shared three-second timeout", result.timedOut)
        assertTrue(result.isSuccessful)
    }
}
```

Add two behavior-preservation tests using the same real fixture:

```kotlin
@Test
fun defaultKioskTimeoutRemainsShort() {
    withFakeSu(
        """
        case "${'$'}2" in
            /data/adb/modules/yinxing_guard/bin/kiosk-home.sh) /bin/sleep 2 ;;
            *) exit 64 ;;
        esac
        """.trimIndent()
    ) { executable ->
        val runner = SuRootCommandRunner(
            maxOutputBytes = 1_024,
            suExecutable = executable.toString()
        )

        val result = runner.run(RootCommand.KIOSK_HOME)

        assertTrue(result.timedOut)
        assertFalse(result.isSuccessful)
    }
}

@Test
fun defaultStatusTimeoutRemainsBounded() {
    withFakeSu(
        """
        case "${'$'}2" in
            /data/adb/modules/yinxing_guard/bin/status.sh) /bin/sleep 4 ;;
            *) exit 64 ;;
        esac
        """.trimIndent()
    ) { executable ->
        val runner = SuRootCommandRunner(
            maxOutputBytes = 1_024,
            suExecutable = executable.toString()
        )

        val result = runner.run(RootCommand.STATUS)

        assertTrue(result.timedOut)
        assertFalse(result.isSuccessful)
    }
}
```

Do not weaken `timeoutForciblyStopsAStuckSuProcessWithinBound()` or replace its explicit 100 ms override.

- [ ] **Step 2: Run the focused test and observe RED.**

Run:

```bash
env GRADLE_OPTS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888' \
    bash ./gradlew :app:testDebugUnitTest \
    --tests com.yinxing.launcher.common.root.RootCommandRunnerTest \
    --no-daemon --console=plain
```

Expected: recovery fails because the result has `timedOut=true` after the current 3,000 ms default; Kiosk fails because the shared 3,000 ms default lets its two-second process succeed. The status preservation test, fixed-path test, 100 ms stuck-process test, and output-limit test remain green.

- [ ] **Step 3: Run static checks for the red slice.**

```bash
git diff --check
git status --short
```

Expected: only `RootCommandRunnerTest.kt` is modified and the diff check exits 0.

- [ ] **Step 4: Commit the red regression.**

```bash
git add app/src/test/java/com/yinxing/launcher/common/root/RootCommandRunnerTest.kt
git commit -m "test: expose root recovery timeout mismatch"
```

---

### Task 2: Command-Specific Timeout Budgets

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/common/root/RootCommandRunner.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/common/root/RootHomeLauncher.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/common/root/RootCommandRunnerTest.kt`

**Interfaces:**
- Consumes: `RootCommand`, `SuRootCommandRunner(timeoutMillis, maxOutputBytes, suExecutable)`, `RootCommandResult`, and the Task 1 regression.
- Produces: `RootCommand(shellPath: String, timeoutMillis: Long)` and runner resolution `timeoutMillis ?: command.timeoutMillis`.

- [ ] **Step 1: Make path and budget one fixed enum contract.**

Replace the current enum body with:

```kotlin
internal enum class RootCommand(
    val shellPath: String,
    val timeoutMillis: Long
) {
    STATUS(
        shellPath = "/data/adb/modules/yinxing_guard/bin/status.sh",
        timeoutMillis = 3_000L
    ),
    RECOVER(
        shellPath = "/data/adb/modules/yinxing_guard/action.sh",
        timeoutMillis = 12_000L
    ),
    KIOSK_HOME(
        shellPath = "/data/adb/modules/yinxing_guard/bin/kiosk-home.sh",
        timeoutMillis = 1_200L
    )
}
```

No method may concatenate, accept, or transform a path or argument.

- [ ] **Step 2: Make the constructor timeout an optional uniform override.**

Change the constructor field to:

```kotlin
private val timeoutMillis: Long? = null
```

Change validation to:

```kotlin
require(timeoutMillis == null || timeoutMillis > 0) { "timeoutMillis must be positive" }
```

Immediately before `process.waitFor`, resolve:

```kotlin
val commandTimeoutMillis = timeoutMillis ?: command.timeoutMillis
```

and pass `commandTimeoutMillis` to `waitFor`. Remove the obsolete shared `DEFAULT_TIMEOUT_MILLIS`; keep every termination and reader constant unchanged.

- [ ] **Step 3: Remove the duplicate Kiosk timeout definition.**

Change the default runner in `SuRootHomeLauncher` to:

```kotlin
private val runner: RootCommandRunner = SuRootCommandRunner()
```

Remove its companion object containing `DEFAULT_TIMEOUT_MILLIS`. Injection of a fake `RootCommandRunner` and cancellation/error handling remain unchanged.

- [ ] **Step 4: Run the focused Root JVM suite and observe GREEN.**

```bash
env GRADLE_OPTS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888' \
    bash ./gradlew :app:testDebugUnitTest \
    --tests 'com.yinxing.launcher.common.root.*' \
    --no-daemon --console=plain
```

Expected: the four-second default recovery succeeds; two-second Kiosk and four-second status processes time out; the 100 ms override still terminates the 30-second process within 1.5 seconds; output overflow remains bounded and repository tests stay green.

- [ ] **Step 5: Run source and diff checks.**

```bash
rg -n 'DEFAULT_TIMEOUT_MILLIS|timeoutMillis = 3_000|timeoutMillis = 12_000|timeoutMillis = 1_200' \
    app/src/main/java/com/yinxing/launcher/common/root \
    app/src/test/java/com/yinxing/launcher/common/root
git diff --check
```

Expected: no duplicate `DEFAULT_TIMEOUT_MILLIS`; one exact enum budget per command; diff check exits 0.

- [ ] **Step 6: Commit the implementation.**

```bash
git add \
    app/src/main/java/com/yinxing/launcher/common/root/RootCommandRunner.kt \
    app/src/main/java/com/yinxing/launcher/common/root/RootHomeLauncher.kt \
    app/src/test/java/com/yinxing/launcher/common/root/RootCommandRunnerTest.kt
git commit -m "fix: align root recovery timeout budget"
```

---

### Task 3: Preview 11 Version, Full Verification, And Release

**Files:**
- Modify: `app/build.gradle.kts`
- Modify: `root/kernelsu/yinxing_guard/module.prop`
- Modify: `root/kernelsu/yinxing_guard/bin/common.sh`
- Modify: `root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh`
- Modify: `tools/test-yinxing-guard.sh`
- Create: `docs/release/yinxing-root-preview-11.md`

**Interfaces:**
- Consumes: verified command-aware runner, Debug APK output `app/build/outputs/apk/debug/app-debug.apk`, and `tools/package-yinxing-guard.sh`.
- Produces: source commit and annotated tag `v1.10.0-root-preview.11`, APK/module/checksum assets, committed release notes, and fresh remote verification evidence.

- [ ] **Step 1: Bump every exact version source.**

Set APK:

```kotlin
versionCode = 27
versionName = "1.10.0-root-preview.11"
```

Set module `version=1.10.0-root-preview.11`, `versionCode=11`, and both shell `MODULE_VERSION` constants to `1.10.0-root-preview.11`. Update package-test source/ZIP assertions to code 11 and Preview 11.

Run:

```bash
rg -n 'root-preview\.10|versionCode=10|versionCode = 26' app root tools --glob '!app/build/**'
```

Expected: no current-version hits remain outside historical docs and plans.

- [ ] **Step 2: Commit the version slice.**

```bash
git add \
    app/build.gradle.kts \
    root/kernelsu/yinxing_guard/module.prop \
    root/kernelsu/yinxing_guard/bin/common.sh \
    root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh \
    tools/test-yinxing-guard.sh
git commit -m "chore: bump root preview 11 version"
```

- [ ] **Step 3: Run final shell verification with timing.**

```bash
/usr/bin/time -f 'ELAPSED_SECONDS=%e' bash tools/test-yinxing-guard.sh all
bash -n root/kernelsu/yinxing_guard/bin/*.sh tools/test-yinxing-guard.sh tools/package-yinxing-guard.sh
busybox ash -n root/kernelsu/yinxing_guard/bin/common.sh
git diff --check
```

Expected: host Bash and recursive standalone BusyBox `ash` suites pass; both syntax checks and the diff check exit 0. Record exact elapsed time.

- [ ] **Step 4: Run a fresh full Android test and Debug build.**

```bash
env GRADLE_OPTS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888 -Dkotlin.incremental=false' \
    /usr/bin/time -f 'ELAPSED_SECONDS=%e' \
    bash ./gradlew :app:testDebugUnitTest :app:assembleDebug \
    --rerun-tasks --no-daemon --console=plain
```

Expected: exit 0, `assembleDebug` succeeds, and every XML test suite has zero failures, errors, and skips. Parse the XML reports with a structured parser and record exact tests and elapsed seconds.

- [ ] **Step 5: Generate and verify deterministic assets.**

Create:

```text
out/release/yinxing-1.10.0-root-preview.11-debug.apk
out/release/yinxing-guard-1.10.0-root-preview.11.zip
out/release/SHA256SUMS.txt
```

Copy the final Debug APK, run the module packager with version `1.10.0-root-preview.11`, and generate `SHA256SUMS.txt` from inside `out/release` so both entries contain basenames only.

Verify:

```bash
/nfs/home/leguochun/android-sdk/build-tools/36.0.0/aapt2 dump badging out/release/yinxing-1.10.0-root-preview.11-debug.apk
/nfs/home/leguochun/android-sdk/build-tools/36.0.0/apksigner verify --verbose out/release/yinxing-1.10.0-root-preview.11-debug.apk
unzip -t out/release/yinxing-guard-1.10.0-root-preview.11.zip
```

Also verify module root entries, executable modes, 1980-01-01 timestamps, metadata code/name, and a second packager output with `cmp -s`.

- [ ] **Step 6: Write and commit release notes.**

Create `docs/release/yinxing-root-preview-11.md` containing:

- exact APK/module filenames and versions;
- the three-command timeout table and why recovery alone is longer;
- unchanged literal Root paths and fail-closed process/output behavior;
- KernelSU-module-first installation order and Debug-signing caveat;
- rollback to Preview 10;
- exact shell/Gradle timings, Android test totals, and both SHA-256 values;
- explicit statement that no OnePlus 15 was connected locally.

Run `git diff --check`, then commit with `docs: add root preview 11 release notes`.

- [ ] **Step 7: Perform whole-branch review and final tagged-source reproduction.**

Review the complete diff from `v1.10.0-root-preview.10` through `HEAD` for exact spec coverage and unintended authority expansion. Correct every Critical/Important finding, rerun covering tests, then rerun the forced Android command on the final source and compare the rebuilt APK with the release candidate using `cmp -s`. Repackage the module and compare it byte-for-byte as well.

- [ ] **Step 8: Fast-forward and push source plus annotated tag.**

From the main worktree, require only the user-owned `.planning/` path to be untracked. Fetch `origin`, prove `origin/main` is an ancestor of the feature branch, then run:

```bash
git merge --ff-only feat/root-command-timeout-preview-11
git push --set-upstream origin feat/root-command-timeout-preview-11
git push origin main
git tag -a v1.10.0-root-preview.11 -m "Yinxing Root Guard Preview 11"
git push origin v1.10.0-root-preview.11
```

Expected: remote feature branch, `main`, and peeled tag all resolve to the same source commit.

- [ ] **Step 9: Publish and remotely verify GitHub assets.**

Create a non-draft Release titled `银杏 Root 增强 Preview 11` with `--verify-tag`, the committed notes, and all three assets. Query release state/assets, then download all assets into a fresh `mktemp -d` directory and run:

```bash
sha256sum -c SHA256SUMS.txt
unzip -t yinxing-guard-1.10.0-root-preview.11.zip
/nfs/home/leguochun/android-sdk/build-tools/36.0.0/aapt2 dump badging yinxing-1.10.0-root-preview.11-debug.apk
/nfs/home/leguochun/android-sdk/build-tools/36.0.0/apksigner verify --verbose yinxing-1.10.0-root-preview.11-debug.apk
```

Expected: downloaded digests match local assets and committed notes; APK code/name and v2 signature pass; module ZIP passes integrity.

- [ ] **Step 10: Update persistent goal records.**

Append Preview 11 design finding, source commit, tag, Release URL, exact timings, test totals, hashes, remote evidence, and remaining OnePlus 15 validation requirement to the active `.planning` task, progress, and findings files. Keep the device-feedback phase and persistent Goal active.
