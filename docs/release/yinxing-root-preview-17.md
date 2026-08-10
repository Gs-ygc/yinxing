# 银杏 Root 增强 Preview 17

Preview 17 面向一加 15 中国版 ColorOS 16、KernelSU、已 Root 专机。它修复
HOME 恢复的一条假成功路径：`am start` 返回成功不再意味着银杏桌面一定已经显示。

## 发布内容

- `yinxing-1.10.0-root-preview.17-debug.apk`：银杏 Debug APK，`versionCode=33`。
- `yinxing-guard-1.10.0-root-preview.17.zip`：KernelSU Root Guard 模块，
  `versionCode=17`。
- `SHA256SUMS.txt`：两个二进制资产的 SHA-256 校验值。

## Preview 17 变化

Root Guard 固定拉起 HOME 后，只解析 `dumpsys activity activities` 中明确的
`mResumedActivity` 和 `mFocusedActivity` 记录，并且只接受固定的银杏
`MainActivity`。只有这个后置条件成功，才写入当前开机周期的前台确认记录。

Root 健康协议升级为 schema 3：

- `桌面` 表示 HOME 角色和 resolver 是否仍由银杏拥有。
- `前台确认` 表示本次开机中最近一次 Root 拉起桌面的结果：`正常` 为已确认，
  `待处理` 为尚未确认，`未知` 为没有安全的当前开机证据。

`前台确认` 有意不是实时前台探针。打开设置、微信或其他正常应用，不会把已确认
的桌面拉起误报为失败。已知的其他前台最多允许 Guard 在同一进程稍后重试一次；
每个 Guard 进程最多两次固定 HOME 拉起。诊断未知、畸形、失败或超时会停止本轮
后续拉起并保持降级。手动修复同样只有在前台确认后才记录成功。

完整的 HOME 拉起、前台探测和证据发布过程持有 HOME 事务锁；卸载、Kiosk 拉起、
Guard 重试和手动修复不能在 `unverified` 与 `verified` 之间交错，避免旧启动结果
覆盖新失败结果，或卸载后重新生成 marker。

确认 marker 使用临时文件、0600 权限、读回校验和同步；过期 boot id、额外内容、
目录和 symlink 均 fail-closed。卸载会清理该诊断 marker，但不会仅因它改变 HOME。

APK 的 Root 白名单仍只有固定的 `status.sh`、`action.sh`、`kiosk-home.sh` 三个
无参数路径。没有加入任意 Shell、坐标点击、任意包名或组件、进程杀除、私有
ColorOS API。Kiosk 拉起上限为 15 秒，显式修复上限为 20 秒。

## 安装顺序

1. 覆盖安装 `yinxing-1.10.0-root-preview.17-debug.apk`。
2. 在 KernelSU 安装并启用 `yinxing-guard-1.10.0-root-preview.17.zip`；若系统要求
   重启，先重启让模块生效。
3. 在银杏设置执行一次 Root 修复，确认 `桌面` 和 `前台确认` 都显示 `正常`。
4. 按 Home 键、进入一次自动化流程，再重启一次后复查，才交给无人值守使用。

模块启用期间会持续恢复银杏的 HOME 路由，这是专机高可靠模式的预期行为。该 APK
是 Debug 包，不是生产签名发布物。

## 回滚

1. 在 KernelSU 禁用或卸载模块。
2. 按 KernelSU 提示重启，让延迟清理脚本恢复接管前的桌面、Doze 和无障碍事务状态。
3. 确认 Home 键回到目标桌面后，再安装旧模块。
4. APK 可用旧版 Debug 包覆盖；若系统拒绝低版本覆盖，按设备允许的降级安装方式处理。

Preview 16 Release：<https://github.com/Gs-ygc/yinxing/releases/tag/v1.10.0-root-preview.16>

## 本地验证记录

- 所有 KernelSU Shell 脚本通过 `sh -n`；`bash tools/test-yinxing-guard.sh all`
  退出码为 0，含 host 和递归 BusyBox harness，共 414 个 PASS、0 个 FAIL，耗时
  226.11 秒。
- `:app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon` 构建成功，
  48 个任务重新执行，耗时 96.73 秒。43 个 JUnit XML 合计 354 tests、0 failures、
  0 errors、0 skipped。
- `aapt2` 确认 APK 为 `com.yinxing.launcher`、`versionCode=33`、
  `versionName=1.10.0-root-preview.17`、`minSdk=24`、`targetSdk=36`；`apksigner`
  确认单一 Android Debug 签名和 v2 签名有效。
- `unzip -t` 验证模块 ZIP 无错误；独立重新打包与发布 ZIP 逐字节一致，ZIP 内
  `common.sh` 和 `uninstall-cleanup.sh` 与源码完全一致。
- 并发回归确认暂停中的 HOME 拉起会阻塞卸载；事务失败时延迟清理仍会删除前台
  证据而保留可重试的 HOME、Doze 或无障碍回滚 marker。
- 当前环境没有连接真实一加 15；不会把本地 fixture 或 AOSP 行为表述为 ColorOS 16
  真机验证。发布后会从 GitHub Release 新目录下载资产，再作一次校验和复核。

## SHA-256

```text
c2a505a42ae569fde009fcd762390c4077bde1c9d10c145f018a9bb46d83fb28  yinxing-1.10.0-root-preview.17-debug.apk
ca47388d808fa2b7d4559121ea542787e1bd42b10816a81737e0a653d8a42428  yinxing-guard-1.10.0-root-preview.17.zip
fda4df6182a2dbd3f7bc0139573bcfcceca28a9638b00088eb2e16d0d6d3083f  SHA256SUMS.txt
```
