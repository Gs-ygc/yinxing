# 老年首页常用电话快捷拨号 Preview 19 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将首页可信联系人拨号缩短为一次大触控操作，并让首页与电话簿共享同一套权限、降级和防重复拨号行为。

**Architecture:** `HomeViewModel` 通过可注入的 `HomeTrustedContactSource` 异步读取现有电话联系人，`HomeTrustedContactPolicy` 过滤并选出最多两个联系人。新增的 `HomeTrustedContactsController` 只负责稳定首页控件的绑定；共用 `PhoneCallLauncher` 负责权限、`ACTION_CALL`、1.2 秒防连点和 `ACTION_DIAL` 降级，两个 Activity 通过回调接入各自生命周期。

**Tech Stack:** Kotlin, AndroidX Lifecycle/Activity Result, Material Components, RecyclerView/ViewBinding, Kotlin coroutines, JUnit 4, Robolectric, Android instrumentation.

## Global Constraints

- 目标设备固定为 OnePlus 15、中国版 ColorOS 16、KernelSU 已 Root；本 Preview 不修改 KernelSU module 或 BusyBox。
- 普通 APK 拨号必须在 Root 缺失时仍可用；不可依赖无障碍或厂商私有 API。
- 快捷联系人最多两个，只有非空手机号可进入快捷区；排序沿用 `ContactStorage.sort`。
- 每个快捷项只有一个 TalkBack 动作目标，触控高度不小于 96dp，姓名最多两行、号码单行省略。
- 无法直接拨号时必须提供带号码的 `ACTION_DIAL` 降级，并保留取消操作。
- 不新增后台轮询、常驻服务、自动拨号或紧急联系人语义。
- 使用 `GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home` 和 `JAVA_HOME=/tmp/yinxing-jdk21-review` 运行 Gradle。

## File Map

- Create: `app/src/main/java/com/yinxing/launcher/feature/home/HomeTrustedContactPolicy.kt` — 纯 Kotlin 过滤、排序、数量上限。
- Create: `app/src/main/java/com/yinxing/launcher/feature/home/HomeTrustedContactsController.kt` — 首页快捷区渲染和点击转发。
- Create: `app/src/main/java/com/yinxing/launcher/feature/phone/PhoneCallLauncher.kt` — 两个 Activity 共用的拨号状态机。
- Create: `app/src/main/java/com/yinxing/launcher/feature/phone/PhoneCallFallbackDialog.kt` — 共用降级对话框构建。
- Create: `app/src/main/res/layout/item_home_trusted_calls.xml` — 首页快捷区标题、全部电话按钮和动态项容器。
- Create: `app/src/main/res/layout/item_home_trusted_call.xml` — 单个大触控联系人项。
- Modify: `app/src/main/java/com/yinxing/launcher/feature/home/HomeViewModel.kt` — 联系人 source、StateFlow、刷新和 Android source。
- Modify: `app/src/main/java/com/yinxing/launcher/feature/home/MainActivity.kt` — 首页区域、权限回调和共用拨号接入。
- Modify: `app/src/main/java/com/yinxing/launcher/feature/home/HomeNavigator.kt` — 提供明确的全部电话导航入口。
- Modify: `app/src/main/java/com/yinxing/launcher/feature/phone/PhoneContactActivity.kt` — 改用 `PhoneCallLauncher` 和共用降级对话框。
- Modify: `app/src/main/java/com/yinxing/launcher/data/home/LauncherAppRepository.kt` — 将电话入口文案改为“全部电话”（资源驱动，无逻辑变化）。
- Modify: `app/src/main/res/layout/activity_main.xml` — 在天气和应用网格之间 include 快捷区。
- Modify: `app/src/main/res/values/strings.xml` — 首页快捷区和“全部电话”文案。
- Create: `app/src/test/java/com/yinxing/launcher/feature/home/HomeTrustedContactPolicyTest.kt` — 选择策略行为测试。
- Create: `app/src/test/java/com/yinxing/launcher/feature/phone/PhoneCallLauncherTest.kt` — 拨号状态机测试。
- Modify: `app/src/test/java/com/yinxing/launcher/feature/home/HomeViewModelTest.kt` — source 加载、刷新和失败保留测试。
- Modify: `app/src/test/java/com/yinxing/launcher/feature/home/MainActivitySmokeTest.kt` — 无联系人快捷区空态回归。
- Modify: `app/src/androidTest/java/com/yinxing/launcher/feature/home/MainActivityInstrumentedTest.kt` — 快捷项和全部电话入口验收。

### Task 1: Lock the trusted-contact selection contract

**Files:**
- Create: `app/src/test/java/com/yinxing/launcher/feature/home/HomeTrustedContactPolicyTest.kt`
- Create: `app/src/main/java/com/yinxing/launcher/feature/home/HomeTrustedContactPolicy.kt`

**Interfaces:**
- Produces `object HomeTrustedContactPolicy` with `const val MAX_CONTACTS = 2` and `fun select(contacts: List<Contact>, maxContacts: Int = MAX_CONTACTS): List<Contact>`.

- [ ] **Step 1: Write the failing tests**

  Add tests that pass pinned, recent, unpinned, and no-number `Contact` values and assert that only callable contacts are returned in `ContactStorage.sort` order, that the default result has at most two items, and that `maxContacts = 1` works.

  ```kotlin
  @Test
  fun selectFiltersMissingNumbersSortsAndCapsAtTwo() {
      val result = HomeTrustedContactPolicy.select(
          listOf(
              Contact("old", "旧", phoneNumber = "100", isPinned = true),
              Contact("missing", "无号"),
              Contact("recent", "最近", phoneNumber = "200", lastCallTime = 20),
              Contact("count", "次数", phoneNumber = "300", callCount = 5)
          )
      )
      assertEquals(listOf("old", "count"), result.map { it.id })
  }
  ```

- [ ] **Step 2: Run the focused test and verify RED**

  Run `GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home JAVA_HOME=/tmp/yinxing-jdk21-review bash gradlew :app:testDebugUnitTest --tests '*HomeTrustedContactPolicyTest' --no-daemon --console=plain`.

  Expected: compilation/test failure because `HomeTrustedContactPolicy` does not exist.

- [ ] **Step 3: Implement the minimal policy**

  Filter `phoneNumber?.isNotBlank() == true`, call `ContactStorage.sort`, clamp a negative limit to zero, and call `take(limit)`; do not copy or mutate the input list.

- [ ] **Step 4: Run the focused test and verify GREEN**

  Rerun the command from Step 2. Expected: all policy tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add app/src/main/java/com/yinxing/launcher/feature/home/HomeTrustedContactPolicy.kt app/src/test/java/com/yinxing/launcher/feature/home/HomeTrustedContactPolicyTest.kt
  git commit -m "test: define home trusted contact selection"
  ```

### Task 2: Add asynchronous home contact state

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/feature/home/HomeViewModel.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/feature/home/HomeViewModelTest.kt`

**Interfaces:**
- Produces `val trustedContacts: StateFlow<List<Contact>>` and `fun refreshTrustedContacts()` on `HomeViewModel`.
- Produces `interface HomeTrustedContactSource { suspend fun getContacts(): List<Contact> }`.

- [ ] **Step 1: Extend the test fake and write failing tests**

  Add a fake source and tests asserting `refreshTrustedContacts()` emits the two selected contacts after the test dispatcher runs, a second refresh replaces the list after a simulated caregiver edit, and a failed refresh preserves a prior successful list.

  ```kotlin
  @Test
  fun refreshTrustedContactsSelectsCallableContacts() = runTest {
      val source = FakeHomeTrustedContactSource(listOf(
          Contact("1", "家人", phoneNumber = "13800138000", isPinned = true),
          Contact("2", "无号"),
          Contact("3", "邻居", phoneNumber = "13900139000")
      ))
      val viewModel = createViewModel(trustedContactSource = source)
      viewModel.refreshTrustedContacts()
      dispatcher.scheduler.runCurrent()
      assertEquals(listOf("1", "3"), viewModel.trustedContacts.value.map { it.id })
  }
  ```

- [ ] **Step 2: Run the focused tests and verify RED**

  Run `... bash gradlew :app:testDebugUnitTest --tests '*HomeViewModelTest.refreshTrustedContacts*' --no-daemon --console=plain`.

  Expected: compilation failure because the source/state API is absent.

- [ ] **Step 3: Implement the source and state**

  Add a cancellable refresh Job. The Android source must call `PhoneContactManager.getInstance(appContext).getContacts()` inside `withContext(Dispatchers.IO)`. On non-cancellation failure, leave the current StateFlow unchanged. Call `refreshTrustedContacts()` from `MainActivity.onResume()`; do not add a timer or receiver.

- [ ] **Step 4: Run HomeViewModel tests and verify GREEN**

  Run `... bash gradlew :app:testDebugUnitTest --tests '*HomeViewModelTest' --no-daemon --console=plain` and confirm all existing and new tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add app/src/main/java/com/yinxing/launcher/feature/home/HomeViewModel.kt app/src/test/java/com/yinxing/launcher/feature/home/HomeViewModelTest.kt
  git commit -m "feat: load trusted phone contacts on home"
  ```

### Task 3: Extract shared direct-call state machine

**Files:**
- Create: `app/src/main/java/com/yinxing/launcher/feature/phone/PhoneCallLauncher.kt`
- Create: `app/src/main/java/com/yinxing/launcher/feature/phone/PhoneCallFallbackDialog.kt`
- Create: `app/src/test/java/com/yinxing/launcher/feature/phone/PhoneCallLauncherTest.kt`

**Interfaces:**
- Produces `internal class PhoneCallLauncher` with constructor callbacks `hasCallPermission`, `requestPermission`, `launchIntent`, `showFallback`, and `onCallLaunched`; methods `makeCall(contact: Contact)`, `onPermissionResult(granted: Boolean)`, `restorePendingContact(contact: Contact)`, and read-only `pendingContactOrNull`.
- Produces `internal fun AppCompatActivity.showPhoneCallFallbackDialog(contact: Contact, directCallFailed: Boolean, onDialerFailure: (Throwable) -> Unit): AlertDialog`.

- [ ] **Step 1: Write failing state-machine tests**

  Use a fake clock and lambdas collecting real `Intent`/`Contact` values. Cover direct launch with permission, permission request then grant, denial fallback, duplicate taps inside 1,200 ms, launch exception fallback, success callback once, and blank number ignored.

- [ ] **Step 2: Run the focused test and verify RED**

  Run `... bash gradlew :app:testDebugUnitTest --tests '*PhoneCallLauncherTest' --no-daemon --console=plain`.

  Expected: compilation failure because the launcher class is absent.

- [ ] **Step 3: Implement the minimal launcher and dialog helper**

  Keep pending permission state inside the launcher; clear it exactly once when a result arrives. Acquire `PhoneCallLaunchGate` only when launching direct `ACTION_CALL`. Do not log full phone numbers. The dialog helper must reuse existing string resources and launch `PhoneCallIntentFactory.dialer(number)` only from its explicit button.

- [ ] **Step 4: Run focused and existing phone tests**

  Run `... bash gradlew :app:testDebugUnitTest --tests '*PhoneCallLauncherTest' --tests '*PhoneCallLaunchGateTest' --tests '*PhoneContactActivitySmokeTest' --no-daemon --console=plain`.

  Expected: PASS with no regression.

- [ ] **Step 5: Commit**

  ```bash
  git add app/src/main/java/com/yinxing/launcher/feature/phone/PhoneCallLauncher.kt app/src/main/java/com/yinxing/launcher/feature/phone/PhoneCallFallbackDialog.kt app/src/test/java/com/yinxing/launcher/feature/phone/PhoneCallLauncherTest.kt
  git commit -m "refactor: share reliable phone call launching"
  ```

### Task 4: Wire the phone page to the shared launcher

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/feature/phone/PhoneContactActivity.kt`

**Interfaces:**
- Consumes `PhoneCallLauncher` from Task 3.
- Preserves the existing saved-state keys and all manage/search behavior.

- [ ] **Step 1: Add a regression assertion before rewiring**

  Extend `PhoneContactActivitySmokeTest` with a source-level/behavior assertion that the phone page still exposes one call action per contact and retains `STATE_PENDING_CALL_NUMBER` on recreation; run the focused test to establish the expected current behavior.

- [ ] **Step 2: Rewire permission and adapter callbacks**

  Initialize `PhoneCallLauncher` in `onCreate`, route adapter calls to `makeCall`, route the existing Activity Result callback to `onPermissionResult`, restore saved pending contact through `restorePendingContact`, and use `pendingContactOrNull` in `onSaveInstanceState`.

- [ ] **Step 3: Replace the local fallback builder**

  Keep the existing dialog reference/lifecycle guard, but delegate dialog construction to `showPhoneCallFallbackDialog`; preserve the existing Toast on dialer failure.

- [ ] **Step 4: Run phone regression tests**

  Run `... bash gradlew :app:testDebugUnitTest --tests '*PhoneContactActivitySmokeTest' --tests '*PhoneActivitySmokeTest' --tests '*PhoneCallLauncherTest' --no-daemon --console=plain`.

- [ ] **Step 5: Commit**

  ```bash
  git add app/src/main/java/com/yinxing/launcher/feature/phone/PhoneContactActivity.kt
  git commit -m "refactor: route phone page through shared call launcher"
  ```

### Task 5: Build the stable home shortcut UI

**Files:**
- Create: `app/src/main/res/layout/item_home_trusted_calls.xml`
- Create: `app/src/main/res/layout/item_home_trusted_call.xml`
- Modify: `app/src/main/res/layout/activity_main.xml`
- Modify: `app/src/main/res/values/strings.xml`
- Create: `app/src/main/java/com/yinxing/launcher/feature/home/HomeTrustedContactsController.kt`
- Create: `app/src/test/java/com/yinxing/launcher/feature/home/HomeTrustedContactsControllerTest.kt`

**Interfaces:**
- Produces `HomeTrustedContactsController.render(contacts: List<Contact>)` and `setOnCallClick((Contact) -> Unit)`, `setOnOpenAllClick(() -> Unit)`.

- [ ] **Step 1: Write failing controller/policy UI tests**

  Inflate the section under Robolectric, render zero, one, and two callable contacts, and assert section visibility, child count, content descriptions, and that the full-list button remains visible for one or more contacts.

- [ ] **Step 2: Run the focused test and verify RED**

  Run `... bash gradlew :app:testDebugUnitTest --tests '*HomeTrustedContactsControllerTest' --no-daemon --console=plain`.

  Expected: compilation failure because the controller/layout are absent.

- [ ] **Step 3: Implement XML and controller**

  Use a title row plus a horizontal action container. Give each item `minHeight=96dp`, `weight=1`, no entry animation, one root click listener, and child views marked not important for accessibility when the root is the action target. Hide the section when `contacts.isEmpty()` and remove all old children before adding new ones.

- [ ] **Step 4: Run focused UI tests and resource compilation**

  Run `... bash gradlew :app:testDebugUnitTest --tests '*HomeTrustedContactsControllerTest' --no-daemon --console=plain`.

  Expected: PASS and successful resource compilation.

- [ ] **Step 5: Commit**

  ```bash
  git add app/src/main/res/layout/item_home_trusted_calls.xml app/src/main/res/layout/item_home_trusted_call.xml app/src/main/res/layout/activity_main.xml app/src/main/res/values/strings.xml app/src/main/java/com/yinxing/launcher/feature/home/HomeTrustedContactsController.kt app/src/test/java/com/yinxing/launcher/feature/home/HomeTrustedContactsControllerTest.kt
  git commit -m "feat: add one-tap trusted calls to home"
  ```

### Task 6: Wire MainActivity and preserve the full-list route

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/feature/home/MainActivity.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/feature/home/HomeNavigator.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/data/home/LauncherAppRepository.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/feature/home/MainActivitySmokeTest.kt`
- Modify: `app/src/androidTest/java/com/yinxing/launcher/feature/home/MainActivityInstrumentedTest.kt`

**Interfaces:**
- Consumes `HomeViewModel.trustedContacts`, `HomeTrustedContactsController`, and `PhoneCallLauncher`.
- `HomeNavigator.openPhoneContacts()` remains the single full-list navigation method; `openHomeItem(PHONE)` delegates to it.

- [ ] **Step 1: Add failing integration assertions**

  Seed two phone contacts in the instrumentation environment, assert two shortcut content descriptions appear without changing the app-grid count, assert the full-list button opens `PhoneContactActivity`, and assert the zero-contact section is `GONE` in the JVM smoke test.

- [ ] **Step 2: Run the new integration tests and verify RED**

  Run the focused JVM test and the connected-test source compilation task. Expected: missing view/controller wiring or IDs cause failure.

- [ ] **Step 3: Wire lifecycle and callbacks**

  Instantiate the controller and shared launcher before observing flows; collect `trustedContacts`; call `refreshTrustedContacts()` on `onResume`; save/restore a pending permission contact; and make fallback dialogs dismiss safely in `onDestroy`. Keep normal home navigation unchanged for non-phone tiles.

- [ ] **Step 4: Run home and phone integration tests**

  Run `... bash gradlew :app:testDebugUnitTest --tests '*MainActivitySmokeTest' --tests '*HomeTrustedContactsControllerTest' --tests '*PhoneContactActivitySmokeTest' --no-daemon --console=plain`, then `... bash gradlew :app:compileDebugAndroidTestKotlin --no-daemon --console=plain`.

- [ ] **Step 5: Commit**

  ```bash
  git add app/src/main/java/com/yinxing/launcher/feature/home/MainActivity.kt app/src/main/java/com/yinxing/launcher/feature/home/HomeNavigator.kt app/src/main/java/com/yinxing/launcher/data/home/LauncherAppRepository.kt app/src/test/java/com/yinxing/launcher/feature/home/MainActivitySmokeTest.kt app/src/androidTest/java/com/yinxing/launcher/feature/home/MainActivityInstrumentedTest.kt
  git commit -m "feat: wire trusted calls into launcher home"
  ```

### Task 7: Full verification and release preparation

**Files:**
- Modify: `app/build.gradle.kts` — bump Preview 19 version metadata only after behavior is green.
- Create: `docs/release/yinxing-root-preview-19.md` — release evidence and explicit device gates.
- Modify: `.planning/2026-08-07-android-build-verification/{task_plan.md,findings.md,progress.md}` — record phase and measurements.

- [ ] **Step 1: Run the complete JVM suite**

  Run `GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home JAVA_HOME=/tmp/yinxing-jdk21-review bash gradlew :app:testDebugUnitTest --no-daemon --console=plain`; aggregate JUnit XML and record test count/failures.

- [ ] **Step 2: Run Android build and instrumentation APK compilation**

  Run `... bash gradlew :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest --rerun-tasks --no-daemon --console=plain`; record wall time and APK metadata. Run `adb devices -l` and state clearly if no OnePlus 15 is attached.

- [ ] **Step 3: Run lint and classify output**

  Run `... bash gradlew :app:lintDebug --no-daemon --console=plain`; verify no new errors beyond the two pre-existing `RootCommandRunner.kt` min-SDK API errors.

- [ ] **Step 4: Run the existing Root release matrix without changing Root code**

  Run `bash tools/test-yinxing-guard.sh all`; record PASS/FAIL and duration. This is a release regression gate, not the Preview 19 product objective.

- [ ] **Step 5: Request independent code review and close findings**

  Read `requesting-code-review` instructions, review the diff against `main`, and resolve any Critical/Important findings before packaging. Re-run affected tests after every fix.

- [ ] **Step 6: Package and publish Preview 19**

  Build deterministic APK/module assets using the repository's existing release scripts, verify checksums, ZIP integrity, APK metadata/signature, and GitHub remote byte identity. Push the release commit/tag to `origin` and create a prerelease with the release document. Do not claim ColorOS 16 runtime latency, power, TalkBack, or dialer takeover until device evidence exists.

- [ ] **Step 7: Commit evidence and update persistent plan**

  Commit the release document and plan updates, push `main`, and leave the Goal active for the user's OnePlus 15 feedback.
