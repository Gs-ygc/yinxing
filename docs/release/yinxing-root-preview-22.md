# 银杏老年体验 Preview 22

Preview 22 把重点放回老人每天真正会碰到的首页主路径：更稳定的固定布局、更少的
误触入口，以及由家属统一整理的应用顺序。目标设备仍是一加 15 中国版 ColorOS 16、
KernelSU、已 Root 的受控专机。本版没有折腾 BusyBox，也没有改变 Root 模块。

## 发布内容

- `yinxing-1.10.0-root-preview.22-debug.apk`：银杏 Debug APK，`versionCode=38`，
  `versionName=1.10.0-root-preview.22`。
- `SHA256SUMS.txt`：本版 APK 的 SHA-256 校验值。
- KernelSU Root Guard：本版没有修改模块源码、脚本或元数据，继续使用
  [Preview 18 模块](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.18/yinxing-guard-1.10.0-root-preview.18.zip)。

## 老年主路径变化

- 首页只保留固定的“电话”“微信视频”和家属选择的第三方应用；移除了容易误触、
  位置不稳定的“添加”卡片。家属从首页顶部的“家属设置”进入维护入口。
- “家属设置 → 首页应用”现在是唯一的应用选择与排序入口。已选应用始终排在列表前面，
  并按保存顺序展示；未选应用按名称排序，便于家属快速扫描。
- 已选行提供明确的 48dp 上移/下移按钮，按钮带应用名的中文无障碍描述；第一项不能上移，
  最后一项不能下移，未选行不显示排序按钮。
- 每次有效移动都会立即保存、刷新管理列表，并同步首页顺序。连续快速点击使用最新顺序，
  不会因后台刷新延迟而丢掉上一次操作。
- 首页应用卡片不再支持长按拖拽。首页回到直接列表差分更新，减少拖拽状态、动画和误触
  对首屏点击的干扰；点击第三方应用、电话和微信视频的既有交接逻辑保持不变。
- 宏基准测试已改走“家属设置 → 首页应用”，不会再点击已移除的旧入口。

## 自启动、低功耗与 Root 边界

- 本版没有新增服务、定时器、轮询、网络请求、后台唤醒、Root 命令或无障碍命令；首页
  管理只使用已有的本地偏好和生命周期刷新。
- 本版没有修改 KernelSU 模块、BusyBox、HOME 接管、开机恢复、Doze 白名单或无障碍恢复。
  Root Guard 仍由 Preview 18 模块承担。
- 因 Root surface 与 Preview 21 相同，按比例只做文件边界核对，没有重复约四分钟的
  BusyBox host/standalone 矩阵；这不能替代 ColorOS 16 真机验收。

## 安装与体验顺序

1. 下载并覆盖安装本 Release 的 APK。APK 使用 Android Debug 签名，只适用于相同调试签名
   的体验安装。
2. 保持 Preview 18 KernelSU 模块启用；本版不需要重装或升级模块。
3. 进入“家属设置 → 首页应用”，勾选两三个应用，确认已选项置顶；用上下箭头调整顺序，
   回到首页确认卡片顺序一致。
4. 快速连续点击同一个第三方应用，确认不会出现多个重复任务；再分别点击电话、微信视频
   和一个第三方应用，确认各自入口仍能打开。
5. 重启专机后检查银杏 HOME、自启动、Root Guard 状态和无障碍恢复，并记录从开机到首页
   首次可操作的时间；观察一晚待机耗电。
6. 在 ColorOS 的电池/自启动管理中确认银杏保持允许后台运行；若系统杀后台或权限状态
   异常，请把现象、时间点和 `设置 → Root 健康` 页面状态一并反馈。

## 回滚

1. 安装 [Preview 21 APK](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.21/yinxing-1.10.0-root-preview.21-debug.apk)。
2. KernelSU 模块保持 Preview 18，或按专机维护流程禁用并重启后再回退模块。
3. 若系统拒绝覆盖安装，按专机维护流程备份配置后卸载体验 APK，再安装旧 APK。

## 本地验证记录

- `:app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest --rerun-tasks
  --no-daemon --console=plain`：80/80 任务执行成功，耗时 94.75 秒；55 份 JUnit XML 共
  433 tests、0 failures、0 errors、0 skipped，主 APK 与 androidTest APK 均生成。
- `:benchmark:compileBenchmarkReleaseKotlin`：`BUILD SUCCESSFUL`，宏基准源码与新入口路径
  编译通过。
- `:app:lintDebug`：退出码 1，2 个既有 `RootCommandRunner.kt:72`、`:150` API 26
  `NewApi` errors，135 条既有 warning；本版新增的动态箭头无障碍描述已显式声明，没有新增
  lint error。
- 独立差异复核覆盖 Preview 21 → Preview 22 的排序、回收、无障碍、Home 导航和测试边界；
  未发现 Critical/Important 问题。Task 2 早期的选择后分组问题已由 Task 3 的同步镜像、
  重载和 2 个 Activity smoke tests 覆盖。
- Root 边界核对：`git diff --name-only v1.10.0-root-preview.21..HEAD` 没有命中
  `root/` 或 `tools/test-yinxing-guard.sh`；Root/BusyBox 源码未变。
- `aapt2 dump badging`：包名 `com.yinxing.launcher`、`versionCode=38`、
  `versionName=1.10.0-root-preview.22`、`minSdk=24`、`targetSdk=36`。
- `apksigner verify --verbose --print-certs`：单一 Android Debug signer，APK Signature
  Scheme v2 为 `true`；证书 SHA-256 为
  `68168b637a07c0b77befbdce9f589f149a00869b50d893d111eaef73f7957175`。
- 当前环境的 `adb devices` 没有列出设备，因此没有宣称一加 15/ColorOS 16 的真实首页
  延时、自启动、Root 保活、无障碍恢复、应用接管或功耗结果。

## SHA-256

```text
aab197f9146d87b665ea8d7fec3944daf6dffb4a293c434f65075c0663dd0143  yinxing-1.10.0-root-preview.22-debug.apk
```
