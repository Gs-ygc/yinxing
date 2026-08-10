# 老年首页即时应用网格 Preview 20 Implementation Plan

**Goal:** 恢复首页应用网格的按视口回收与跨屏拖动能力，同时移除首屏卡片入场延时，并让应用卡片在系统大字体下自适应高度而不裁剪名称。

**Architecture:** `ConcatAdapter` 将一个全跨列 `HomeHeaderAdapter` 与现有两列 `HomeAppAdapter` 组成唯一的 `RecyclerView`。header 承载时间、天气、状态和常用电话；`GridLayoutManager.SpanSizeLookup` 让 header 占两列，应用项占一列。`ItemMoveCallback` 只接受属于 `HomeAppAdapter` 的 ViewHolder，保留应用内部相对排序。卡片从固定高度改为 `wrap_content` 加最小高度，适配器只维护与图标缩放相关的最小尺寸，不再启动绑定动画。

## Constraints

- 目标仍为 OnePlus 15、中国版 ColorOS 16、KernelSU 已 Root 的固定专机。
- 本版不修改 Root、BusyBox、开机、自启动、拨号或后台服务。
- 不隐藏、缩短或强制单行显示老人需要读取的应用名称。
- 使用 `GRADLE_USER_HOME=/nfs/home/leguochun/yinxing/.gradle-user-home`、`JAVA_HOME=/tmp/yinxing-jdk21-review`。

## Tasks

### 1. Add red regression coverage

- Extend `MainActivitySmokeTest` to assert a direct `match_parent` RecyclerView, a `ConcatAdapter`, full-span header and one-span app items instead of a wrapping inner RecyclerView.
- Add `ItemMoveCallback` coverage proving a header holder cannot enter the app adapter's drag transaction.
- Add a resource contract assertion for `item_home_app.xml`: root/content are `wrap_content`, minimum height is present, and name allows two lines.
- Run the focused tests and confirm the current animation/fixed-height implementation fails at least one assertion.

### 2. Implement the smallest UI change

- Replace the outer scroll layout with one RecyclerView, create `item_home_header.xml` and `HomeHeaderAdapter`, and route existing weather/status/trusted-contact rendering into that header.
- Compose the header and app adapters with `ConcatAdapter`; assign header two spans and app items one span.
- Guard `ItemMoveCallback` so drops into the header never change application order.
- Change `item_home_app.xml` root and inner container to `wrap_content`, with a 200dp minimum baseline.
- Change `HomeAppAdapter.applyUi` to update `minimumHeight` and icon dimensions without forcing `layoutParams.height`.
- Replace `animateIn` with a deterministic reset to `alpha=1f` and `translationY=0f`; do not add a replacement animation.

### 3. Verify and review

- Run focused home tests, then the full `:app:testDebugUnitTest` and forced Debug APK/androidTest build.
- Run `git diff --check`, lint and classify only pre-existing Root errors, and run the unchanged Root guard matrix.
- Request an independent read-only review of the exact final tree before publishing.

### 4. Publish Preview 20

- Bump APK version to `1.10.0-root-preview.20` without changing the unchanged KernelSU module version.
- Package APK and SHA-256 notes, push source/main/tag, create a GitHub prerelease, and re-download assets for byte/checksum/metadata/signature verification.
- Update the persistent Goal to the next device acceptance phase.
