# Preview 27 Root Path Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the module-script executable-bit dependency from Yinxing's three fixed Root actions and show the exact bounded failing stage, UID, command, exit code, and system output in the caregiver Root sheet.

**Architecture:** Keep KernelSU's only supported compatibility entry `/system/bin/su` and the existing three-value `RootCommand` allowlist. Make each value derive one immutable `/system/bin/sh <fixed-script>` command, then carry a bounded `RootFailureEvidence` value from `SuRootCommandRunner` through `RootHealthRepository` into the existing caregiver sheet. Keep the Preview 26 module byte-for-byte unchanged and add no probe, bridge, daemon, polling, or background work.

**Tech Stack:** Kotlin/JVM, Android Views, coroutines, Robolectric/JUnit 4, Java `ProcessBuilder`, Gradle 9.3.1, Android SDK 36, GitHub CLI.

## Global Constraints

- Target only the managed OnePlus 15 / China ColorOS 16 / KernelSU device.
- Keep `/system/bin/su` as the sole Root entry and do not bypass KernelSU's explicit app-UID authorization.
- Keep exactly `STATUS`, `RECOVER`, and `KIOSK_HOME`; accept no external path, argument, package, component, coordinate, or shell text.
- Invoke each fixed script as `/system/bin/sh <absolute-script-path>` through `su -c`; do not require the script itself to be executable.
- Retain timeouts of 3,000 ms, 20,000 ms, and 15,000 ms and the 16 KiB process-output cap.
- Diagnostic detail keeps newlines/tabs, replaces other controls, preserves useful beginning/end text, and never exceeds 1,024 characters.
- Keep reason badges distinct; evidence supplements classification and never combines `su` start failure with a later script/command failure.
- Show technical evidence only in the explicit caregiver Root sheet. Do not add it to elderly HOME, phone, video, or call surfaces.
- Do not modify `root/`, BusyBox behavior, the manifest, services, receivers, boot logic, Accessibility policy, HOME policy, contacts, calls, WeChat automation, network behavior, wakelocks, or idle work.
- Set APK metadata exactly to `versionCode=43`, `versionName="1.10.0-root-preview.27"`; reuse and link the exact Preview 26 module asset rather than rebuilding or renaming it.
- Every behavior change requires a focused test observed RED before production implementation.
- Never claim device Root recovery before direct OnePlus 15 evidence.

---

### Task 1: Interpret fixed scripts with the Android system shell and capture runner evidence

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/common/root/RootCommandRunner.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/common/root/RootCommandRunnerTest.kt`
- Create: `app/src/test/java/com/yinxing/launcher/common/root/RootFailureEvidenceTest.kt`

**Interfaces:**
- Produces `internal const val ANDROID_SYSTEM_SHELL = "/system/bin/sh"`.
- `RootCommand` retains `shellPath` and adds `val shellCommand: String` equal to `"$ANDROID_SYSTEM_SHELL $shellPath"` and `val invocation: String` equal to `"$KERNEL_SU_EXECUTABLE -c \"$shellCommand\""`.
- Produces `internal enum class RootFailureStage { SU_START, COMMAND_RUN, STATUS_PARSE, RUNNER_EXCEPTION }`.
- Produces `internal data class RootFailureEvidence(val command: RootCommand, val stage: RootFailureStage, val invocation: String, val exitCode: Int?, val detail: String)` with `companion object fun create(command, stage, exitCode = null, detail = ""): RootFailureEvidence`.
- `RootCommandResult` adds `val evidence: RootFailureEvidence? = null` without changing existing callers' default construction.
- `SuRootCommandRunner` starts exactly `ProcessBuilder(KERNEL_SU_EXECUTABLE, "-c", command.shellCommand)` and returns evidence on every unsuccessful result.

- [ ] **Step 1: Establish the released focused baseline**

Run from the isolated worktree:

```bash
/usr/bin/time -p env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.common.root.*' \
  --tests com.yinxing.launcher.feature.settings.SettingsActivitySmokeTest \
  --rerun-tasks --no-daemon --console=plain
```

Expected: exit 0 with all current Root/settings tests passing. Record elapsed time and parsed test count in `.planning/.../progress.md`.

- [ ] **Step 2: Write RED tests for shell-read invocation and exact runner evidence**

In `RootCommandRunnerTest`, replace the old direct-path allowlist expectation with these assertions:

```kotlin
@Test
fun usesSystemShellToReadOnlyTheThreeFixedScripts() {
    val record = Files.createTempFile("yinxing-root-commands", ".txt")
    withFakeSu("printf '%s\\n' \"${'$'}2\" >> '$record'; exit 0") { executable ->
        val runner = SuRootCommandRunner(timeoutMillis = 1_000, suExecutable = executable.toString())
        RootCommand.values().forEach(runner::run)
    }

    assertEquals(
        listOf(
            "/system/bin/sh /data/adb/modules/yinxing_guard/bin/status.sh",
            "/system/bin/sh /data/adb/modules/yinxing_guard/action.sh",
            "/system/bin/sh /data/adb/modules/yinxing_guard/bin/kiosk-home.sh"
        ),
        Files.readAllLines(record)
    )
    Files.deleteIfExists(record)
}
```

The fake `su` must append its second argument to a test-owned file and exit 0. Add a host semantic regression that copies a tiny script to a temporary `0644` file and proves `/bin/sh <file>` succeeds even though direct `/bin/sh -c <file>` exits nonzero. This test documents why the production command removes exit 126 without accepting arbitrary production paths.

Add start and exit evidence assertions:

```kotlin
assertEquals(RootFailureStage.SU_START, missing.evidence?.stage)
assertEquals(RootCommand.STATUS, missing.evidence?.command)
assertTrue(missing.evidence?.invocation.orEmpty().contains("/system/bin/su -c"))
assertTrue(missing.evidence?.detail.orEmpty().contains("IOException"))

assertEquals(RootFailureStage.COMMAND_RUN, denied.evidence?.stage)
assertEquals(126, denied.evidence?.exitCode)
assertTrue(denied.evidence?.detail.orEmpty().contains("Permission denied"))
```

Create `RootFailureEvidenceTest` with a detail containing leading/trailing whitespace, newline, tab, NUL, and more than 1,024 characters. Assert controls are replaced, newline/tab remain, the output contains an explicit ASCII omitted-character marker, useful prefix/suffix remain, and `detail.length <= 1024`.

- [ ] **Step 3: Run the focused tests and verify RED**

```bash
env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest \
  --tests com.yinxing.launcher.common.root.RootCommandRunnerTest \
  --tests com.yinxing.launcher.common.root.RootFailureEvidenceTest \
  --no-daemon --console=plain
```

Expected: compilation failures for `ANDROID_SYSTEM_SHELL`, `RootFailureEvidence`, `RootFailureStage`, `shellCommand`, `invocation`, and `evidence`, plus the old fake-su path contract mismatch. The host semantic assertion itself should prove direct execution fails and shell reading succeeds.

- [ ] **Step 4: Implement the minimal fixed invocation and evidence normalization**

Add these fixed properties near `RootCommand`:

```kotlin
internal const val KERNEL_SU_EXECUTABLE = "/system/bin/su"
internal const val ANDROID_SYSTEM_SHELL = "/system/bin/sh"

internal val RootCommand.shellCommand: String
    get() = "$ANDROID_SYSTEM_SHELL $shellPath"

internal val RootCommand.invocation: String
    get() = "$KERNEL_SU_EXECUTABLE -c \"$shellCommand\""
```

Implement evidence creation with a 1,024-character final cap. Use fixed prefix/suffix budgets and compute the omitted count before composing the marker; after composition, assert or defensively `take(MAX_DETAIL_CHARS)` so the public contract cannot overflow. Build start evidence with:

```kotlin
private fun Throwable.diagnosticText(): String = buildString {
    append(this@diagnosticText::class.java.simpleName)
    message?.takeIf(String::isNotBlank)?.let { append(": ").append(it) }
}
```

Change only the process start line:

```kotlin
ProcessBuilder(suExecutable, "-c", command.shellCommand)
```

On `IOException` or `SecurityException`, return the existing reason override plus `SU_START` evidence. On a normal unsuccessful result, attach `COMMAND_RUN` evidence with the actual exit code when non-negative and the bounded combined output. Timeout and overflow evidence use the same stage and keep their existing reason precedence.

Update `hasDirectRootCommandError` so it prefers `result.evidence?.command` and classifies a line as top-level only when it contains that command's fixed `shellPath` plus the relevant permission/missing phrase. Preserve the existing three-enum fallback only for manually constructed test/repository results that have no runner evidence. Include `can't open`, `cannot open`, and `can't execute` Android-shell variants. Do not classify a line that only names an internal dependency.

- [ ] **Step 5: Run focused and all Root tests GREEN**

```bash
env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.common.root.*' \
  --rerun-tasks --no-daemon --console=plain
```

Expected: all Root tests pass; timeout/output bounds remain green.

- [ ] **Step 6: Commit Task 1**

```bash
git add app/src/main/java/com/yinxing/launcher/common/root/RootCommandRunner.kt \
  app/src/test/java/com/yinxing/launcher/common/root/RootCommandRunnerTest.kt \
  app/src/test/java/com/yinxing/launcher/common/root/RootFailureEvidenceTest.kt
git commit -m "fix: read root scripts through system shell"
```

---

### Task 2: Preserve status, parsing, recovery, and runner-exception evidence

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/common/root/RootHealthSnapshot.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/common/root/RootHealthRepository.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/common/root/RootHealthSnapshotTest.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/common/root/RootHealthRepositoryTest.kt`

**Interfaces:**
- `RootHealthSnapshot` adds `val failureEvidence: RootFailureEvidence? = null` after `failureExitCode`.
- `RootHealthSnapshot.unavailable(reason, exitCode, evidence)` accepts optional evidence and preserves source compatibility through defaults.
- `RootRecoveryResult` adds `val actionFailureEvidence: RootFailureEvidence? = null`.
- `RootHealthRepository` preserves runner evidence; creates `STATUS_PARSE` evidence for successful malformed status; and maps thrown non-cancellation `Exception` to `RUNNER_EXCEPTION` evidence for the attempted command.

- [ ] **Step 1: Write RED repository/model evidence tests**

Add a fake status result containing explicit evidence and assert identity/value preservation:

```kotlin
assertEquals(evidence, repository.query().failureEvidence)
```

For malformed successful status, assert:

```kotlin
assertEquals(RootFailureStage.STATUS_PARSE, snapshot.failureEvidence?.stage)
assertEquals(RootCommand.STATUS, snapshot.failureEvidence?.command)
assertTrue(snapshot.failureEvidence?.detail.orEmpty().contains("schema=3"))
```

For recovery failure followed by healthy status:

```kotlin
assertEquals(RootHealthState.HEALTHY, result.snapshot.state)
assertEquals(actionEvidence, result.actionFailureEvidence)
assertEquals(listOf(RootCommand.RECOVER, RootCommand.STATUS), runner.commands)
```

Add a `ThrowingRunner(IllegalStateException("runner exploded"))` and assert the unavailable snapshot has reason `UNKNOWN`, stage `RUNNER_EXCEPTION`, command `STATUS`, the fixed invocation, no exit code, and detail containing both `IllegalStateException` and `runner exploded`. Retain the cancellation rethrow test or add it if absent.

- [ ] **Step 2: Run repository/model tests and verify RED**

```bash
env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest \
  --tests com.yinxing.launcher.common.root.RootHealthSnapshotTest \
  --tests com.yinxing.launcher.common.root.RootHealthRepositoryTest \
  --no-daemon --console=plain
```

Expected: compilation failures for `failureEvidence` and `actionFailureEvidence`, then assertion failures until parse/exception evidence is synthesized.

- [ ] **Step 3: Implement evidence propagation**

Extend `RootHealthSnapshot.unavailable`:

```kotlin
fun unavailable(
    reason: RootFailureReason = RootFailureReason.UNKNOWN,
    exitCode: Int? = null,
    evidence: RootFailureEvidence? = null
): RootHealthSnapshot = RootHealthSnapshot(
    state = RootHealthState.ROOT_UNAVAILABLE,
    failureReason = reason,
    failureExitCode = exitCode,
    failureEvidence = evidence
)
```

Change `readSnapshot()` so a nonzero result passes `result.evidence`; if parsing fails, create `STATUS_PARSE` evidence from `result.output`. Change `runCommand(command)` so its exception mapping includes `RUNNER_EXCEPTION` evidence using the same normalized factory. Rethrow `CancellationException` unchanged.

Set `actionFailureEvidence` only when recovery is unsuccessful. Do not replace the subsequent fresh status snapshot with action evidence.

- [ ] **Step 4: Run focused repository and full Root tests GREEN**

```bash
env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.common.root.*' \
  --rerun-tasks --no-daemon --console=plain
```

Expected: all Root runner/parser/repository/HOME tests pass with no skipped tests.

- [ ] **Step 5: Commit Task 2**

```bash
git add app/src/main/java/com/yinxing/launcher/common/root/RootHealthSnapshot.kt \
  app/src/main/java/com/yinxing/launcher/common/root/RootHealthRepository.kt \
  app/src/test/java/com/yinxing/launcher/common/root/RootHealthSnapshotTest.kt \
  app/src/test/java/com/yinxing/launcher/common/root/RootHealthRepositoryTest.kt
git commit -m "feat: preserve exact root failure evidence"
```

---

### Task 3: Render exact status and recovery evidence in the caregiver Root sheet

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/feature/settings/SettingsRootHealthSheet.kt`
- Modify: `app/src/main/res/values/strings.xml`
- Modify: `app/src/test/java/com/yinxing/launcher/feature/settings/SettingsActivitySmokeTest.kt`

**Interfaces:**
- Produces `internal fun SettingsActivity.rootFailureEvidenceSummary(evidence: RootFailureEvidence): String`.
- `rootHealthStatusSummary(snapshot)` appends evidence after the existing reason-specific explanation only when `snapshot.failureEvidence != null`.
- `showRootHealthSheet()` retains `var recoveryFailureEvidence: RootFailureEvidence?` for that sheet session and passes it into rendering.
- `renderRootHealthEntries(..., recoveryFailureEvidence)` shows action evidence in the recovery summary after a failed action; busy text and default action text keep precedence otherwise.

- [ ] **Step 1: Add RED UI summary tests**

Add status evidence fixtures for:

```kotlin
RootFailureEvidence.create(
    command = RootCommand.STATUS,
    stage = RootFailureStage.SU_START,
    detail = "IOException: Cannot run program /system/bin/su: error=2, No such file or directory"
)
```

Assert the rendered summary contains all of:

```text
当前 UID <Robolectric process UID>
启动 su
/system/bin/su -c "/system/bin/sh /data/adb/modules/yinxing_guard/bin/status.sh"
未启动
IOException
error=2
```

Add exit-126 evidence and assert `执行状态脚本`, `退出码 126`, the selected `status.sh`, and the original permission line all remain. Add empty detail and assert `系统原文：无输出`.

Extend the sheet/repository fake so `recoverAndQuery()` returns healthy status plus failed `actionFailureEvidence`; click the recovery entry, idle coroutines, and assert the status entry is healthy while the recovery entry persistently contains `action.sh`, its exit code, and original output.

- [ ] **Step 2: Run the settings test and verify RED**

```bash
env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest \
  --tests com.yinxing.launcher.feature.settings.SettingsActivitySmokeTest \
  --no-daemon --console=plain
```

Expected: compilation failures for evidence formatting and assertion failures because the released summary still discards evidence.

- [ ] **Step 3: Add exact Chinese diagnostic labels and formatter**

Add strings adjacent to existing Root failure strings:

```xml
<string name="settings_root_diagnostic_stage_su_start">启动 su</string>
<string name="settings_root_diagnostic_stage_command_status">执行状态脚本</string>
<string name="settings_root_diagnostic_stage_command_recover">执行修复脚本</string>
<string name="settings_root_diagnostic_stage_command_home">执行桌面恢复脚本</string>
<string name="settings_root_diagnostic_stage_status_parse">解析状态</string>
<string name="settings_root_diagnostic_stage_runner_exception">执行器异常</string>
<string name="settings_root_diagnostic_not_started">未启动</string>
<string name="settings_root_diagnostic_no_output">无输出</string>
<string name="settings_root_diagnostic_format">诊断阶段：%1$s\n应用 UID：%2$d\n固定命令：%3$s\n退出码：%4$s\n系统原文：%5$s</string>
```

Map `COMMAND_RUN` by `evidence.command`, not a generic label. Use `android.os.Process.myUid()` at formatting time, evidence invocation verbatim, `exitCode?.toString()` or `未启动`, and detail or `无输出`.

Append `"\n\n" + rootFailureEvidenceSummary(evidence)` to the existing human explanation. Do not replace any current reason string or badge.

- [ ] **Step 4: Retain recovery evidence in the current sheet session**

Initialize `var recoveryFailureEvidence: RootFailureEvidence? = null` in `showRootHealthSheet`. Clear it immediately when a new recovery begins. After `recoverAndQuery`, assign `result.actionFailureEvidence`, then render. Extend `renderRootHealthEntries` with a nullable evidence parameter defaulting to null so query-only callers stay simple.

Set recovery summary priority:

```kotlin
recoverySummary.text = when {
    busy -> getString(R.string.settings_root_recover_running)
    recoveryFailureEvidence != null -> rootFailureEvidenceSummary(recoveryFailureEvidence)
    else -> getString(R.string.settings_root_entry_recover_summary)
}
```

Keep both rows disabled only while busy and keep the healthy status entry truthful.

- [ ] **Step 5: Run settings plus complete Root slice GREEN**

```bash
/usr/bin/time -p env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.common.root.*' \
  --tests com.yinxing.launcher.feature.settings.SettingsActivitySmokeTest \
  --rerun-tasks --no-daemon --console=plain
```

Expected: all focused tests pass; Root still starts unchecked and no normal overview refresh invokes `su`.

- [ ] **Step 6: Commit Task 3**

```bash
git add app/src/main/java/com/yinxing/launcher/feature/settings/SettingsRootHealthSheet.kt \
  app/src/main/res/values/strings.xml \
  app/src/test/java/com/yinxing/launcher/feature/settings/SettingsActivitySmokeTest.kt
git commit -m "feat: show exact root failure evidence"
```

---

### Task 4: Version, independently review, verify, and publish Preview 27

**Files:**
- Modify: `app/build.gradle.kts`
- Create: `docs/release/yinxing-root-preview-27.md`
- Generate ignored: `out/release/yinxing-1.10.0-root-preview.27-debug.apk`
- Generate ignored: `out/release/SHA256SUMS.txt`

**Interfaces:**
- Produces Debug APK package `com.yinxing.launcher`, versionCode 43, versionName `1.10.0-root-preview.27`, min/target SDK 24/36.
- Publishes annotated tag and non-draft prerelease `v1.10.0-root-preview.27` with exactly the APK and checksum assets.
- Release body links Preview 26's unchanged module asset and states that a device already on the Preview 26 module only needs the new APK.

- [ ] **Step 1: Set APK metadata and write exact release notes**

Change only:

```kotlin
versionCode = 43
versionName = "1.10.0-root-preview.27"
```

Release notes must include:

- the two device-observed failures remain separate;
- all three APK actions now use fixed `/system/bin/sh <fixed-script>` through `/system/bin/su`;
- exact failure stage/UID/command/exit/original output appears in the caregiver sheet;
- KernelSU authorization cannot be bypassed, and `su` invisibility still names the current UID;
- no BusyBox, module, daemon, boot, Accessibility policy, HOME policy, background, or power change;
- Preview 26 module is unchanged and linked with its published SHA-256 `96f243ed79bf7216a1576fdd64ba1943dd5125e07d83750ed19bca56c53b7cf9`;
- Debug-signing clean-install caveat, Preview 26 rollback, and no attached-device claim;
- acceptance steps: install APK, open 家属设置 → Root 专机, capture every diagnostic line, tap immediate recovery once, then check status/recovery rows.

- [ ] **Step 2: Commit metadata and notes**

```bash
git add app/build.gradle.kts docs/release/yinxing-root-preview-27.md
git commit -m "chore: prepare root preview 27 release"
```

- [ ] **Step 3: Run independent code review and resolve findings with RED tests**

Invoke `requesting-code-review` against the complete diff from `v1.10.0-root-preview.26`. Require review of:

- command allowlist and quoting;
- exact script-read semantics;
- evidence bounds/control normalization;
- exception/cancellation/process lifecycle;
- classification overreach;
- status versus recovery evidence ownership;
- caregiver readability and no background/elderly UI/module scope leak.

For every Critical or Important finding, add a focused failing regression, observe RED, fix minimally, rerun the focused slice, and commit. Record Minor findings and either fix them or explicitly justify deferral.

- [ ] **Step 4: Run final Root Guard, Android, lint, and source-boundary verification**

```bash
bash tools/test-yinxing-guard.sh

/usr/bin/time -f 'ELAPSED_SECONDS=%e EXIT_STATUS=%x' \
  env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest \
  --rerun-tasks --no-daemon --console=plain

env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:lintDebug --no-daemon --console=plain

git diff --check v1.10.0-root-preview.26..HEAD
git diff --name-only v1.10.0-root-preview.26..HEAD
git diff --exit-code v1.10.0-root-preview.26..HEAD -- root app/src/main/AndroidManifest.xml
```

Expected:

- host plus recursive standalone BusyBox module suite exits 0;
- every Android task executes and build exits 0;
- JUnit XML totals have zero failures, errors, and skips;
- lint has no new issue beyond the two inherited API-24/26 `Process.waitFor(timeout, TimeUnit)` findings, unless Task 1's touched lines legitimately remove them;
- `git diff --check` exits 0;
- the final Root/manifest boundary diff exits 0, proving the module and manifest are unchanged.

- [ ] **Step 5: Build and verify exact local release assets**

```bash
mkdir -p out/release
cp app/build/outputs/apk/debug/app-debug.apk \
  out/release/yinxing-1.10.0-root-preview.27-debug.apk
(
  cd out/release
  sha256sum yinxing-1.10.0-root-preview.27-debug.apk > SHA256SUMS.txt
  sha256sum -c SHA256SUMS.txt
)
```

Use `$ANDROID_HOME/build-tools/36.0.0/aapt2 dump badging` and `apksigner verify --verbose --print-certs` to assert exact package/version/min/target metadata, one Debug signer, and v2 signing. Record APK bytes and SHA-256. Run `$ANDROID_HOME/platform-tools/adb devices -l`; if no OnePlus 15 is attached, retain the no-device claim.

- [ ] **Step 6: Merge, push, tag, and publish only verified source**

Fast-forward the feature branch into `main`, rerun the focused Root/settings tests on merged `main`, push `main` and the feature branch, then create and push the annotated tag:

```bash
git tag -a v1.10.0-root-preview.27 -m "Yinxing Root Preview 27"
git push origin main feat/root-path-device-incident-preview-27
git push origin v1.10.0-root-preview.27
gh release create v1.10.0-root-preview.27 \
  out/release/yinxing-1.10.0-root-preview.27-debug.apk \
  out/release/SHA256SUMS.txt \
  --verify-tag --prerelease --title "Yinxing Root Preview 27" \
  --notes-file docs/release/yinxing-root-preview-27.md
```

Do not publish a rebuilt module. Link the exact Preview 26 module URL in the release body.

- [ ] **Step 7: Fresh-download verify the GitHub release**

Create a fresh `mktemp -d` directory, download every release asset with `gh release download`, and verify:

- release is non-draft prerelease with exactly two assets;
- `sha256sum -c SHA256SUMS.txt` passes;
- remote files are byte-identical to local verified assets;
- remote APK metadata/signature still match;
- remote `main`, feature branch, and peeled annotated tag resolve to the same commit;
- release body includes exact diagnostics, unchanged module link/hash, rollback, Debug caveat, and no-device boundary.

Update `.planning` with final timings, test totals, hashes, commit/tag/release URL, remote verification, and the still-open OnePlus 15 acceptance phase. Mark the implementation tasks complete but keep the broad Goal active until real device Root behavior is confirmed and the larger elderly reliability objective is satisfied.
