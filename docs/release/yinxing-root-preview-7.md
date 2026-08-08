# 银杏 Root 无障碍绑定恢复预览 7

本版面向用户控制的中国版一加 15、ColorOS 16、KernelSU Root 专机，继续强化 Root Guard 的保活、无障碍自动恢复和老年桌面入口可靠性。

## 资产

- `yinxing-1.10.0-root-preview.7-debug.apk`：银杏体验 APK，`versionCode=23`。
- `yinxing-guard-1.10.0-root-preview.7.zip`：KernelSU Root Guard 模块，`versionCode=7`。
- `SHA256SUMS.txt`：以上两个文件的 SHA-256 校验值。

## 本版行为

- Root Guard 读取 `dumpsys accessibility` 的 `Bound services`、`Binding services` 和 `Crashed services` 区段，识别银杏固定无障碍组件是否真的有绑定。
- 只有目标组件明确出现在 `Crashed services` 时，才从现有冒号分隔列表中移除银杏、等待 1 秒、恢复原列表并重新写入 `accessibility_enabled=1`。
- TalkBack 或其他无障碍服务原值保留；`Bound`、`Binding`、空输出、命令失败或无法识别的厂商输出都不触发设置切换。
- Root 健康快照仍为 8 行；显式崩溃报告为 `accessibility=stale`，APK 将其解析为降级状态，提示真实绑定状态而不是只相信设置项。
- 保留 Preview 6 的同启动周期 owner 锁、监督器退避、Doze 所有权和卸载延迟清理语义；不增加任意 Root shell、坐标点击、杀进程或 ColorOS 私有设置。

## 安装与体验

1. 安装 APK，至少启动一次，并确认银杏仍是默认桌面。
2. 在 KernelSU 管理器中安装并启用 `yinxing-guard-1.10.0-root-preview.7.zip`。
3. 重启手机，观察开机后无障碍服务、桌面保活和银杏健康状态。
4. 若服务曾崩溃，检查模块日志是否出现 `accessibility_service_rebound`；确认 TalkBack 等其他服务仍在列表中。
5. 在 KernelSU 中禁用模块，确认监督进程停止；重新启用并重启后确认链路恢复。

APK 与 KernelSU 模块应保持同一预览号。构建机没有连接目标一加 15，ColorOS 16 的实际开机时序、厂商 `dumpsys` 格式和后台策略仍需真机确认。

## 构建环境与验证

- Linux amd64，OpenJDK 21.0.11，Gradle 9.3.1，Kotlin 2.2.21。
- Android `compileSdk/targetSdk=36`，Build Tools `36.0.0`；Gradle 使用共享缓存和 HTTP/HTTPS 代理。
- Host Root Guard 全套：通过，外部计时 6.95 秒。
- 独立 BusyBox `ash` Root Guard 全套：通过，外部计时 7.69 秒。
- Bash `-n`、BusyBox `ash -n`、`git diff --check`：通过。
- `:app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon --console=plain`：`BUILD SUCCESSFUL`，外部计时 74.58 秒；JUnit XML 汇总 338 tests，0 skipped，0 failures，0 errors。
- APK `aapt2 dump badging`：包名 `com.yinxing.launcher`、`versionCode=23`、`versionName=1.10.0-root-preview.7`。
- APK `apksigner verify --verbose`：v2 `true`，1 个 signer；Debug 签名，不是正式发布私钥。
- KernelSU ZIP：`unzip -t` 完整性、固定根布局、7 个脚本可执行权限和所有条目 `1980-01-01 00:00:00` 时间戳均通过；重复打包字节一致。

## 回滚

1. 在 KernelSU 中禁用或卸载 `yinxing_guard`，然后重启。
2. 需要回退时，安装 Preview 6 APK 和模块：<https://github.com/Gs-ygc/yinxing/releases/tag/v1.10.0-root-preview.6>。
3. 无法进入系统时，使用 KernelSU 的模块救援方式禁用 `yinxing_guard`。

## GitHub Release

<https://github.com/Gs-ygc/yinxing/releases/tag/v1.10.0-root-preview.7>

## SHA-256

```text
68ffbfaad3cbcadb2403f75ad6049d6d7714b8049436d12ebf1acc63bd1cd60f  yinxing-1.10.0-root-preview.7-debug.apk
0cc36e36c789c473ff406b0f666469c8ae556521bb6c64ec73a2ec4063a089cc  yinxing-guard-1.10.0-root-preview.7.zip
```
