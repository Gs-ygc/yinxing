# 银杏 Root 增强 Preview 9

Preview 9 面向一加 15 中国版 ColorOS 16、KernelSU、已 Root 专机，增加了受控的 Root 桌面回退。目标是 Kiosk 模式下 Android 普通前台拉回被 ColorOS 拒绝或延迟时，仍能用固定 Root 命令恢复银杏桌面。

## 发布内容

- `yinxing-1.10.0-root-preview.9-debug.apk`：银杏体验 APK，`versionCode=25`。
- `yinxing-guard-1.10.0-root-preview.9.zip`：KernelSU Root Guard 模块，`versionCode=9`。
- `SHA256SUMS.txt`：两个资产的 SHA-256 校验值。

## Preview 9 变化

- 新增固定模块入口 `/data/adb/modules/yinxing_guard/bin/kiosk-home.sh`。它只调用现有固定的 `am start --user 0 -n com.yinxing.launcher/.feature.home.MainActivity`，并拒绝模块缺失、`disable` 或 `remove` 状态。
- Kiosk 恢复链在普通 `startActivity`、Android 14+ `PendingIntent` 和 settle retry 之后，才考虑 Root 回退；每个恢复代际最多执行一次，Root 调用可取消且有 1.2 秒超时。
- 只有 Kiosk 已开启、没有正在运行的微信自动化会话、当前/最新窗口仍是已识别的系统桌面时才会触发 Root 回退。SystemUI、输入法、权限窗口不会误取消原有桌面恢复；更新的用户应用窗口会取消陈旧回退。
- Root 不可用、模块未安装、命令失败、超时或输出超限时，保留原有 Android 恢复路径，不改变普通模式行为。

## 安装顺序

1. 在 KernelSU 中先安装并启用 `yinxing-guard-1.10.0-root-preview.9.zip`。如果 KernelSU 要求重启，先重启让模块生效。
2. 再安装 `yinxing-1.10.0-root-preview.9-debug.apk`，覆盖 Preview 8 时使用升级安装。
3. 打开银杏设置并启用 Kiosk 模式；Root 回退只在 Kiosk 条件满足时工作。
4. 首次体验建议保留 Preview 8 APK 和模块 ZIP，出现问题时按下面的回滚步骤恢复。

这是 Debug APK，安装时可能受到设备现有签名策略限制；不要把它当作生产 Release 包分发。

## 回滚

先在 KernelSU 中停用或卸载 Preview 9 模块，再安装 Preview 8 模块并按 KernelSU 提示重启。APK 可用 Preview 8 Debug 包覆盖安装；若系统拒绝低版本覆盖，使用设备允许的降级安装方式或先卸载当前 APK，再安装 Preview 8。

## 验证记录

- 环境：Gradle 9.3.1、OpenJDK 21.0.11、Android SDK Build Tools 36.0.0。
- `bash tools/test-yinxing-guard.sh all`：主机 Bash 和 BusyBox ash 均通过，耗时 22.30 秒。
- `bash -n root/kernelsu/yinxing_guard/bin/*.sh tools/package-yinxing-guard.sh tools/test-yinxing-guard.sh`：通过。
- `:app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon`：344 项测试，0 失败、0 错误、0 跳过；耗时 81.80 秒。
- `aapt2 dump badging`：包名 `com.yinxing.launcher`、`versionCode=25`、`versionName=1.10.0-root-preview.9`。
- `apksigner verify --verbose`：APK Signature Scheme v2 验证通过。
- KernelSU ZIP：条目位于归档根目录，脚本均为可执行权限，时间戳归一化，重复打包字节一致。

## SHA-256

```text
77b44381b587faa8998dbcb5ff86c511a232ed2f862bc6c5278322d63c523f75  yinxing-1.10.0-root-preview.9-debug.apk
fc5ce010073406041a968c7880ee2a6ec5e70e3af9cd5c441b262b18985fcd5c  yinxing-guard-1.10.0-root-preview.9.zip
```

本 Preview 未在真实一加 15 上执行；发布资产用于专机体验验证，后续根据设备日志继续调整 ColorOS 16 的窗口识别和回退时序。
