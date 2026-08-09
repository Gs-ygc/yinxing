# 银杏 Root 增强 Preview 10

Preview 10 面向一加 15 中国版 ColorOS 16、KernelSU、已 Root 专机，补强了无障碍服务崩溃后的恢复判定。Root Guard 现在会在一次精确重绑后确认银杏无障碍服务是否真正离开 `Crashed services`，避免把仍在崩溃的服务误报为已恢复。

## 发布内容

- `yinxing-1.10.0-root-preview.10-debug.apk`：银杏体验 APK，`versionCode=26`。
- `yinxing-guard-1.10.0-root-preview.10.zip`：KernelSU Root Guard 模块，`versionCode=10`。
- `SHA256SUMS.txt`：两个资产的 SHA-256 校验值，仅使用资产文件名。

## Preview 10 变化

- 检测到固定银杏无障碍组件处于 `Crashed services` 后，仍只执行一次移除/恢复设置项，并保留 TalkBack 等其他已启用服务。
- 重绑后默认最多执行 5 次只读 `dumpsys accessibility` 确认，仅在状态仍明确为 `crashed` 时每秒等待一次；确认过程不会再次写设置项。
- 持续确认崩溃会让修复返回失败、记录 `last_repair=failed`，手动修复动作也不会继续拉起桌面；后台 Guard 会在下一健康周期重试。
- ColorOS 输出缺失或无法识别时保持非破坏性，不重复切换无障碍设置，避免因厂商格式差异造成修复循环。

| 重绑后状态 | Preview 10 结果 |
| --- | --- |
| `bound` / `binding` | 确认恢复成功 |
| 最后一次仍为 `crashed` | 修复失败，等待下一周期重试 |
| `unknown` | 停止确认并按非破坏性成功处理 |

APK 的 Root 调用白名单保持不变，只允许三个固定、无参数的模块路径：`status.sh`、`action.sh` 和 `kiosk-home.sh`。本版本没有增加任意 shell、包名、组件、坐标、进程终止或 ColorOS 私有接口。

## 安装顺序

1. 在 KernelSU 中先安装并启用 `yinxing-guard-1.10.0-root-preview.10.zip`。如果 KernelSU 要求重启，先重启让模块生效。
2. 再安装 `yinxing-1.10.0-root-preview.10-debug.apk`，覆盖 Preview 9 时使用升级安装。
3. 启动银杏后检查 Root 增强状态；若曾出现无障碍失效，可执行一次“立即修复”并观察状态是否恢复。
4. 首次体验建议保留 Preview 9 APK 和模块 ZIP，以便按下面步骤回滚。

这是 Debug APK，安装时可能受到设备现有签名策略限制；不要把它当作生产 Release 包分发。

## 回滚

先在 KernelSU 中停用或卸载 Preview 10 模块，再安装 Preview 9 模块并按 KernelSU 提示重启。APK 可用 Preview 9 Debug 包覆盖安装；若系统拒绝低版本覆盖，使用设备允许的降级安装方式或先卸载当前 APK，再安装 Preview 9。

## 验证记录

- 环境：Gradle 9.3.1、OpenJDK 21.0.11、Android SDK Build Tools 36.0.0。
- `bash tools/test-yinxing-guard.sh all`：主机 Bash 和 BusyBox ash 均通过，耗时 24.06 秒。
- `bash -n root/kernelsu/yinxing_guard/bin/*.sh tools/test-yinxing-guard.sh tools/package-yinxing-guard.sh` 与 `busybox ash -n root/kernelsu/yinxing_guard/bin/common.sh`：通过。
- `:app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon`：344 项测试，0 失败、0 错误、0 跳过；耗时 101.91 秒。
- `aapt2 dump badging`：包名 `com.yinxing.launcher`、`versionCode=26`、`versionName=1.10.0-root-preview.10`。
- `apksigner verify --verbose`：APK Signature Scheme v2 验证通过。
- KernelSU ZIP：11 个条目位于归档根目录，脚本均为可执行权限，时间戳归一化为 1980-01-01 00:00:00，重复打包字节一致。

## SHA-256

```text
1511090454f614b3b15542a88eb276d392575e99c0f29916e7d4e35c12529cd1  yinxing-1.10.0-root-preview.10-debug.apk
4a98922ac8aa348aec4f5284c258a8bb06f921f63eb820ebc1941ccc89540ebc  yinxing-guard-1.10.0-root-preview.10.zip
```

本 Preview 未连接真实一加 15，未执行 ColorOS 16 真机验证；发布资产用于专机体验，后续将根据设备状态和日志继续调整恢复时序。
