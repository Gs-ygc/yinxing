# 银杏 Root 增强 Preview 12

Preview 12 面向一加 15 中国版 ColorOS 16、KernelSU、已 Root 专机，补齐“安全设置仍显示无障碍已启用，但系统诊断确认服务没有处于绑定、绑定中或崩溃列表”的自动恢复缺口。

## 发布内容

- `yinxing-1.10.0-root-preview.12-debug.apk`：银杏体验 APK，`versionCode=28`。
- `yinxing-guard-1.10.0-root-preview.12.zip`：KernelSU Root Guard 模块，`versionCode=12`。
- `SHA256SUMS.txt`：两个资产的 SHA-256 校验值，仅使用资产文件名。

## Preview 12 变化

Root Guard 现在区分“诊断未知”和“确认未绑定”。只有 `dumpsys accessibility` 同时包含 `Bound services`、`Binding services`、`Crashed services` 三个已识别区段，且固定银杏组件在三个区段中均不存在时，内部状态才是 `unbound`；状态接口继续复用已有 `accessibility=stale`，没有增加 APK 协议值。

确认未绑定只会在修复周期开始前同时满足以下条件时触发一次既有的精确重绑：`enabled_accessibility_services` 已包含银杏组件，且 `accessibility_enabled=1`。首次启用时不立即解绑重绑，避免打断 Android 正常的异步绑定过程。重绑只移除并恢复固定银杏组件，TalkBack 和其他无障碍服务列表项保持不变。

重绑后的 `unbound` 与 `crashed` 共用既有限次确认流程；出现 `bound` 或 `binding` 即成功，持续未绑定会在上限内失败并记录修复失败。命令失败、空输出、缺少任一区段、截断输出或 ColorOS 改名区段仍归为 `unknown`，保持无副作用且不使其他修复失败。

APK 的 Root 调用白名单保持不变，只允许三个固定、无参数的模块路径：`/data/adb/modules/yinxing_guard/bin/status.sh`、`/data/adb/modules/yinxing_guard/action.sh` 和 `/data/adb/modules/yinxing_guard/bin/kiosk-home.sh`。没有增加任意 shell、参数、包名/组件输入、坐标点击、应用或系统进程终止命令，也没有调用 ColorOS 私有接口。

## 安装顺序

1. 在 KernelSU 中先安装并启用 `yinxing-guard-1.10.0-root-preview.12.zip`。如果 KernelSU 要求重启，先重启让模块生效。
2. 再安装 `yinxing-1.10.0-root-preview.12-debug.apk`，覆盖 Preview 11 时使用升级安装。
3. 启动银杏后检查 Root 增强状态；若无障碍仍显示异常，可执行一次“立即修复”并等待有限次绑定确认完成。
4. 首次体验建议保留 Preview 11 APK 和模块 ZIP，以便按下面步骤回滚。

这是 Debug APK，安装时可能受到设备现有签名策略限制；不要把它当作生产 Release 包分发。

## 回滚

先在 KernelSU 中停用或卸载 Preview 12 模块，再安装 Preview 11 模块并按 KernelSU 提示重启。APK 可用 Preview 11 Debug 包覆盖安装；若系统拒绝低版本覆盖，使用设备允许的降级安装方式或先卸载当前 APK，再安装 Preview 11。

## 验证记录

- 环境：Gradle 9.3.1、OpenJDK 21.0.11、Android SDK Build Tools 36.0.0。
- `bash tools/test-yinxing-guard.sh all`：主机 Bash 和 BusyBox ash 均通过，最终候选耗时 27.18 秒。
- 新增回归覆盖：完整空绑定区段报告为 `stale`、已启用服务精确重绑、持续未绑定有限失败、首次启用不重复重绑、部分诊断无副作用。
- `bash -n root/kernelsu/yinxing_guard/bin/*.sh tools/test-yinxing-guard.sh tools/package-yinxing-guard.sh`、`busybox ash -n root/kernelsu/yinxing_guard/bin/common.sh` 和 `git diff --check`：通过。
- `:app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon`：347 项测试，0 失败、0 错误、0 跳过；耗时 111.31 秒。
- 最终发布源复现：主机 Bash 和 BusyBox ash 耗时 27.16 秒；同一强制 Android 命令耗时 84.35 秒，仍为 347 项测试、0 失败、0 错误、0 跳过；重建 APK 和模块 ZIP 均与发布候选逐字节一致。
- `aapt2 dump badging`：包名 `com.yinxing.launcher`、`versionCode=28`、`versionName=1.10.0-root-preview.12`。
- `apksigner verify --verbose`：APK Signature Scheme v2 验证通过。
- KernelSU ZIP：11 个条目位于归档根目录，脚本均为可执行权限，时间戳归一化为 1980-01-01 00:00:00，重复打包字节一致。

## SHA-256

```text
f92cf65c34009ddda601ae007cf3adac056c8682d355ae778d8d63812426613c  yinxing-1.10.0-root-preview.12-debug.apk
804d378cbce05a5bfdd5a9355aa265da601df00145c85f16a379c64ee71e0049  yinxing-guard-1.10.0-root-preview.12.zip
```

本 Preview 未连接真实一加 15，未执行 ColorOS 16 真机验证；发布资产用于专机体验，后续将根据设备的 Root 状态、无障碍绑定状态和日志继续迭代。
