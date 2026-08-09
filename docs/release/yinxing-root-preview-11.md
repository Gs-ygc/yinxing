# 银杏 Root 增强 Preview 11

Preview 11 面向一加 15 中国版 ColorOS 16、KernelSU、已 Root 专机，修复 Root “立即修复”可能在无障碍重绑确认完成前被共享 3 秒超时截断的问题。Root 调用仍由固定命令白名单控制，但每个命令现在使用与职责匹配的超时预算。

## 发布内容

- `yinxing-1.10.0-root-preview.11-debug.apk`：银杏体验 APK，`versionCode=27`。
- `yinxing-guard-1.10.0-root-preview.11.zip`：KernelSU Root Guard 模块，`versionCode=11`。
- `SHA256SUMS.txt`：两个资产的 SHA-256 校验值，仅使用资产文件名。

## Preview 11 变化

| 固定 Root 命令 | 默认超时 | 设计目的 |
| --- | ---: | --- |
| `status.sh` | 3,000 ms | 健康检查保持快速失败 |
| `action.sh` | 12,000 ms | 覆盖移除/恢复设置项及重绑后的有限确认等待 |
| `kiosk-home.sh` | 1,200 ms | 桌面拉起保持短超时，避免阻塞主流程 |

恢复命令单独使用更长预算，是因为无障碍服务崩溃后的恢复脚本可能包含一次设置项重绑和最多数轮只读状态确认；状态检查与桌面切换不需要承担这段等待。测试仍可通过 `SuRootCommandRunner(timeoutMillis=...)` 使用正数统一覆盖值，生产默认值由固定命令枚举集中维护。

APK 的 Root 调用白名单保持不变，只允许三个固定、无参数的模块路径：`/data/adb/modules/yinxing_guard/bin/status.sh`、`/data/adb/modules/yinxing_guard/action.sh` 和 `/data/adb/modules/yinxing_guard/bin/kiosk-home.sh`。超时清理只处理当前 runner 自己启动的 `su` 进程；没有增加任意 shell、包名、组件、坐标、应用/系统进程终止命令或 ColorOS 私有接口。超时、启动失败、输出超限均继续按失败关闭处理。

## 安装顺序

1. 在 KernelSU 中先安装并启用 `yinxing-guard-1.10.0-root-preview.11.zip`。如果 KernelSU 要求重启，先重启让模块生效。
2. 再安装 `yinxing-1.10.0-root-preview.11-debug.apk`，覆盖 Preview 10 时使用升级安装。
3. 启动银杏后检查 Root 增强状态；若曾出现无障碍失效，可执行一次“立即修复”并等待状态确认完成。
4. 首次体验建议保留 Preview 10 APK 和模块 ZIP，以便按下面步骤回滚。

这是 Debug APK，安装时可能受到设备现有签名策略限制；不要把它当作生产 Release 包分发。

## 回滚

先在 KernelSU 中停用或卸载 Preview 11 模块，再安装 Preview 10 模块并按 KernelSU 提示重启。APK 可用 Preview 10 Debug 包覆盖安装；若系统拒绝低版本覆盖，使用设备允许的降级安装方式或先卸载当前 APK，再安装 Preview 10。

## 验证记录

- 环境：Gradle 9.3.1、OpenJDK 21.0.11、Android SDK Build Tools 36.0.0。
- `bash tools/test-yinxing-guard.sh all`：主机 Bash 和 BusyBox ash 均通过，耗时 24.97 秒。
- `bash -n root/kernelsu/yinxing_guard/bin/*.sh tools/test-yinxing-guard.sh tools/package-yinxing-guard.sh` 与 `busybox ash -n root/kernelsu/yinxing_guard/bin/common.sh`：通过。
- `:app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon`：347 项测试，0 失败、0 错误、0 跳过；耗时 91.32 秒。
- `aapt2 dump badging`：包名 `com.yinxing.launcher`、`versionCode=27`、`versionName=1.10.0-root-preview.11`。
- `apksigner verify --verbose`：APK Signature Scheme v2 验证通过。
- KernelSU ZIP：11 个条目位于归档根目录，脚本均为可执行权限，时间戳归一化为 1980-01-01 00:00:00，重复打包字节一致。

## SHA-256

```text
934cf17d93b51cec9e5ade56df5dbc2ba392589216bac73c54115c75ad3173a2  yinxing-1.10.0-root-preview.11-debug.apk
a5bf2a946985cf3dbea1b5a688a0db45360ccded00d7371362a1ae7597e5023f  yinxing-guard-1.10.0-root-preview.11.zip
```

本 Preview 未连接真实一加 15，未执行 ColorOS 16 真机验证；发布资产用于专机体验，后续将根据设备状态和日志继续调整恢复时序。

