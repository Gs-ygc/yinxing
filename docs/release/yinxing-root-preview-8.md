# 银杏 Root 无障碍绑定恢复预览 8

本版面向用户控制的中国版一加 15、ColorOS 16、KernelSU Root 专机，继续强化 Root Guard 的保活、无障碍自动恢复和老年桌面入口可靠性。

## 资产

- `yinxing-1.10.0-root-preview.8-debug.apk`：银杏体验 APK，`versionCode=24`。
- `yinxing-guard-1.10.0-root-preview.8.zip`：KernelSU Root Guard 模块，`versionCode=8`。
- `SHA256SUMS.txt`：以上两个文件的 SHA-256 校验值。

## 本版行为

- Root Guard 在同一启动周期的 owner 锁中写入 `/proc/<pid>/stat` 的进程启动时间 token，并保持 `boot_id`、启动时间、PID 的发布顺序：PID 最后写入。
- 竞争者只有在 PID 存活且启动时间 token 匹配时才认定 owner 活跃并返回 76；同 PID 但 token 明确不匹配时认定为陈旧锁，通过现有排他 reclaim 目录接管，不发送任何杀进程命令。
- 旧版没有启动时间文件、当前 `/proc` 不可读或 token 格式异常时保持保守行为：仍认定存活 owner，避免误接管；`status.sh` 只在明确身份不匹配时报告 `guard=stale`。
- 目录已创建但 PID 尚未发布的短窗口仍返回 75 给 supervisor 重试；一旦读到匹配的活跃 owner，临时重试标志不会再掩盖 76。
- `dumpsys accessibility` 仍只在目标银杏组件明确位于 `Crashed services` 区段时触发解绑、等待和恢复；其他服务原值保留，无法识别的厂商输出不触发设置切换。
- 保留此前的 Doze 所有权、监督器退避、卸载延迟清理和老年桌面入口语义；不增加任意 Root shell、坐标点击、杀进程或 ColorOS 私有设置。

## 安装与体验

1. 安装 APK，至少启动一次，并确认银杏仍是默认桌面。
2. 在 KernelSU 管理器中安装并启用 `yinxing-guard-1.10.0-root-preview.8.zip`。
3. 重启手机，观察开机后无障碍服务、桌面保活和银杏健康状态。
4. 可在模块状态输出中确认同启动周期锁的 `boot_id`、`start_time` 和 PID 均存在；模拟或遇到 PID 复用时，旧 owner 不应阻塞新的健康周期。
5. 在 KernelSU 中禁用模块，确认监督进程停止；重新启用并重启后确认链路恢复。

APK 与 KernelSU 模块应保持同一预览号。构建机没有连接目标一加 15，ColorOS 16 的实际开机时序、厂商 `dumpsys` 格式和后台策略仍需真机确认。

## 构建环境与验证

- Linux amd64，OpenJDK 21.0.11，Gradle 9.3.1，Kotlin 2.2.21。
- Android `compileSdk/targetSdk=36`，Build Tools `36.0.0`；Gradle 通过显式 HTTP/HTTPS 代理下载 wrapper 并使用本地依赖缓存。
- Host Root Guard 全套：通过，外部计时 11.84 秒。
- 独立 BusyBox `ash` Root Guard 全套：通过，外部计时 11.36 秒。
- Bash `-n`、BusyBox `ash -n`、`git diff --check`：通过。
- `:app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon --console=plain`：`BUILD SUCCESSFUL`，外部计时 393.37 秒；JUnit XML 汇总 338 tests，0 skipped，0 failures，0 errors。
- APK `aapt2 dump badging`：包名 `com.yinxing.launcher`、`versionCode=24`、`versionName=1.10.0-root-preview.8`。
- APK `apksigner verify --verbose`：v2 `true`，1 个 signer；Debug 签名，不是正式发布私钥。
- KernelSU ZIP：`unzip -t` 完整性、固定根布局、脚本可执行权限和所有条目 `1980-01-01 00:00:00` 时间戳均通过；重复打包字节一致。

## 回滚

1. 在 KernelSU 中禁用或卸载 `yinxing_guard`，然后重启。
2. 需要回退时，安装 Preview 7 APK 和模块：<https://github.com/Gs-ygc/yinxing/releases/tag/v1.10.0-root-preview.7>。
3. 无法进入系统时，使用 KernelSU 的模块救援方式禁用 `yinxing_guard`。

## GitHub Release

<https://github.com/Gs-ygc/yinxing/releases/tag/v1.10.0-root-preview.8>

## SHA-256

```text
1bfd1d3a54a8aa7afca8b332ffcf0efd3c94b5d0a7eb6798a18da7b27902d242  yinxing-1.10.0-root-preview.8-debug.apk
d42615796e20ba9f44d1c5a8a2624b3c9b9a63e3d46898ab2aefca65ae49e5fc  yinxing-guard-1.10.0-root-preview.8.zip
```
