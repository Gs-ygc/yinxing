# Preview 22 Stable Elderly Home Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the daily Home layout non-configurable while preserving explicit caregiver selection and ordering in the existing Home-app management screen.

**Architecture:** Keep `HomeAppOrderPolicy` as the pure source of truth for management ordering and adjacent moves. `LauncherAppRepository` supplies one selected-first management list, `AppManageActivity` persists checkbox and arrow actions, and the Home stack removes its `ADD` and drag-only state entirely. Existing preferences remain authoritative, so no migration or new mode is needed.

**Tech Stack:** Kotlin, Android RecyclerView/ListAdapter, Material XML layouts, SharedPreferences-backed `HomeAppConfig`, JUnit 4, Robolectric, Gradle Android plugin.

## Global Constraints

- Home contains only fixed daily actions and caregiver-selected applications; no `ADD` item or ordering long press.
- Selected management rows follow saved Home order; unselected rows follow locale-independent application-name order.
- Only selected rows expose 48dp up/down icon buttons with localized, app-specific TalkBack descriptions.
- First-up, last-down, missing, unselected, blank, or unsupported-offset moves are no-ops and do not rewrite preferences.
- Selection keeps existing append/remove order semantics.
- No PIN, edit mode, new Activity, overlay, service, receiver, timer, network request, Root command, or migration.
- Root, BusyBox, HOME takeover, boot recovery, Accessibility recovery, Doze, phone, and external application launch behavior remain unchanged.
- Device-only ColorOS latency, task-stack, accessibility, and power claims remain explicit acceptance gaps.

---

### Task 1: Pure caregiver ordering policy

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/data/home/HomeAppOrderPolicy.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/data/home/HomeAppOrderPolicyTest.kt`

**Interfaces:**
- Produces: `HomeAppOrderPolicy.orderManagementApps(apps: Collection<OrderedApp>, selectedPackages: Collection<String>, savedOrder: Collection<String>): List<OrderedApp>`
- Produces: `HomeAppOrderPolicy.moveSelectedPackage(currentOrder: Collection<String>, packageName: String, offset: Int): List<String>?`

- [ ] **Step 1: Write failing management-order tests**

Add tests proving selected packages follow saved order, selected packages omitted from saved order append by name, unselected packages follow by name, and stale/duplicate saved packages disappear:

```kotlin
val result = HomeAppOrderPolicy.orderManagementApps(
    apps = listOf(
        OrderedApp("pkg.alpha", "Alpha"),
        OrderedApp("pkg.beta", "Beta"),
        OrderedApp("pkg.gamma", "Gamma")
    ),
    selectedPackages = setOf("pkg.alpha", "pkg.gamma"),
    savedOrder = listOf("pkg.gamma", "pkg.missing", "pkg.gamma")
)
assertEquals(listOf("pkg.gamma", "pkg.alpha", "pkg.beta"), result.map { it.packageName })
```

- [ ] **Step 2: Write failing adjacent-move tests**

Cover up/down swaps and exact no-op cases. Compare complete lists so a no-op cannot silently discard another package:

```kotlin
assertEquals(
    listOf("pkg.beta", "pkg.alpha", "pkg.gamma"),
    HomeAppOrderPolicy.moveSelectedPackage(
        currentOrder = listOf("pkg.alpha", "pkg.beta", "pkg.gamma"),
        packageName = "pkg.alpha",
        offset = 1
    )
)
```

No-op cases return `null`: first package with `-1`, last with `1`, offset `0`, offset `2`, blank package, and a package absent from `currentOrder`.

- [ ] **Step 3: Run Task 1 tests and confirm RED**

Run:

```bash
GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home bash gradlew \
  :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.data.home.HomeAppOrderPolicyTest' \
  --no-daemon --console=plain
```

Expected: compilation fails because both policy methods are missing.

- [ ] **Step 4: Implement the two pure functions**

Use existing normalization and ordering rather than a second sort contract:

```kotlin
fun orderManagementApps(
    apps: Collection<OrderedApp>,
    selectedPackages: Collection<String>,
    savedOrder: Collection<String>
): List<OrderedApp> {
    val selected = selectedPackages.toSet()
    val selectedApps = orderApps(apps.filter { it.packageName in selected }, savedOrder)
    val unselectedApps = orderApps(apps.filterNot { it.packageName in selected }, emptyList())
    return selectedApps + unselectedApps
}

fun moveSelectedPackage(
    currentOrder: Collection<String>,
    packageName: String,
    offset: Int
): List<String>? {
    val normalizedOrder = normalizeSavedOrder(currentOrder)
    if (packageName.isBlank() || offset !in setOf(-1, 1)) return null
    val from = normalizedOrder.indexOf(packageName)
    val to = from + offset
    if (from < 0 || to !in normalizedOrder.indices) return null
    return normalizedOrder.toMutableList().apply { java.util.Collections.swap(this, from, to) }
}
```

The nullable result is the write gate: invalid or boundary actions cannot accidentally normalize or truncate persisted order. The caller supplies the selected package order currently displayed by the management list, so selected apps omitted from stale preferences are retained when a valid move is made.

- [ ] **Step 5: Run Task 1 tests GREEN and commit**

Run the Step 3 command, then:

```bash
git add app/src/main/java/com/yinxing/launcher/data/home/HomeAppOrderPolicy.kt \
  app/src/test/java/com/yinxing/launcher/data/home/HomeAppOrderPolicyTest.kt
git commit -m "feat: order caregiver home applications"
```

---

### Task 2: Selected-first management rows with explicit arrows

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/data/home/LauncherAppRepository.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/feature/appmanage/AppListAdapter.kt`
- Modify: `app/src/main/res/layout/item_app.xml`
- Modify: `app/src/main/res/values/strings.xml`
- Create: `app/src/test/java/com/yinxing/launcher/feature/appmanage/AppListAdapterTest.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/data/home/LauncherAppRepositoryTest.kt`

**Interfaces:**
- Consumes: the two Task 1 `HomeAppOrderPolicy` functions.
- Produces: required adapter callbacks `onMoveUp: (AppInfo) -> Unit` and `onMoveDown: (AppInfo) -> Unit`.
- Produces row IDs: `btn_app_move_up` and `btn_app_move_down`.

- [ ] **Step 1: Write failing repository order tests**

Use app names whose alphabetical order differs from saved order:

```kotlin
preferences.setPackageSelected("pkg.zebra", true)
preferences.setPackageSelected("pkg.alpha", true)
preferences.saveAppOrder(listOf("pkg.zebra", "pkg.alpha"))
val apps = repository.getInstalledApps(preferences)
assertEquals(
    listOf("pkg.zebra", "pkg.alpha", "pkg.beta"),
    apps.map(AppInfo::packageName)
)
```

Expected before implementation: alphabetical installed order.

- [ ] **Step 2: Write failing adapter accessibility/boundary tests**

Create a Robolectric adapter with three selected rows and one unselected row. Bind all four and assert:

```kotlin
assertEquals(View.VISIBLE, firstUp.visibility)
assertFalse(firstUp.isEnabled)
assertTrue(firstDown.isEnabled)
assertEquals("下移 相机", firstDown.contentDescription.toString())
assertEquals(View.GONE, unselectedUp.visibility)
assertEquals(View.GONE, unselectedDown.visibility)
```

Click enabled up/down buttons and assert exactly the corresponding `AppInfo` reaches the callback. Click the disabled first-up/last-down buttons and assert no callback.

- [ ] **Step 3: Run Task 2 tests and confirm RED**

Run:

```bash
GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home bash gradlew \
  :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.data.home.LauncherAppRepositoryTest' \
  --tests 'com.yinxing.launcher.feature.appmanage.AppListAdapterTest' \
  --no-daemon --console=plain
```

Expected: missing arrow IDs/callbacks and repository order mismatch.

- [ ] **Step 4: Order repository results through the Task 1 policy**

Map by package after ordering records:

```kotlin
val selectedPackages = preferences.getSelectedPackages()
val orderedRecords = HomeAppOrderPolicy.orderManagementApps(
    apps = loadInstalledApps().map { OrderedApp(it.packageName, it.appName) },
    selectedPackages = selectedPackages,
    savedOrder = preferences.getAppOrder()
)
return@withContext orderedRecords.map { app ->
    AppInfo(app.packageName, app.appName, app.packageName in selectedPackages)
}
```

- [ ] **Step 5: Add stable arrow controls and bind their state**

Add two 48dp `ImageButton`s using platform up/down arrow drawables between app name and checkbox. In `AppListAdapter.bind`, derive `selectedCount` and the holder's current position from `currentList`, then set `VISIBLE` only for selected rows and enable exact bounds:

```kotlin
val position = holder.bindingAdapterPosition
val selectedCount = currentList.count { it.isSelected }
holder.moveUp.isVisible = appInfo.isSelected
holder.moveDown.isVisible = appInfo.isSelected
holder.moveUp.isEnabled = appInfo.isSelected && position > 0
holder.moveDown.isEnabled = appInfo.isSelected && position in 0 until selectedCount - 1
holder.moveUp.contentDescription = context.getString(R.string.app_move_up_description, appInfo.appName)
holder.moveDown.contentDescription = context.getString(R.string.app_move_down_description, appInfo.appName)
holder.moveUp.setOnClickListener { if (holder.moveUp.isEnabled) onMoveUp(appInfo) }
holder.moveDown.setOnClickListener { if (holder.moveDown.isEnabled) onMoveDown(appInfo) }
```

Clear both listeners in `onViewRecycled`. Add exact strings `上移 %1$s` and `下移 %1$s`.

- [ ] **Step 6: Run Task 2 tests GREEN and commit**

Run the Step 3 command, then:

```bash
git add app/src/main/java/com/yinxing/launcher/data/home/LauncherAppRepository.kt \
  app/src/main/java/com/yinxing/launcher/feature/appmanage/AppListAdapter.kt \
  app/src/main/res/layout/item_app.xml app/src/main/res/values/strings.xml \
  app/src/test/java/com/yinxing/launcher/data/home/LauncherAppRepositoryTest.kt \
  app/src/test/java/com/yinxing/launcher/feature/appmanage/AppListAdapterTest.kt
git commit -m "feat: arrange home apps in caregiver settings"
```

---

### Task 3: Persist caregiver moves and refresh selection groups

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/feature/appmanage/AppManageActivity.kt`
- Modify: `app/src/main/res/values/strings.xml`
- Create: `app/src/test/java/com/yinxing/launcher/feature/appmanage/AppManageActivitySmokeTest.kt`

**Interfaces:**
- Consumes: Task 1 `moveSelectedPackage` and Task 2 adapter callbacks/row IDs.
- Produces: one activity path that persists both application selection and order.

- [ ] **Step 1: Write a failing activity move test**

Register three fake launcher applications with Robolectric, select two, save reverse-alphabetical order, reset the repository singleton, launch `AppManageActivity`, and wait for rows. Click the first selected row's down button, then assert:

```kotlin
assertEquals(listOf("pkg.alpha", "pkg.zebra"), preferences.getAppOrder())
assertEquals(
    listOf("pkg.alpha", "pkg.zebra"),
    adapter.currentList.filter(AppInfo::isSelected).map(AppInfo::packageName)
)
```

Add a rapid-action case with three selected rows: invoke the first row's down action twice before allowing the repository refresh to complete, then require the persisted order to be `[second, third, first]`. This proves the second action is based on the first persisted move rather than a stale adapter snapshot.

- [ ] **Step 2: Write a failing selection-regroup test**

Click an unselected application's row. Assert it becomes selected, appears at the end of the selected group, and the persisted order includes it once. Click again and assert it returns to the unselected group and disappears from order.

- [ ] **Step 3: Run the activity smoke tests and confirm RED**

Run:

```bash
GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home bash gradlew \
  :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.feature.appmanage.AppManageActivitySmokeTest' \
  --no-daemon --console=plain
```

Expected: adapter has no activity move callbacks and selection remains in its previous list position.

- [ ] **Step 4: Persist selection and move callbacks through one reload path**

Construct the adapter with:

```kotlin
onCheckChanged = { appInfo, checked -> saveAppSelection(appInfo.packageName, checked) },
onMoveUp = { appInfo -> moveSelectedApp(appInfo.packageName, -1) },
onMoveDown = { appInfo -> moveSelectedApp(appInfo.packageName, 1) }
```

Implement movement without redundant writes:

```kotlin
private var currentSelectedOrder: List<String> = emptyList()

private fun moveSelectedApp(packageName: String, offset: Int) {
    val movedOrder = HomeAppOrderPolicy.moveSelectedPackage(
        currentOrder = currentSelectedOrder,
        packageName = packageName,
        offset = offset
    ) ?: return
    currentSelectedOrder = movedOrder
    launcherPreferences.saveAppOrder(movedOrder)
    appRepository.invalidateSelections()
    loadInstalledApps()
}
```

Set `currentSelectedOrder` from every successfully loaded management list before submitting it to the adapter. Update it synchronously to `movedOrder` before saving and starting the refresh, so a second arrow tap cannot use stale RecyclerView state. Change `saveAppSelection` to copy the synchronous preference order into this field, invalidate selections, and reload instead of only patching the old alphabetical adapter list. Cancellation of the previous load remains the single stale-result guard.

- [ ] **Step 5: Update exact caregiver copy**

Use `首页应用` for the page title and a result-oriented subtitle: `已选应用排在前面，顺序与首页一致`. Replace the settings drag tip with `在「首页应用」里，用上下箭头调整显示顺序。`

- [ ] **Step 6: Run Task 3 and related preference tests GREEN, then commit**

Run:

```bash
GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home bash gradlew \
  :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.feature.appmanage.*' \
  --tests 'com.yinxing.launcher.data.home.*' \
  --no-daemon --console=plain
```

Then:

```bash
git add app/src/main/java/com/yinxing/launcher/feature/appmanage/AppManageActivity.kt \
  app/src/main/res/values/strings.xml \
  app/src/test/java/com/yinxing/launcher/feature/appmanage/AppManageActivitySmokeTest.kt
git commit -m "feat: persist caregiver home arrangement"
```

---

### Task 4: Remove Home configuration and drag state

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/data/home/LauncherAppRepository.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/feature/home/HomeAppItem.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/feature/home/HomeNavigator.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/feature/home/HomeAppAdapter.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/feature/home/MainActivity.kt`
- Delete: `app/src/main/java/com/yinxing/launcher/feature/home/ItemMoveCallback.kt`
- Modify: `app/src/main/res/values/strings.xml`
- Modify: `app/src/test/java/com/yinxing/launcher/data/home/LauncherAppRepositoryTest.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/feature/home/HomeAppAdapterTest.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/feature/home/HomeViewModelTest.kt`
- Modify: `app/src/test/java/com/yinxing/launcher/feature/home/MainActivitySmokeTest.kt`
- Modify: `app/src/androidTest/java/com/yinxing/launcher/feature/home/MainActivityInstrumentedTest.kt`

**Interfaces:**
- Removes: `HomeAppItem.Type.ADD`, Home `onOrderChanged`, `setTouchHelper`, and all `ItemTouchHelperAdapter` drag methods.
- Preserves: Home click navigation, icon loading, differ submission, adaptive card sizing, and app launch gate.

- [ ] **Step 1: Write failing Home stability tests**

Update repository/MainActivity expectations from three built-ins to two and add exact assertions:

```kotlin
assertEquals(
    listOf(HomeAppItem.Type.PHONE, HomeAppItem.Type.WECHAT_VIDEO),
    repository.getStaticHomeItems().map(HomeAppItem::type)
)
assertTrue(homeItems.none { it.packageName == "add" })
```

Bind a third-party Home card and assert `performLongClick()` is false and `onOrderChanged` is not available as a Home interaction.

- [ ] **Step 2: Run Home-focused tests and confirm RED**

Run:

```bash
GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home bash gradlew \
  :app:testDebugUnitTest \
  --tests 'com.yinxing.launcher.data.home.LauncherAppRepositoryTest' \
  --tests 'com.yinxing.launcher.feature.home.HomeAppAdapterTest' \
  --tests 'com.yinxing.launcher.feature.home.HomeViewModelTest' \
  --tests 'com.yinxing.launcher.feature.home.MainActivitySmokeTest' \
  --no-daemon --console=plain
```

Expected: existing repository still appends `ADD`, MainActivity counts include it, and the application icon consumes long press.

- [ ] **Step 3: Remove the `ADD` model/navigation/repository path**

Delete `HomeAppItem.Type.ADD`, `addSecondaryBuiltInItems`, its calls, the `HomeNavigator` branch/import, and the unused `home_item_add` string. Keep fixed phone/video insertion unchanged.

- [ ] **Step 4: Simplify Home adapter and Activity wiring**

Remove `ItemTouchHelperAdapter`, `ItemTouchHelper`, `onOrderChanged`, `touchHelper`, drag snapshots, pending submissions, drag listeners, and drag methods. Submission becomes the existing direct differ call:

```kotlin
fun submitList(items: List<HomeAppItem>, commitCallback: (() -> Unit)? = null) {
    differ.submitList(items) { commitCallback?.invoke() }
}
```

Delete `ItemMoveCallback.kt`. In `MainActivity`, remove the callback field, helper attachment, order callback, and drag-animation update. Keep `itemAnimator = null`.

- [ ] **Step 5: Adjust existing tests without weakening coverage**

Use `PHONE` or `WECHAT_VIDEO` in `HomeViewModelTest` when proving non-application items are excluded. Remove drag-concurrency tests that exercise deleted behavior, retain icon lifecycle/size tests, and add the long-press no-op assertion. Update all exact Home item counts by one.

- [ ] **Step 6: Run Home and management regression tests GREEN and commit**

Run the Step 2 command plus Task 3 tests, then:

```bash
git add app/src/main app/src/test app/src/androidTest
git commit -m "feat: keep elderly home layout stable"
```

---

### Task 5: Release evidence and Preview 22 publication

**Files:**
- Modify: `app/build.gradle.kts`
- Create: `docs/release/yinxing-root-preview-22.md`
- Modify: `docs/superpowers/plans/2026-08-11-elderly-stable-home-preview-22.md`

**Interfaces:**
- Produces: versionCode `38`, versionName `1.10.0-root-preview.22`, one Debug APK, and `SHA256SUMS.txt`.
- Reuses: unchanged Preview 18 KernelSU module link; no new module ZIP.

- [ ] **Step 1: Bump version metadata**

Set:

```kotlin
versionCode = 38
versionName = "1.10.0-root-preview.22"
```

- [ ] **Step 2: Run forced Android verification in isolation**

Run:

```bash
/usr/bin/time -f 'ELAPSED_SECONDS=%e EXIT_STATUS=%x' \
  env GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home \
  bash gradlew :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest \
  --rerun-tasks --no-daemon --console=plain
```

Require exit 0, all unit XML suites with zero failures/errors/skips, and both APKs present.

- [ ] **Step 3: Run lint and proportional Root proof**

Run `:app:lintDebug`, classify existing `RootCommandRunner.kt:72/:150` findings, and prove no Root surface changed:

```bash
if git diff --name-only v1.10.0-root-preview.21..HEAD \
  | rg -q '^(root/|tools/test-yinxing-guard.sh)'; then
  exit 1
fi
```

Do not rerun the four-minute BusyBox matrix when the exact Root surface is unchanged.

- [ ] **Step 4: Obtain independent code review**

Review the complete Preview 21-to-Preview 22 range for accidental loss of selection/order, adapter recycling, accessibility, Home navigation, and test weakness. Resolve all Critical/Important findings and rerun affected tests.

- [ ] **Step 5: Record and commit release evidence**

Document exact test count/time, lint classification, independent review, APK metadata/signature/hash, unchanged Root boundary, no-device gap, install checks, and Preview 21 rollback. Commit:

```bash
git add app/build.gradle.kts docs/release/yinxing-root-preview-22.md \
  docs/superpowers/plans/2026-08-11-elderly-stable-home-preview-22.md
git commit -m "docs: record stable elderly home preview 22"
```

- [ ] **Step 6: Package, publish, and verify remote bytes**

Copy the final APK to `out/release/yinxing-1.10.0-root-preview.22-debug.apk`, generate `SHA256SUMS.txt`, fast-forward `main`, push the feature branch/main/annotated tag, and create prerelease `v1.10.0-root-preview.22`. Download into a fresh `mktemp -d` directory and require checksum, `cmp`, `aapt2`, `apksigner`, asset list, release body, and remote ref equality before reporting publication.
