# Preview 23 Elderly Video Takeover Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the WeChat video takeover immediately actionable, continuously identify the target contact, and provide one obvious tap-to-cancel action without changing automation decisions or background behavior.

**Architecture:** Keep `SelectToSpeakService` as the existing automation/session owner and `FloatingStatusView` as its only overlay boundary. Make overlay binding directly testable, format one localized contact title for service updates, and remove presentation-only animation from the video contact list. Existing cancellation, terminal callbacks, timeout, launcher return, and Root behavior remain authoritative.

**Tech Stack:** Kotlin, Android AccessibilityService and WindowManager overlay, Material XML, RecyclerView/ListAdapter, JUnit 4, Robolectric, Gradle Android plugin.

## Global Constraints

- Overlay title is `正在联系 %1$s`; the status line contains only the existing plain-language current action.
- Cancel is a visible `取消` action with content description `取消联系`, at least 56dp in both dimensions, and responds to one ordinary tap.
- Cancel continues through the existing `cancelSession(true)` listener; do not add a second cancellation state machine.
- Video contacts and RecyclerView updates have no entry/item animation.
- Keep WindowManager flags, automation selectors, navigation, adaptive delays, retry budgets, timeouts, callbacks, and launcher-return behavior unchanged.
- Add no Activity, service, receiver, timer, polling loop, network request, wake lock, setting, shell command, Root allowlist, BusyBox dependency, or KernelSU asset.
- Do not claim OnePlus 15/ColorOS 16 runtime latency, return-Home, Accessibility recovery, or power evidence from local tests.

---

### Task 1: Explicit single-tap overlay cancellation

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/common/ui/FloatingStatusView.kt`
- Modify: `app/src/main/res/layout/floating_status.xml`
- Modify: `app/src/main/res/values/strings.xml`
- Create: `app/src/test/java/com/yinxing/launcher/common/ui/FloatingStatusViewTest.kt`

**Interfaces:**
- Preserves: `FloatingStatusView.setOnCancelListener(listener: () -> Unit)`.
- Produces: `internal fun bindCancelAction(view: View)` for listener binding without adding a WindowManager view in tests.
- Produces: `internal fun bindText(view: View, title: String, status: String?)` for deterministic two-line rendering.

- [ ] **Step 1: Write failing overlay layout and interaction tests**

Create a Robolectric test that inflates `floating_status` and requires the elder-facing contract:

```kotlin
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class FloatingStatusViewTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun cancelActionIsExplicitLargeAndAccessible() {
        val root = LayoutInflater.from(context)
            .inflate(R.layout.floating_status, FrameLayout(context), false)
        val cancel = root.findViewById<TextView>(R.id.tv_cancel)

        assertEquals(context.getString(R.string.video_call_overlay_cancel), cancel.text.toString())
        assertEquals(
            context.getString(R.string.video_call_overlay_cancel_description),
            cancel.contentDescription.toString()
        )
        assertTrue(cancel.minimumWidth >= context.dp(56))
        assertTrue(cancel.minimumHeight >= context.dp(56))
        assertFalse(cancel.text.toString() == "×")
    }

    @Test
    fun ordinaryCancelTapInvokesListenerOnce() {
        val root = LayoutInflater.from(context)
            .inflate(R.layout.floating_status, FrameLayout(context), false)
        var cancellations = 0
        val statusView = FloatingStatusView(context)
        statusView.setOnCancelListener { cancellations += 1 }
        statusView.bindCancelAction(root)

        assertTrue(root.findViewById<View>(R.id.tv_cancel).performClick())
        assertEquals(1, cancellations)
    }

    @Test
    fun textBindingKeepsContactAndStatusSeparate() {
        val root = LayoutInflater.from(context)
            .inflate(R.layout.floating_status, FrameLayout(context), false)
        val statusView = FloatingStatusView(context)

        statusView.bindText(root, "正在联系 女儿", "正在打开微信")
        assertEquals("正在联系 女儿", root.findViewById<TextView>(R.id.tv_status).text.toString())
        assertEquals("正在打开微信", root.findViewById<TextView>(R.id.tv_status_step).text.toString())
        assertEquals(View.VISIBLE, root.findViewById<View>(R.id.tv_status_step).visibility)

        statusView.bindText(root, "正在联系 女儿", null)
        assertEquals(View.GONE, root.findViewById<View>(R.id.tv_status_step).visibility)
    }
}
```

The local `dp` helper multiplies by `resources.displayMetrics.density` and rounds to `Int`.

- [ ] **Step 2: Run Task 1 test and confirm RED**

Run:

```bash
GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home bash gradlew \
  :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.common.ui.FloatingStatusViewTest' \
  --no-daemon --console=plain
```

Expected: test compilation fails because `bindCancelAction` and the view-accepting `bindText` overload do not exist. The current layout also contains `x`, has a 36dp target, and lacks the new resources.

- [ ] **Step 3: Implement the explicit action and testable binding boundary**

Add exact resources:

```xml
<string name="video_call_overlay_cancel">取消</string>
<string name="video_call_overlay_cancel_description">取消联系</string>
```

Replace `tv_cancel` with a Material text button using fixed `88dp` width, `56dp` height, zero insets, `18sp` bold white text, an 8dp corner radius, and a visible `launcher_on_overlay_muted` stroke. Give the text column a bounded `210dp` width and both text views `maxLines="2"` so font scaling cannot push the action outside the overlay.

Refactor binding without changing show/hide error containment:

```kotlin
private var onCancelRequest: (() -> Unit)? = null

fun setOnCancelListener(listener: () -> Unit) {
    onCancelRequest = listener
    floatingView?.let(::bindCancelAction)
}

internal fun bindCancelAction(view: View) {
    view.findViewById<View>(R.id.tv_cancel).setOnClickListener {
        onCancelRequest?.invoke()
    }
}

internal fun bindText(view: View, title: String, status: String?) {
    view.findViewById<TextView>(R.id.tv_status).text = title
    view.findViewById<TextView>(R.id.tv_status_step).apply {
        isVisible = !status.isNullOrBlank()
        text = status.orEmpty()
    }
}
```

Keep private wrappers that use `floatingView ?: return`, so the public `show` and `updateMessage` signatures remain unchanged.

- [ ] **Step 4: Run Task 1 GREEN and commit**

Run the Step 2 command, then:

```bash
git add app/src/main/java/com/yinxing/launcher/common/ui/FloatingStatusView.kt \
  app/src/main/res/layout/floating_status.xml app/src/main/res/values/strings.xml \
  app/src/test/java/com/yinxing/launcher/common/ui/FloatingStatusViewTest.kt
git commit -m "feat: make video takeover easy to cancel"
```

---

### Task 2: Stable contact-specific takeover copy

**Files:**
- Create: `app/src/main/java/com/yinxing/launcher/feature/videocall/VideoCallOverlayCopy.kt`
- Modify: `app/src/main/java/com/google/android/accessibility/selecttospeak/SelectToSpeakService.kt`
- Modify: `app/src/main/res/values/strings.xml`
- Create: `app/src/test/java/com/yinxing/launcher/feature/videocall/VideoCallOverlayCopyTest.kt`

**Interfaces:**
- Produces: `internal fun Context.videoCallOverlayTitle(rawContactName: String): String`.
- Consumes: unchanged `FloatingStatusView.show(title: String, stepLabel: String?)` and `updateMessage(title: String, stepLabel: String?)` signatures.

- [ ] **Step 1: Write failing contact-title tests**

```kotlin
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class VideoCallOverlayCopyTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun contactTitleTrimsAndNamesTheTarget() {
        assertEquals("正在联系 女儿", context.videoCallOverlayTitle("  女儿  "))
    }

    @Test
    fun blankContactTitleUsesExistingContactFallback() {
        assertEquals("正在联系 联系人", context.videoCallOverlayTitle("   "))
    }
}
```

- [ ] **Step 2: Run Task 2 test and confirm RED**

Run:

```bash
GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home bash gradlew \
  :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.feature.videocall.VideoCallOverlayCopyTest' \
  --no-daemon --console=plain
```

Expected: compilation fails because `videoCallOverlayTitle` is missing.

- [ ] **Step 3: Implement localized title formatting and service wiring**

Add:

```xml
<string name="video_call_overlay_contact_title">正在联系 %1$s</string>
```

Implement:

```kotlin
internal fun Context.videoCallOverlayTitle(rawContactName: String): String {
    val contactName = rawContactName.trim().ifBlank {
        getString(R.string.contact_name_placeholder)
    }
    return getString(R.string.video_call_overlay_contact_title, contactName)
}
```

In `SelectToSpeakService`, import the extension and change only visible overlay copy:

```kotlin
floatingView?.show(
    videoCallOverlayTitle(session.contactName),
    "正在打开微信"
)

floatingView?.updateMessage(
    videoCallOverlayTitle(session.contactName),
    message
)
```

At successful completion use the same title with `视频通话已发起` as status. Remove the now-unused `VideoCallSession.stepLabel()` function. Preserve `stepNumber()` and `stepName()` because logs and metrics still consume them.

- [ ] **Step 4: Run copy, overlay, and service lifecycle tests GREEN, then commit**

Run:

```bash
GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home bash gradlew \
  :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.feature.videocall.VideoCallOverlayCopyTest' \
  --tests 'com.yinxing.launcher.common.ui.FloatingStatusViewTest' \
  --tests 'com.google.android.accessibility.selecttospeak.KioskLauncherGuardTest' \
  --no-daemon --console=plain
```

Then:

```bash
git add app/src/main/java/com/yinxing/launcher/feature/videocall/VideoCallOverlayCopy.kt \
  app/src/main/java/com/google/android/accessibility/selecttospeak/SelectToSpeakService.kt \
  app/src/main/res/values/strings.xml \
  app/src/test/java/com/yinxing/launcher/feature/videocall/VideoCallOverlayCopyTest.kt
git commit -m "feat: keep video contact visible during takeover"
```

---

### Task 3: Immediately actionable video contacts

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/feature/videocall/VideoCallActivity.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/feature/videocall/VideoCallContactAdapter.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/feature/videocall/VideoCallActivitySmokeTest.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/feature/videocall/ElderContactActionUiTest.kt`

**Interfaces:**
- Removes: `VideoCallContactAdapter.setAnimationsEnabled`, `animationsEnabled`, `animatedIds`, and `animateInIfFirstShow`.
- Preserves: `setLowPerformanceMode(enabled: Boolean)` and every contact/action callback.

- [ ] **Step 1: Write failing no-animation tests**

Add to `VideoCallActivitySmokeTest`:

```kotlin
@Test
fun videoListHasNoItemAnimator() {
    val activity = Robolectric.buildActivity(VideoCallActivity::class.java).setup().get()
    val recycler = activity.findViewById<RecyclerView>(R.id.recycler_video_contacts)
    assertNull(recycler.itemAnimator)
}
```

Add to `ElderContactActionUiTest` after binding one normal-performance contact:

```kotlin
assertEquals(1f, holder.itemView.alpha, 0f)
assertEquals(0f, holder.itemView.translationY, 0f)
```

- [ ] **Step 2: Run Task 3 tests and confirm RED**

Run:

```bash
GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home bash gradlew \
  :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.feature.videocall.VideoCallActivitySmokeTest' \
  --tests 'com.yinxing.launcher.feature.videocall.ElderContactActionUiTest' \
  --no-daemon --console=plain
```

Expected: the Activity exposes `DefaultItemAnimator`, and a newly bound normal-performance row starts with zero alpha/positive translation.

- [ ] **Step 3: Remove presentation delays without changing image performance**

In `VideoCallActivity.applyPerformanceMode`, keep cache sizing and low-performance propagation, but always set:

```kotlin
recyclerView.itemAnimator = null
```

In the adapter, remove `DecelerateInterpolator`, animation flags/history, `setAnimationsEnabled`, and the `animateInIfFirstShow` call. Bind every holder from a stable state:

```kotlin
override fun onBindViewHolder(holder: ViewHolder, position: Int) {
    holder.itemView.animate().cancel()
    holder.itemView.alpha = 1f
    holder.itemView.translationY = 0f
    bind(holder, getItem(position))
}
```

Keep thumbnail cancellation and all call/action accessibility binding unchanged.

- [ ] **Step 4: Run Task 3 and all video tests GREEN, then commit**

Run:

```bash
GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home bash gradlew \
  :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.feature.videocall.*' \
  --tests 'com.google.android.accessibility.selecttospeak.*' \
  --no-daemon --console=plain
```

Then:

```bash
git add app/src/main/java/com/yinxing/launcher/feature/videocall/VideoCallActivity.kt \
  app/src/main/java/com/yinxing/launcher/feature/videocall/VideoCallContactAdapter.kt \
  app/src/test/java/com/yinxing/launcher/feature/videocall/VideoCallActivitySmokeTest.kt \
  app/src/test/java/com/yinxing/launcher/feature/videocall/ElderContactActionUiTest.kt
git commit -m "perf: make video contacts immediately actionable"
```

---

### Task 4: Preview 23 release evidence and publication

**Files:**
- Modify: `app/build.gradle.kts`
- Create: `docs/release/yinxing-root-preview-23.md`
- Modify: this implementation plan to check completed steps as evidence is produced.

**Interfaces:**
- Produces: versionCode `39`, versionName `1.10.0-root-preview.23`.
- Produces: `out/release/yinxing-1.10.0-root-preview.23-debug.apk` and `out/release/SHA256SUMS.txt`.
- Produces: GitHub prerelease tag `v1.10.0-root-preview.23` with no new KernelSU module asset.

- [ ] **Step 1: Bump exact Preview 23 metadata and add acceptance notes**

Set:

```kotlin
versionCode = 39
versionName = "1.10.0-root-preview.23"
```

Write release notes covering the explicit cancel action, persistent contact/status, removed video-list animation, unchanged automation/Root/BusyBox boundary, OnePlus 15 acceptance sequence, Preview 22 rollback URL, and exact local verification evidence.

- [ ] **Step 2: Run the focused suite and changed-boundary checks**

Run all new and directly affected tests. Require:

```bash
git diff --check v1.10.0-root-preview.22..HEAD
git diff --name-only v1.10.0-root-preview.22..HEAD | \
  rg '(^|/)(root|kernel|module)(/|$)|tools/test-yinxing-guard\.sh' && exit 1 || true
rg -n 'setOnLongClickListener|第[0-9].*共|stepLabel\(' \
  app/src/main/java/com/yinxing/launcher/common/ui/FloatingStatusView.kt \
  app/src/main/java/com/google/android/accessibility/selecttospeak/SelectToSpeakService.kt \
  app/src/main/res/layout/floating_status.xml && exit 1 || true
```

- [ ] **Step 3: Independently review the complete Preview 22-to-23 range**

Review `v1.10.0-root-preview.22..HEAD` for cancel listener lifecycle, overlay clipping at large font, WindowManager touch/focus behavior, stale-session progress, RecyclerView recycling, accessibility semantics, and test weakness. Resolve every Critical/Important finding and rerun affected tests.

- [ ] **Step 4: Run final forced Android verification and classify lint**

Run in isolation:

```bash
/usr/bin/time -f 'ELAPSED_SECONDS=%e EXIT_STATUS=%x' \
  env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest :app:assembleDebug \
  :app:assembleDebugAndroidTest --rerun-tasks --no-daemon --console=plain
```

Require all tasks successful, all JUnit XML failures/errors/skips zero, both APKs present, and fresh test counts recorded. Then run `:app:lintDebug`; classify the existing `RootCommandRunner.kt` minSdk findings separately and require no new error in a Preview 23 changed file.

- [ ] **Step 5: Verify candidate metadata, signature, hash, and device boundary**

Use SDK `aapt2` and `apksigner` to require package `com.yinxing.launcher`, versionCode `39`, versionName `1.10.0-root-preview.23`, minSdk `24`, targetSdk `36`, and v2 Debug signing. Require `adb devices` evidence before making any device claim.

Copy the candidate to the exact release name and generate the checksum from inside `out/release`:

```bash
cp app/build/outputs/apk/debug/app-debug.apk \
  out/release/yinxing-1.10.0-root-preview.23-debug.apk
(
  cd out/release
  sha256sum yinxing-1.10.0-root-preview.23-debug.apk > SHA256SUMS.txt
  sha256sum -c SHA256SUMS.txt
)
```

- [ ] **Step 6: Commit release evidence, merge, publish, and verify remotely**

Commit final metadata/notes/evidence, fast-forward `main`, push feature/main, create annotated tag `v1.10.0-root-preview.23`, and publish a prerelease with exactly the APK and checksum assets. The notes link to the unchanged Preview 18 KernelSU module rather than repackaging it.

Download both assets into a fresh `mktemp -d` directory and require checksum success, byte-for-byte `cmp`, `aapt2` metadata, `apksigner` verification, exact GitHub asset list/body, and equality of remote `main`, feature branch, and peeled tag before reporting publication.
