# 银杏 Root 自动化生命周期预览 6

本版面向用户控制的中国版一加 15、ColorOS 16、KernelSU Root 专机，继续强化 Root Guard 的保活、无障碍自动恢复和晚启动自愈。

Preview 6 修复了 Preview 5 的一个监督边界：Guard 以前用状态 `0` 同时表示“已有同启动周期的活跃 owner”和“有限运行正常结束”，监督器无法安全地在 owner 消失后重试。现在活跃 owner 冲突返回专用状态 `76`；监督器默认等待 30 秒后重新尝试取得锁，正常完成仍以 `0` 结束。这样不会把一次性 Guard 测试或正常结束无限拉起，同时能覆盖 owner 被系统回收后留下的锁。

## 资产

- `yinxing-1.10.0-root-preview.6-debug.apk`：银杏体验 APK，`versionCode=22`。
- `yinxing-guard-1.10.0-root-preview.6.zip`：KernelSU Root Guard 模块，`versionCode=6`。
- `SHA256SUMS.txt`：以上两个文件的 SHA-256 校验值。

## 本版行为

- Guard 发现同一启动周期的活跃 PID 时返回 `76`，监督器按 `YINXING_GUARD_OWNER_RETRY_SECONDS` 等待，默认 30 秒。
- 不完整锁仍返回 `75`，沿用 5 秒短重试；其他非零失败仍记录固定事件并按默认 30 秒退避。
- 每次重新启动 Guard 前后都检查模块目录、`disable` 和 `remove` 标记；禁用、移除或目录消失时停止监督。
- 只重用现有固定修复路径：恢复银杏无障碍服务、保活策略和固定桌面入口；不增加任意 Root shell、坐标点击、包白名单或 ColorOS 私有设置。
- 不会在用户主动使用其他应用时强制拉回桌面。

Preview 4/5 已有的服务连接闸门、会话代际保护、服务重连清理、Kiosk 拉回重试、健康面板和卸载清理语义均保留。

## 安装前注意

APK 使用构建机 Debug 签名，不是正式发布私钥签名。若手机上的银杏来自其他签名，Android 可能拒绝覆盖安装；请先备份联系人和设置，再决定是否清洁安装。APK 与 KernelSU 模块应保持同一预览号。

本版只针对 Android 用户 0 的固定 Root 专机；需要 KernelSU 已授权 Root。构建机没有连接目标一加 15，ColorOS 16 的实际开机时序、授权状态和后台策略仍需真机确认。

## 安装与体验

1. 安装 APK，至少启动一次，并确认银杏仍是默认桌面。
2. 在 KernelSU 管理器中安装并启用 `yinxing-guard-1.10.0-root-preview.6.zip`。
3. 重启手机，观察开机后无障碍服务、桌面保活和银杏健康状态是否自动恢复。
4. 在开机后较早阶段发起一次视频自动化，或在包管理/安全设置尚未完全就绪的窗口触发一次检查，观察 Guard 是否会在短暂失败后继续修复。
5. 在 KernelSU 中禁用模块，确认旧监督进程停止；重新启用并重启后确认链路恢复。

体验反馈请尽量包含：是否覆盖安装、重启后的时间点、KernelSU 模块日志中是否出现 `guard_already_running` 或 `guard_unexpected_exit`、无障碍服务当前状态，以及是否发生桌面抢前台。

## 验证证据

- Host Root Guard 全套：通过。
- 独立 BusyBox `ash` Root Guard 全套：通过。
- POSIX `sh -n`、BusyBox `ash -n`、Bash 语法与 `git diff --check`：通过。
- Android Debug 单元测试与 APK 构建：337 tests，0 skipped，0 failures，0 errors。
- Gradle：`BUILD SUCCESSFUL in 1m 27s`；外部计时 `87.71s`。
- APK `aapt2 dump badging`：包名 `com.yinxing.launcher`、`versionCode=22`、`versionName=1.10.0-root-preview.6`。
- APK `apksigner verify --verbose`：v2 `true`，1 个 signer。
- KernelSU ZIP：归档完整性、固定根布局、可执行权限和 1980-01-01 规范化时间戳均通过。

## 回滚

1. 在 KernelSU 中禁用或卸载 `yinxing_guard`，然后重启。
2. 需要回退时，安装 Preview 5 APK 和模块：<https://github.com/Gs-ygc/yinxing/releases/tag/v1.10.0-root-preview.5>。
3. 无法进入系统时，使用 KernelSU 的模块救援方式禁用 `yinxing_guard`。

## SHA-256

```text
4980a149d8950a4b7b86f19260966c3e4b1a839e17c7c172426fbe7ef67f0092  yinxing-1.10.0-root-preview.6-debug.apk
d9b729986857e79a967643cddb94651ef87b629b9c73d9ea758e8894e8e0c81a  yinxing-guard-1.10.0-root-preview.6.zip
```
