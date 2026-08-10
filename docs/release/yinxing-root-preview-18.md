# 银杏老年体验 Preview 18

Preview 18 面向一加 15、中国版 ColorOS 16、KernelSU、已 Root 专机。本版把
老年用户每天会走的主路径放在第一位：从首页进入常用联系人后，整张电话联系人
卡片都能直接拨号；权限或系统拨号失败时，也不会把用户留在一条消失很快的提示里。

## 发布内容

- `yinxing-1.10.0-root-preview.18-debug.apk`：银杏 Debug APK，`versionCode=34`。
- `yinxing-guard-1.10.0-root-preview.18.zip`：KernelSU Root Guard 模块，
  `versionCode=18`。
- `SHA256SUMS.txt`：两个二进制资产的 SHA-256 校验值。

## 老年主路径变化

- 电话联系人默认整卡可点，保留 76dp 绿色拨打按钮；首页入口不再显示家属管理
  操作，新增、修改和删除仍集中在设置里的联系人管理页。
- 拨号页关闭自定义入场动画和 RecyclerView 插入动画，联系人出现后立即可操作，
  同时降低无意义动画和刷新功耗。
- 1.2 秒全局拨号闸门会吞掉连续误触，包括快速点到另一个联系人；权限请求中的
  重复点击也不会发出第二个请求或电话 Intent。
- 没有 `CALL_PHONE` 权限或系统拒绝直接拨号时，显示大字、大按钮的持续对话框；
  用户可一键打开已填好号码的系统拨号盘，不需要重新记忆或输入号码。
- 权限请求期间旋转或重建 Activity 会保留待拨联系人，避免授权回来后丢失操作。
- 电话和视频的“整卡点击”已拆成两个家属设置：电话新安装默认开启，视频默认只
  允许点击明确的蓝色按钮以减少误触。升级时会保留旧版已经明确选择的状态。
- 电话和视频卡片在 TalkBack 下都只暴露一个动作目标；设置弹层可滚动，开关和
  加减按钮有明确读屏名称，短屏、横屏和大字体不会截断底部操作。
- 首页电话图标改为熟悉的听筒，微信视频改为摄像机，减少图标含义混淆。

## 自启动与接管

- 家属在 ColorOS 设置中确认过“允许自启动”后，开机或覆盖安装会实际尝试恢复
  银杏首页；默认桌面和防退出模式仍作为另外两条恢复信号。
- ColorOS 拒绝后台拉起时会记录诊断而不让广播接收器崩溃；默认桌面查询异常时
  保持 fail-closed，不猜测接管状态。

## Root Guard 底层补强

Preview 18 没有新增 BusyBox 功能或任意 Root 命令面。它只修正既有固定流程的两条
证据边界：无法取得可信 boot identity 时不再复用 HOME 前台证据；HOME 前台
`dumpsys` 输出在进入 Shell 变量前就有 64 KiB 上限。卸载清理与运行时使用相同的
boot identity 来源顺序和超时清理方式，仍只允许固定的 `status.sh`、`action.sh`、
`kiosk-home.sh` 三个无参数 Root 入口。

## 安装顺序

1. 覆盖安装 `yinxing-1.10.0-root-preview.18-debug.apk`。
2. 在 KernelSU 安装并启用 `yinxing-guard-1.10.0-root-preview.18.zip`；按 KernelSU
   提示重启。
3. 打开银杏设置，检查默认桌面、自启动、后台弹出和 Root 增强状态；执行一次
   Root 修复并复查。
4. 从首页点一个常用电话联系人，分别体验直接拨号和关闭电话权限后的拨号盘回退。
5. 重启设备后确认自动回到银杏，再交给老人长期使用。

模块启用期间会持续恢复银杏 HOME、保活和无障碍服务，这是受控专机的预期行为。
该 APK 使用 Android Debug 签名，不是生产签名发布物。

## 回滚

1. 在 KernelSU 禁用或卸载 Preview 18 模块。
2. 按 KernelSU 提示重启，让延迟清理恢复接管前的桌面、Doze 和无障碍事务状态。
3. 确认 Home 键回到目标桌面后，再安装旧模块。
4. APK 可覆盖安装旧版；若系统拒绝降级，需要先按专机维护流程备份配置再卸载。

Preview 17 Release：<https://github.com/Gs-ygc/yinxing/releases/tag/v1.10.0-root-preview.17>

## 本地验证记录

- `bash tools/test-yinxing-guard.sh all` 的 host 与 standalone BusyBox 两轮共 434 个
  PASS、0 个 FAIL，耗时 249.69 秒；所有模块脚本通过 `sh -n`、`bash -n` 和
  BusyBox `ash -n`。
- `:app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest
  --rerun-tasks --no-daemon` 构建成功，80 个任务全部执行，耗时 106.57 秒；
  46 个 JUnit XML 合计 374 tests、0 failures、0 errors、0 skipped。
- 独立代码审查未发现 Critical 或 Important 问题；迁移、列表动画、设置弹层溢出
  和 TalkBack 标签问题均在发布前修复。
- `aapt2` 确认包名 `com.yinxing.launcher`、`versionCode=34`、
  `versionName=1.10.0-root-preview.18`、`minSdk=24`、`targetSdk=36`；
  `apksigner` 确认单一 Android Debug 签名和 v2 签名有效。
- 模块 ZIP 有 11 个预期条目、统一 1980 时间戳和正确可执行权限；独立二次打包与
  发布候选逐字节一致，`unzip -t` 和 `sha256sum -c` 通过。
- `lintDebug` 仍被两处发布前已存在的 `RootCommandRunner.kt` API 24/26 错误阻断；
  本版改动没有新增 lint error。该问题不在本次老年主路径范围内，已保留为后续债务。
- 当前没有连接真实一加 15，因此不会把本地 Robolectric/AOSP 结果表述为 ColorOS
  16 真机验证。开机拉起、TalkBack、大字体滚动、直接拨号和耗电仍需本次设备验收。

## SHA-256

```text
a11751a24be210b800dc648055e80b7c5dfcf95ef3cfd49d03f92abbc6449bb3  yinxing-1.10.0-root-preview.18-debug.apk
a734d486b7f87bb771e95cc74f4b8895254de2a32a5ef4b2201e70c35958997a  yinxing-guard-1.10.0-root-preview.18.zip
d436fd8aac614337555f1e49edc60dcfbf1dfaa0f531dba8bdbf621953b13862  SHA256SUMS.txt
```
