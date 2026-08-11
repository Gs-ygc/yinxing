# Preview 25 Incoming Call Failure Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace transient incoming-call action failure Toasts with a persistent, elderly-readable recovery flow that can retry or request the system call UI without adding success-path latency or background work.

**Architecture:** Put platform calls behind a fail-closed `IncomingCallSystemUiGateway`, and keep the one-resume handoff lifecycle in a small `IncomingCallRecoveryCoordinator`. A dedicated dialog maps the existing structured failure reason to two large actions. `IncomingCallActivity` wires these boundaries to existing action/diagnostic state, while diagnostics distinguish request, request failure, and recovered success.

**Tech Stack:** Kotlin, Android Telecom/Telephony APIs, AppCompat `AlertDialog`, Material Components, XML resources, JUnit 4, Robolectric, Gradle 9.3.1, Android Gradle Plugin.

## Global Constraints

- Target exact managed baseline: OnePlus 15, China ColorOS 16, KernelSU, rooted; local tests must not claim physical-device success.
- Keep `minSdk=24`, `targetSdk=36`, package `com.yinxing.launcher`, and the existing Android Debug signer.
- Do not add Root commands, BusyBox work, accessibility clicks, coordinate input, OEM-private APIs, receivers, listeners, services, timers, polling, wake locks, or network work.
- Do not change `root/`, `app/src/main/AndroidManifest.xml`, service/background scheduling, HOME ownership, contact loading, or the successful answer/reject path.
- `TelecomManager.showInCallScreen(false)` is only a request; UI and diagnostics must never label its `void` return as foreground success.
- Only the first Activity resume after a successful request may read aggregate call state once; all missing-service, permission, and ordinary-exception cases retain the Yinxing UI.
- Do not catch `Error`/fatal throwables in the new platform boundary.
- Failure never restarts automatic-answer countdown; retry must be an explicit tap.
- Dialog primary and retry targets are each at least `68dp`, use complete visible text plus `contentDescription`, and remain reachable at 2x font in a `360dp x 540dp` constraint.
- Release metadata is exactly `versionCode=41`, `versionName=1.10.0-root-preview.25`; publish a Debug APK and `SHA256SUMS.txt`, with Preview 24 as rollback.

---

### Task 1: Bounded System Call UI Gateway and Resume Coordinator

**Files:**
- Create: `app/src/main/java/com/yinxing/launcher/feature/incoming/IncomingCallSystemUiGateway.kt`
- Create: `app/src/main/java/com/yinxing/launcher/feature/incoming/IncomingCallRecoveryCoordinator.kt`
- Create: `app/src/test/java/com/yinxing/launcher/feature/incoming/IncomingCallSystemUiGatewayTest.kt`
- Create: `app/src/test/java/com/yinxing/launcher/feature/incoming/IncomingCallRecoveryCoordinatorTest.kt`

**Interfaces:**
- Produces: `SystemCallUiRequestResult`, `IncomingDeviceCallState`, `IncomingCallSystemUiGateway`, `AndroidIncomingCallSystemUiGateway`, `IncomingCallResumeDecision`, and `IncomingCallRecoveryCoordinator` for Tasks 3 and 4.
- Consumes: Android `TelecomManager.showInCallScreen(false)` and one-shot `TelephonyManager.callState` only.

- [ ] **Step 1: Write gateway RED tests**

Create tests with injected lambdas proving exact behavior:

```kotlin
@Test fun requestUsesSystemCallUiWithoutDialpad() {
    var requests = 0
    val gateway = AndroidIncomingCallSystemUiGateway(
        requestSystemUi = { requests++ },
        readCallState = { TelephonyManager.CALL_STATE_RINGING }
    )
    assertEquals(SystemCallUiRequestResult.Requested, gateway.requestSystemCallUi())
    assertEquals(1, requests)
}

@Test fun requestReturnsOrdinaryFailureButDoesNotCatchFatalError() {
    val failure = IllegalStateException("telecom unavailable")
    val ordinary = gateway(request = { throw failure })
    assertSame(failure, (ordinary.requestSystemCallUi() as SystemCallUiRequestResult.Failed).error)
    assertThrows(AssertionError::class.java) {
        gateway(request = { throw AssertionError("fatal") }).requestSystemCallUi()
    }
}

@Test fun callStateMapsAllKnownValuesAndFailsClosed() {
    assertEquals(IncomingDeviceCallState.IDLE, gateway(state = { 0 }).currentCallState())
    assertEquals(IncomingDeviceCallState.RINGING, gateway(state = { 1 }).currentCallState())
    assertEquals(IncomingDeviceCallState.OFFHOOK, gateway(state = { 2 }).currentCallState())
    assertEquals(IncomingDeviceCallState.UNKNOWN, gateway(state = { 99 }).currentCallState())
    assertEquals(IncomingDeviceCallState.UNKNOWN, gateway(state = { throw SecurityException("denied") }).currentCallState())
}
```

Include a helper that supplies harmless defaults and a fatal-error state-read regression.

- [ ] **Step 2: Run gateway tests and capture RED**

Run:

```bash
env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home bash gradlew \
  :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.feature.incoming.IncomingCallSystemUiGatewayTest' \
  --no-daemon --console=plain
```

Expected: Kotlin compilation fails because the gateway types do not exist.

- [ ] **Step 3: Implement the gateway minimally**

Use these exact shapes:

```kotlin
internal sealed interface SystemCallUiRequestResult {
    data object Requested : SystemCallUiRequestResult
    data class Failed(val error: Exception) : SystemCallUiRequestResult
}

internal enum class IncomingDeviceCallState { IDLE, RINGING, OFFHOOK, UNKNOWN }

internal interface IncomingCallSystemUiGateway {
    fun requestSystemCallUi(): SystemCallUiRequestResult
    fun currentCallState(): IncomingDeviceCallState
}

internal class AndroidIncomingCallSystemUiGateway(
    private val requestSystemUi: () -> Unit,
    private val readCallState: () -> Int
) : IncomingCallSystemUiGateway {
    constructor(context: Context) : this(
        requestSystemUi = {
            requireNotNull(context.getSystemService(TelecomManager::class.java))
                .showInCallScreen(false)
        },
        readCallState = {
            @Suppress("DEPRECATION")
            requireNotNull(context.getSystemService(TelephonyManager::class.java)).callState
        }
    )

    override fun requestSystemCallUi(): SystemCallUiRequestResult = try {
        requestSystemUi()
        SystemCallUiRequestResult.Requested
    } catch (error: Exception) {
        SystemCallUiRequestResult.Failed(error)
    }

    override fun currentCallState(): IncomingDeviceCallState = try {
        when (readCallState()) {
            TelephonyManager.CALL_STATE_IDLE -> IncomingDeviceCallState.IDLE
            TelephonyManager.CALL_STATE_RINGING -> IncomingDeviceCallState.RINGING
            TelephonyManager.CALL_STATE_OFFHOOK -> IncomingDeviceCallState.OFFHOOK
            else -> IncomingDeviceCallState.UNKNOWN
        }
    } catch (_: Exception) {
        IncomingDeviceCallState.UNKNOWN
    }
}
```

- [ ] **Step 4: Write coordinator RED tests**

Test `NO_PENDING` without a state read, request failure without a pending marker, a successful request consumed by exactly one resume, `RINGING -> KEEP_RINGING`, `UNKNOWN -> KEEP_UNKNOWN`, `OFFHOOK -> FINISH_ANSWERED`, `IDLE -> FINISH_ENDED`, `reset()`, and `restoreAwaitingSystemUiReturn()`.

```kotlin
@Test fun successfulRequestReadsExactlyOnceOnNextResume() {
    val gateway = FakeGateway(request = Requested, state = OFFHOOK)
    val coordinator = IncomingCallRecoveryCoordinator(gateway)
    assertEquals(Requested, coordinator.requestSystemCallUi())
    assertEquals(0, gateway.stateReads)
    assertEquals(FINISH_ANSWERED, coordinator.onHostResumed())
    assertEquals(1, gateway.stateReads)
    assertEquals(NO_PENDING, coordinator.onHostResumed())
    assertEquals(1, gateway.stateReads)
}
```

- [ ] **Step 5: Run coordinator tests and capture RED**

Use the same Gradle command with `--tests '*IncomingCallRecoveryCoordinatorTest'`.

Expected: compilation fails because coordinator types do not exist.

- [ ] **Step 6: Implement coordinator minimally**

```kotlin
internal enum class IncomingCallResumeDecision {
    NO_PENDING, KEEP_RINGING, KEEP_UNKNOWN, FINISH_ANSWERED, FINISH_ENDED
}

internal class IncomingCallRecoveryCoordinator(
    private val gateway: IncomingCallSystemUiGateway
) {
    internal var awaitingSystemUiReturn: Boolean = false
        private set

    fun requestSystemCallUi(): SystemCallUiRequestResult {
        return gateway.requestSystemCallUi().also {
            awaitingSystemUiReturn = it is SystemCallUiRequestResult.Requested
        }
    }

    fun onHostResumed(): IncomingCallResumeDecision {
        if (!awaitingSystemUiReturn) return IncomingCallResumeDecision.NO_PENDING
        awaitingSystemUiReturn = false
        return when (gateway.currentCallState()) {
            IncomingDeviceCallState.RINGING -> IncomingCallResumeDecision.KEEP_RINGING
            IncomingDeviceCallState.OFFHOOK -> IncomingCallResumeDecision.FINISH_ANSWERED
            IncomingDeviceCallState.IDLE -> IncomingCallResumeDecision.FINISH_ENDED
            IncomingDeviceCallState.UNKNOWN -> IncomingCallResumeDecision.KEEP_UNKNOWN
        }
    }

    fun restoreAwaitingSystemUiReturn() { awaitingSystemUiReturn = true }
    fun reset() { awaitingSystemUiReturn = false }
}
```

- [ ] **Step 7: Run both focused tests GREEN and commit**

Run both new test classes, then:

```bash
git add app/src/main/java/com/yinxing/launcher/feature/incoming/IncomingCallSystemUiGateway.kt \
  app/src/main/java/com/yinxing/launcher/feature/incoming/IncomingCallRecoveryCoordinator.kt \
  app/src/test/java/com/yinxing/launcher/feature/incoming/IncomingCallSystemUiGatewayTest.kt \
  app/src/test/java/com/yinxing/launcher/feature/incoming/IncomingCallRecoveryCoordinatorTest.kt
git commit -m "feat: add bounded incoming call system fallback"
```

### Task 2: Observable Diagnostics and Recovered-Success Semantics

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/feature/incoming/IncomingCallDiagnostics.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/feature/incoming/IncomingCallDiagnosticsTest.kt`
- Modify: `app/src/main/res/values/strings.xml`

**Interfaces:**
- Produces: `recordSystemCallUiRequested`, `recordSystemCallUiRequestFailure`, `recordSystemCallUiAnswered`, and `recordSystemCallUiEnded` for Task 4.
- Preserves: existing chain uniqueness and exact `IncomingCallFailureReason` storage until a confirmed recovered success/end state.

- [ ] **Step 1: Add RED diagnostic tests**

Add tests that:

```kotlin
@Test fun failedThenSuccessfulRetryKeepsStepsButClearsCurrentFailure() {
    val reason = IncomingCallFailureReason(PhonePermission, "missing")
    diagnostics.recordAcceptFailure(context, "failed", reason)
    diagnostics.recordAcceptSuccess(context, "sent")
    assertTrue(diagnostics.getSummaryText(context).contains("接听失败"))
    assertTrue(diagnostics.getSummaryText(context).contains("接听成功"))
    assertFalse(diagnostics.getDisplayText(context).contains("失败分类"))
}

@Test fun systemUiRequestIsNotLabeledSuccessAndFailureKeepsOriginalReason() {
    diagnostics.recordDeclineFailure(context, "failed", reason)
    diagnostics.recordSystemCallUiRequested(context)
    assertTrue(diagnostics.getSummaryText(context).contains("已请求系统电话界面"))
    assertTrue(diagnostics.getDisplayText(context).contains("失败分类"))
    diagnostics.recordSystemCallUiRequestFailure(context, SecurityException("denied"))
    assertTrue(diagnostics.getDisplayText(context).contains("denied"))
}
```

Also verify observed `OFFHOOK`/ended methods clear current failure and append distinct labels.

- [ ] **Step 2: Run diagnostics tests RED**

Run `IncomingCallDiagnosticsTest` only.

Expected: compilation fails for missing methods and resource labels; the recovered-success assertion would also fail against existing failure retention.

- [ ] **Step 3: Implement exact diagnostic steps**

Add steps and strings with these visible labels:

```text
SystemCallUiRequested = 系统电话界面已请求
SystemCallUiRequestFailed = 系统电话界面请求失败
SystemCallUiAnswered = 系统电话已接通
SystemCallUiEnded = 系统来电已结束
```

Add `preserveStoredFailure: Boolean = true` to private `append`. Compute the stored failure as:

```kotlin
val storedFailure = when {
    failureReason != null -> failureReason
    preserveStoredFailure -> readFailureReason(context)
    else -> null
}
```

Use `preserveStoredFailure = false` for `recordAcceptSuccess`, `recordDeclineSuccess`, `recordSystemCallUiAnswered`, and `recordSystemCallUiEnded`. Request and request-failure steps retain the original action failure. The request-failure detail must include exception class and message without changing the original failure category.

- [ ] **Step 4: Run diagnostics and state tests GREEN, then commit**

Run `IncomingCallDiagnosticsTest`, `IncomingCallStateMachineTest`, and `IncomingCallFailureCategoryTest`.

```bash
git add app/src/main/java/com/yinxing/launcher/feature/incoming/IncomingCallDiagnostics.kt \
  app/src/test/java/com/yinxing/launcher/feature/incoming/IncomingCallDiagnosticsTest.kt \
  app/src/main/res/values/strings.xml
git commit -m "feat: record incoming call recovery outcomes"
```

### Task 3: Elderly-Readable Incoming Failure Dialog

**Files:**
- Create: `app/src/main/java/com/yinxing/launcher/feature/incoming/IncomingCallFailureDialog.kt`
- Create: `app/src/main/res/layout/dialog_incoming_call_failure.xml`
- Create: `app/src/test/java/com/yinxing/launcher/feature/incoming/IncomingCallFailureDialogTest.kt`
- Modify: `app/src/main/res/values/strings.xml`

**Interfaces:**
- Consumes: `SystemCallUiRequestResult` from Task 1 and existing `IncomingCallFailureReason`.
- Produces: `IncomingCallFailedAction` and `AppCompatActivity.showIncomingCallFailureDialog(...)` for Task 4.

- [ ] **Step 1: Add dialog RED tests**

Test accept/decline title and retry text, blank caller fallback, all three category messages, primary/secondary minimum height and accessibility descriptions, successful system request dismissal, failed system request persistence/message replacement, retry dismissal/callback, Back cancellation, title line/ellipsis bounds, and 2x-font constrained measurement.

Use the exact call shape:

```kotlin
val dialog = activity.showIncomingCallFailureDialog(
    callerName = "王大爷",
    action = IncomingCallFailedAction.ACCEPT,
    reason = IncomingCallFailureReason(IncomingCallFailureCategory.PhonePermission, "missing"),
    onOpenSystemCall = { SystemCallUiRequestResult.Requested },
    onRetry = { retries++ }
)
```

For the failed request case, return `Failed(SecurityException("denied"))`, click the primary button, and assert the dialog remains showing and message becomes `incoming_call_failure_system_ui_failed_message`.

- [ ] **Step 2: Run dialog tests RED**

Run `IncomingCallFailureDialogTest` only.

Expected: compilation/resource linking fails because the dialog types, IDs, layout, and strings do not exist.

- [ ] **Step 3: Add exact strings and scroll-safe layout**

Add strings for accept/decline title, permission/unsupported/generic messages, system-UI failure, `打开系统电话`, `重新接听`, and `重新挂断`.

Build `dialog_incoming_call_failure.xml` as one `MaterialCardView` surface containing one `NestedScrollView`, then a vertical `LinearLayout` with title, message, primary `MaterialButton`, and secondary `MaterialButton`. Use existing `DialogSurfaceCard`, `DialogTitle`, and `DialogMessage` styles. Both buttons use `match_parent`, `minHeight=68dp`, `maxLines=2`, no all-caps, and stable 18dp corner radius. Do not nest cards.

- [ ] **Step 4: Implement the dialog helper**

```kotlin
internal enum class IncomingCallFailedAction { ACCEPT, DECLINE }

internal fun AppCompatActivity.showIncomingCallFailureDialog(
    callerName: String,
    action: IncomingCallFailedAction,
    reason: IncomingCallFailureReason,
    onOpenSystemCall: () -> SystemCallUiRequestResult,
    onRetry: () -> Unit
): AlertDialog
```

Normalize blank caller to `incoming_call_unknown_caller`. Map category to permission, unsupported, or generic message. Set cancelable true and `setCanceledOnTouchOutside(false)`. On primary tap, dismiss only for `Requested`; for `Failed`, keep showing and replace only the message. On retry, dismiss then invoke the callback. Set window width to 92% and `WRAP_CONTENT` after `show()`.

- [ ] **Step 5: Run dialog tests GREEN and commit**

Run the dialog test plus `HomeAppFailureDialogTest` and `PhoneCallFallbackDialogTest` to protect shared visual conventions.

```bash
git add app/src/main/java/com/yinxing/launcher/feature/incoming/IncomingCallFailureDialog.kt \
  app/src/main/res/layout/dialog_incoming_call_failure.xml \
  app/src/test/java/com/yinxing/launcher/feature/incoming/IncomingCallFailureDialogTest.kt \
  app/src/main/res/values/strings.xml
git commit -m "feat: add persistent incoming call recovery dialog"
```

### Task 4: Incoming Activity Recovery Integration

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/feature/incoming/IncomingCallActivity.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/feature/incoming/IncomingCallActivitySmokeTest.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/feature/incoming/IncomingCallStatusSmokeTest.kt`

**Interfaces:**
- Consumes: all Task 1-3 types and methods.
- Produces: complete answer/reject failure recovery behavior with no changes to successful actions.

- [ ] **Step 1: Add Activity RED tests**

Explicitly deny `ANSWER_PHONE_CALLS` on SDK 34, then test:

```kotlin
@Test fun missingPermissionShowsPersistentAcceptRecoveryAndFailedState() {
    denyAnswerPermission()
    val activity = buildActivity("王大爷", autoAnswer = false)
    activity.btn_accept.performClick()
    idle()
    val dialog = ShadowAlertDialog.getLatestAlertDialog()
    assertTrue(dialog.isShowing)
    assertEquals("还没有接通 王大爷", dialog.titleText())
    assertTrue(IncomingCallSessionState.current() is IncomingCallState.Failed)
    assertTrue(activity.btn_accept.isEnabled)
    assertTrue(activity.btn_decline.isEnabled)
}
```

Add the decline equivalent; auto-answer failure leaves countdown hidden; retry dismisses and produces one replacement dialog; `onNewIntent` dismisses the old dialog and renders the new caller; destroy dismisses it. Add exact status tests that call the new internal `applyRecoveryResumeDecision(decision)` method: `FINISH_ANSWERED` must call `IncomingCallSessionState.answered()` and finish, while `FINISH_ENDED` must return the session to `Idle` and finish. `KEEP_RINGING`, `KEEP_UNKNOWN`, and `NO_PENDING` must not finish.

- [ ] **Step 2: Run Activity tests RED**

Run `IncomingCallActivitySmokeTest` and `IncomingCallStatusSmokeTest`.

Expected: assertions fail because only a Toast exists and no recovery dialog is shown.

- [ ] **Step 3: Wire Activity lifecycle and failure handling**

Add fields for current caller label, `AlertDialog?`, and `IncomingCallRecoveryCoordinator`. Instantiate the coordinator in `onCreate` with `AndroidIncomingCallSystemUiGateway(this)`. Restore/save an exact Boolean key for `awaitingSystemUiReturn`.

Factor shared failure code:

```kotlin
private fun handleActionFailure(
    action: IncomingCallFailedAction,
    result: IncomingCallActions.Result,
    retry: () -> Unit
) {
    actionInProgress = false
    setActionButtonsEnabled(true)
    val reason = result.failureReason
        ?: IncomingCallFailureReason(IncomingCallFailureCategory.Unknown, result.detail)
    showRecoveryDialog(action, reason, retry)
}
```

Keep `applyRecoveryResumeDecision(decision: IncomingCallResumeDecision)` internal so the Activity mapping is directly covered without reflection. `onResume` calls this method with `recoveryCoordinator.onHostResumed()`.

The dialog's system callback calls the coordinator, records requested or request-failed diagnostics, and returns the exact result to the dialog. Its retry callback invokes `acceptCall()` or `declineCall()` after dialog dismissal. An identity-checked `OnDismissListener` clears only the current dialog reference.

Override `onResume` and map decisions:

```kotlin
FINISH_ANSWERED -> {
    IncomingCallSessionState.answered()
    IncomingCallDiagnostics.recordSystemCallUiAnswered(this)
    IncomingCallForegroundService.stop(this)
    finish()
}
FINISH_ENDED -> {
    IncomingCallSessionState.idle()
    IncomingCallDiagnostics.recordSystemCallUiEnded(this)
    IncomingCallForegroundService.stop(this)
    finish()
}
else -> Unit
```

`resetUiState` and `onDestroy` dismiss the dialog and reset the coordinator. Remove both failure Toasts and the now-unused Toast import. Do not alter success blocks except shared cleanup before `finish()`.

- [ ] **Step 4: Run Activity/incoming package GREEN**

Run all `com.yinxing.launcher.feature.incoming.*` tests. Confirm XML totals have zero failures/errors/skips.

- [ ] **Step 5: Review focused diff and commit**

Run:

```bash
git diff --check
git diff -- app/src/main/java/com/yinxing/launcher/feature/incoming \
  app/src/main/res/layout/dialog_incoming_call_failure.xml \
  app/src/main/res/values/strings.xml
```

Verify no success-path platform read and no manifest/service/receiver/root change.

```bash
git add app/src/main/java/com/yinxing/launcher/feature/incoming/IncomingCallActivity.kt \
  app/src/test/java/com/yinxing/launcher/feature/incoming/IncomingCallActivitySmokeTest.kt \
  app/src/test/java/com/yinxing/launcher/feature/incoming/IncomingCallStatusSmokeTest.kt
git commit -m "feat: recover failed incoming call actions"
```

### Task 5: Preview 25 Version, Release Evidence, and Publication

**Files:**
- Modify: `app/build.gradle.kts`
- Create: `docs/release/yinxing-root-preview-25.md`
- Modify only if current repository convention requires: `README.md`, `docs/release.md`
- Generate ignored artifact: `out/release/yinxing-1.10.0-root-preview.25-debug.apk`
- Generate ignored artifact: `out/release/SHA256SUMS.txt`

**Interfaces:**
- Consumes: reviewed Tasks 1-4.
- Produces: rollback-capable GitHub prerelease `v1.10.0-root-preview.25` and fresh-download evidence.

- [ ] **Step 1: Bump exact version and write release notes**

Set:

```kotlin
versionCode = 41
versionName = "1.10.0-root-preview.25"
```

Release notes must document: persistent action-specific recovery; system call UI is request-only; one-shot return cleanup; exact diagnostics; no auto-retry; no Root/module/manifest/background change; Preview 18 module retained; Preview 24 rollback; Debug signing; no attached OnePlus claim; device steps for permission failure, retry, system UI, return cleanup, 2x font, and TalkBack.

- [ ] **Step 2: Run focused and full forced verification**

First run the complete incoming package. Then run:

```bash
/usr/bin/time -f 'FINAL_WALL_SECONDS=%e' env \
  GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest \
  --rerun-tasks --no-daemon --console=plain
```

Parse all JUnit XML and require zero failures/errors/skips. Run `:app:lintDebug` separately and compare every error with Preview 24's two inherited `RootCommandRunner.kt` API-26 findings. Run `git diff --check` and prove `root/`, manifest, services, receivers, and background scheduling are unchanged.

- [ ] **Step 3: Independently review the complete branch**

Review from `93942c8..HEAD` for stale dialog lifecycle, false system-UI success, permission/fatal-error handling, retry races, recovered diagnostic correctness, 2x-font reachability, and accidental success-path/power work. Add a failing regression for every valid issue before fixing it, then repeat focused and full verification.

- [ ] **Step 4: Package and inspect candidate**

Copy the final Debug APK to the exact asset name, generate `SHA256SUMS.txt` from inside `out/release`, and verify it. Use SDK `aapt2` and `apksigner` to confirm package, versionCode 41, versionName Preview 25, min/target SDK 24/36, one Android Debug signer, and v2 signing. Record byte size and SHA-256. Confirm `adb devices -l` before making any device claim.

- [ ] **Step 5: Commit release source and verify merged main**

Commit version/release documentation. Fast-forward local `main` only after all branch gates pass, rerun the full merged-main unit suite, then push `main` and `feat/elderly-incoming-recovery-preview-25`.

- [ ] **Step 6: Tag, publish, and fresh-download verify**

Create annotated tag `v1.10.0-root-preview.25` on the exact verified source. Publish with explicit `--repo Gs-ygc/yinxing` as a non-draft prerelease containing exactly the APK and checksum file. Download both assets into a fresh `mktemp -d` directory and verify checksum, byte equality with local candidate, package/version/signature, normalized body, asset names/sizes/digests, and remote main/feature/tag equality.

- [ ] **Step 7: Record evidence and clean isolation**

Append exact build/test/lint/artifact/release evidence to `.planning` without committing it. Remove the clean Preview 25 worktree only after remote verification. Keep Phase 46 device acceptance and the long-running elderly Goal active because no physical OnePlus 15 evidence exists.
