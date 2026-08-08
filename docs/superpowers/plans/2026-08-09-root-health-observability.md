# Root Health Observability Preview 2 Implementation Plan

> For agentic workers: execute this plan task-by-task in the current checkout. Keep the Root allowlist fixed and run each task's tests before moving on.

Goal: Add a bounded KernelSU health snapshot and fixed one-shot repair action, expose them through a fail-closed APK bridge and caregiver settings sheet, and publish a locally verified Preview 2 release.

Architecture: The KernelSU module emits an enumerated key/value snapshot from live device state and atomically records the last repair result. The APK uses a RootCommandRunner with only STATUS and RECOVER commands, parses the snapshot with a pure strict parser, and invokes it only from an explicit settings flow. Existing accessibility and unrooted behavior remain unchanged.

Tech stack: POSIX shell plus standalone BusyBox ash; Kotlin/JVM unit tests; Android Views/Material bottom sheets; Kotlin coroutines; Gradle 9.3.1 with full JDK 21; GitHub CLI.

## Global Constraints

- Target device: OnePlus 15, China ColorOS 16, KernelSU, already Rooted.
- APK minimum SDK remains 24; compile/target SDK remains 36.
- Root commands are fixed literals and never accept user input.
- Root process output is capped at 16 KiB and each invocation is limited to 3 seconds.
- Invalid, duplicate, missing, or unknown status fields fail closed.
- The existing AccessibilityService remains the semantic automation backend.
- .planning/ stays untracked and is not included in product commits or release assets.
- Every production behavior change has a test that was observed failing before implementation.

---

### Task 1: Define and test the module health snapshot

Files:
- Modify: tools/test-yinxing-guard.sh
- Create: root/kernelsu/yinxing_guard/bin/status.sh
- Modify: root/kernelsu/yinxing_guard/bin/common.sh
- Modify: root/kernelsu/yinxing_guard/bin/guard.sh
- Modify: root/kernelsu/yinxing_guard/action.sh
- Modify: root/kernelsu/yinxing_guard/service.sh
- Modify: tools/package-yinxing-guard.sh

Interfaces:
- status.sh prints exactly schema, version, module, guard, accessibility, doze, cleanup, and last_repair.
- common.sh provides record_repair_result(result), accepting only ok or failed and atomically replacing $STATE_DIR/last_repair.
- status.sh returns exit 0 for a readable snapshot, including degraded states; it returns non-zero only when it cannot produce the contract.

- [ ] Step 1: Add red tests for status behavior.

Extend tools/test-yinxing-guard.sh with controlled fixtures and an assert_contains_text helper. The healthy case must create an active module directory, current-boot PID lock, ok marker, module-owned Doze marker, executable cleanup helper, enabled accessibility component, and then assert module=active, guard=running, accessibility=enabled, doze=owned, cleanup=ready, and last_repair=ok. A second case must use a dead PID and assert guard=stale and a non-healthy result. Register both tests in the harness list.

- [ ] Step 2: Run the red module tests.

Run: bash tools/test-yinxing-guard.sh host

Expected: FAIL while trying to execute the missing root/kernelsu/yinxing_guard/bin/status.sh. Do not weaken the assertions.

- [ ] Step 3: Implement the smallest status contract.

Add record_repair_result to common.sh with an allowlist and temp-file-plus-mv replacement. Call it from guard.sh after repair_state and from action.sh for both repair success and failure. Add status.sh using the existing fixed constants and the same boot-id sanitization as guard.sh. It must never print command output. Extend the packager's required-file list, explicit ZIP order, and chmod list with bin/status.sh.

- [ ] Step 4: Run module tests green on host and BusyBox.

Run:
    bash tools/test-yinxing-guard.sh host
    YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh busybox

Expected: both exit 0, including all existing regression cases and the new status cases.

- [ ] Step 5: Commit the module slice.

    git add root/kernelsu/yinxing_guard tools/test-yinxing-guard.sh tools/package-yinxing-guard.sh
    git commit -m "feat: expose root guard health snapshot"

### Task 2: Build the strict APK Root bridge and parser

Files:
- Create: app/src/main/java/com/yinxing/launcher/common/root/RootHealthSnapshot.kt
- Create: app/src/main/java/com/yinxing/launcher/common/root/RootCommandRunner.kt
- Create: app/src/main/java/com/yinxing/launcher/common/root/RootHealthRepository.kt
- Create: app/src/test/java/com/yinxing/launcher/common/root/RootHealthSnapshotTest.kt
- Create: app/src/test/java/com/yinxing/launcher/common/root/RootHealthRepositoryTest.kt

Interfaces:

    internal enum class RootCommand { STATUS, RECOVER }

    internal data class RootCommandResult(
        val exitCode: Int,
        val output: String,
        val timedOut: Boolean = false
    )

    internal fun interface RootCommandRunner {
        fun run(command: RootCommand): RootCommandResult
    }

    internal enum class RootHealthState {
        UNCHECKED, ROOT_UNAVAILABLE, MODULE_MISSING, DEGRADED, HEALTHY
    }

    internal data class RootHealthSnapshot(
        val state: RootHealthState,
        val version: String? = null,
        val module: String = "unknown",
        val guard: String = "unknown",
        val accessibility: String = "unknown",
        val doze: String = "unknown",
        val cleanup: String = "unknown",
        val lastRepair: String = "unknown"
    ) {
        companion object {
            fun unchecked(): RootHealthSnapshot
            fun unavailable(): RootHealthSnapshot
            fun parse(output: String): RootHealthSnapshot?
        }
    }

    internal data class RootRecoveryResult(
        val actionSucceeded: Boolean,
        val snapshot: RootHealthSnapshot
    )

    internal class RootHealthRepository(private val runner: RootCommandRunner) {
        suspend fun query(): RootHealthSnapshot
        suspend fun recoverAndQuery(): RootRecoveryResult
    }

- [ ] Step 1: Write parser and repository red tests.

RootHealthSnapshotTest covers a hand-written valid healthy fixture, a degraded fixture, duplicate keys, unknown values, missing keys, over-16KiB output, and contradictory healthy fields. RootHealthRepositoryTest uses a fake runner returning real RootCommandResult values and covers non-zero exit, timeout, successful query, failed recovery followed by query, and successful recovery followed by query.

- [ ] Step 2: Run the focused red tests.

Run: env ANDROID_HOME=/nfs/home/leguochun/android-sdk GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home JAVA_TOOL_OPTIONS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888' bash gradlew :app:testDebugUnitTest --tests 'com.yinxing.launcher.common.root.*' --no-daemon --console=plain

Expected: compilation/test failure because the new production types do not exist.

- [ ] Step 3: Implement strict parsing and state derivation.

Parse at most 16,384 characters, require exactly the eight schema keys, reject duplicate/unknown keys and values outside the enumerated sets, and derive HEALTHY only when all required live checks plus last_repair=ok pass. Treat module=missing as MODULE_MISSING; all bridge failures map to ROOT_UNAVAILABLE.

- [ ] Step 4: Implement the fixed su runner.

SuRootCommandRunner maps STATUS to /data/adb/modules/yinxing_guard/bin/status.sh and RECOVER to /data/adb/modules/yinxing_guard/action.sh. Use ProcessBuilder("su", "-c", fixedPath), redirect stderr into stdout, consume output on a bounded reader thread, poll for at most 3 seconds, destroy timed-out processes, and return only the structured result.

- [ ] Step 5: Run focused then full Android tests green.

Run the focused command again, then the full :app:testDebugUnitTest command with the same environment. Expected: zero failures and zero errors.

- [ ] Step 6: Commit the bridge slice.

    git add app/src/main/java/com/yinxing/launcher/common/root app/src/test/java/com/yinxing/launcher/common/root
    git commit -m "feat: add bounded root health bridge"

### Task 3: Add the caregiver Root status sheet

Files:
- Modify: app/src/main/res/layout/activity_settings.xml
- Modify: app/src/main/res/values/strings.xml
- Modify: app/src/main/java/com/yinxing/launcher/feature/settings/SettingsActivity.kt
- Modify: app/src/main/java/com/yinxing/launcher/feature/settings/SettingsViewBinding.kt
- Modify: app/src/main/java/com/yinxing/launcher/feature/settings/SettingsRuntimeState.kt
- Modify: app/src/main/java/com/yinxing/launcher/feature/settings/SettingsOverviewController.kt
- Modify: app/src/main/java/com/yinxing/launcher/feature/settings/SettingsSheetController.kt
- Create: app/src/main/java/com/yinxing/launcher/feature/settings/SettingsRootHealthSheet.kt
- Modify: app/src/test/java/com/yinxing/launcher/feature/settings/SettingsActivitySmokeTest.kt

Interfaces:
- Add btn_card_root, tv_root_hub_status, and tv_root_hub_summary to the settings layout.
- SettingsRuntimeState.rootHealthSnapshot defaults to RootHealthSnapshot.unchecked().
- SettingsOverviewController.bindActions accepts onShowRootHealthSheet: () -> Unit and binds the new card.
- SettingsRootHealthSheet.kt exposes SettingsActivity.showRootHealthSheet() and SettingsActivity.updateRootHubCard().

- [ ] Step 1: Add a failing smoke assertion.

Add a test that builds SettingsActivity without Root and asserts btn_card_root exists and tv_root_hub_summary is non-empty. Run the focused test before adding the layout; it must fail because the IDs are absent.

- [ ] Step 2: Add the card, strings, binding, and runtime state.

Place the card between the permissions and device cards, reuse the existing device icon/color treatment, and render the default 未检查 state without invoking su. Add Chinese strings for unchecked, unavailable, missing, degraded, healthy, sheet details, action labels, and recovery result.

- [ ] Step 3: Implement the sheet and explicit asynchronous actions.

Opening the card creates the existing list bottom sheet, immediately renders the cached state, then runs one status query on Dispatchers.IO. The recovery entry invokes recoverAndQuery only after an explicit tap, disables itself while running, and refreshes the overview card. Errors become a Toast plus an unavailable/degraded summary; no exception escapes the Activity.

- [ ] Step 4: Run focused settings tests and the full suite.

Run the smoke test, then :app:testDebugUnitTest. Expect zero failures/errors and no Root prompt during Activity creation.

- [ ] Step 5: Commit the UI slice.

    git add app/src/main/res/layout/activity_settings.xml app/src/main/res/values/strings.xml app/src/main/java/com/yinxing/launcher/feature/settings app/src/test/java/com/yinxing/launcher/feature/settings/SettingsActivitySmokeTest.kt
    git commit -m "feat: add caregiver root health sheet"

### Task 4: Version, document, package, and verify Preview 2

Files:
- Modify: app/build.gradle.kts (versionCode 18, versionName 1.10.0-root-preview.2)
- Modify: root/kernelsu/yinxing_guard/bin/common.sh module version constant
- Modify: root/kernelsu/yinxing_guard/bin/uninstall-cleanup.sh module version constant
- Modify: root/kernelsu/yinxing_guard/module.prop version
- Create: docs/release/yinxing-root-preview-2.md

- [ ] Step 1: Add acceptance and rollback notes.

Document clean-install/debug-signing limitations, KernelSU module installation, explicit first-time Root grant, expected settings-card states, recovery action, reboot/kill/accessibility acceptance checks, module disable rollback, and exact local verification commands.

- [ ] Step 2: Update version metadata and run source checks.

Run git diff --check, sh -n, bash -n, and standalone BusyBox ash -n over all module scripts before packaging.

- [ ] Step 3: Run full forced verification.

    env ANDROID_HOME=/nfs/home/leguochun/android-sdk GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home JAVA_TOOL_OPTIONS='-Dhttp.proxyHost=172.38.8.47 -Dhttp.proxyPort=8888 -Dhttps.proxyHost=172.38.8.47 -Dhttps.proxyPort=8888' bash gradlew :app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon --console=plain
    bash tools/test-yinxing-guard.sh host
    YINXING_TEST_SHELL=busybox bash tools/test-yinxing-guard.sh busybox

Record direct exit codes, Gradle duration, test counts, and module suite output in the planning log.

- [ ] Step 4: Package and verify artifacts.

    mkdir -p /tmp/yinxing-preview-2
    bash tools/package-yinxing-guard.sh /tmp/yinxing-preview-2/yinxing-guard-1.10.0-root-preview.2.zip 1.10.0-root-preview.2
    cp app/build/outputs/apk/debug/app-debug.apk /tmp/yinxing-preview-2/yinxing-1.10.0-root-preview.2-debug.apk
    sha256sum /tmp/yinxing-preview-2/yinxing-1.10.0-root-preview.2-debug.apk /tmp/yinxing-preview-2/yinxing-guard-1.10.0-root-preview.2.zip > /tmp/yinxing-preview-2/SHA256SUMS.txt
    unzip -t /tmp/yinxing-preview-2/yinxing-guard-1.10.0-root-preview.2.zip
    sha256sum -c /tmp/yinxing-preview-2/SHA256SUMS.txt

Confirm package/version, ZIP root layout, executable modes, deterministic timestamps, and presence of bin/status.sh.

- [ ] Step 5: Request review, push, tag, and publish.

Review the complete range from commit 936c9d7 through the Preview 2 implementation, fix all Critical/Important findings, then push main and create annotated tag v1.10.0-root-preview.2. Publish a prerelease titled 银杏 Root 健康预览 2 with the APK, module ZIP, and checksum file.

- [ ] Step 6: Verify the remote release and leave the goal active.

Download all release assets into a fresh temporary directory, verify checksums and ZIP integrity, confirm the tag peels to the pushed commit, and update Phase 10 to complete while keeping Phase 9 active for real-device feedback.
