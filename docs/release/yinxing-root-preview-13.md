# 银杏 Root 增强 Preview 13

Preview 13 面向一加 15 中国版 ColorOS 16、KernelSU、已 Root 专机，修复 Root Guard 进程仍存活、但某个 Android Binder 命令永久卡住后整条自动修复链停止工作的缺口。

## 发布内容

- `yinxing-1.10.0-root-preview.13-debug.apk`：银杏体验 APK，`versionCode=29`。
- `yinxing-guard-1.10.0-root-preview.13.zip`：KernelSU Root Guard 模块，`versionCode=13`。
- `SHA256SUMS.txt`：两个资产的 SHA-256 校验值，仅使用资产文件名。

## Preview 13 变化

Root Guard 现在为所有现有 Android 命令增加模块内固定边界：`pm`、`settings`、`dumpsys accessibility`、`cmd deviceidle`、`cmd appops`、`am start` 和启动阶段 `getprop` 默认在两秒触发终止，并保留最多一秒强杀余量。固定命令在 KernelSU BusyBox 创建的新会话中运行；发生失败或超时时，仍存活的会话 leader 只清理自己的 `-$$` 进程组，因此没有回收后 PID 复用窗口，即使 APK/su 外层先结束，Android 命令包装脚本的阻塞后代也不能继续占住 Guard 的输出管道。

超时沿用原有语义：无障碍诊断超时归为 `unknown`，不触发设置切换；包与设置操作超时走现有修复失败路径；Doze 与 app-op 仍是非致命的可选保活；固定 HOME 启动超时返回失败；启动属性读取不再能无限阻塞 Guard。没有增加状态协议值。

生产模块明确使用 KernelSU 的 `/data/adb/ksu/bin/busybox` 及其 `setsid`、`timeout`、`kill` applet。若该边界不可用，固定命令会失败关闭，不会降级为无超时执行。该能力基于 [KernelSU 官方模块指南](https://kernelsu.org/guide/module.html) 描述的完整 BusyBox 与模块 Shell 环境。

APK 的 Root 调用白名单保持不变，只允许三个固定、无参数的模块路径：`/data/adb/modules/yinxing_guard/bin/status.sh`、`/data/adb/modules/yinxing_guard/action.sh` 和 `/data/adb/modules/yinxing_guard/bin/kiosk-home.sh`。没有增加任意 shell、参数、包名/组件输入、坐标点击、现有应用/系统进程选择或 ColorOS 私有接口。

## 安装顺序

1. 在 KernelSU 中先安装并启用 `yinxing-guard-1.10.0-root-preview.13.zip`。如果 KernelSU 要求重启，先重启让模块生效。
2. 再安装 `yinxing-1.10.0-root-preview.13-debug.apk`，覆盖 Preview 12 时使用升级安装。
3. 启动银杏后检查 Root 增强状态；若无障碍仍显示异常，可执行一次“立即修复”并观察状态是否在有限时间内更新。
4. 首次体验建议保留 Preview 12 APK 和模块 ZIP，以便按下面步骤回滚。

这是 Debug APK，安装时可能受到设备现有签名策略限制；不要把它当作生产 Release 包分发。

## 回滚

先在 KernelSU 中停用或卸载 Preview 13 模块，再安装 Preview 12 模块并按 KernelSU 提示重启。APK 可用 Preview 12 Debug 包覆盖安装；若系统拒绝低版本覆盖，使用设备允许的降级安装方式或先卸载当前 APK，再安装 Preview 12。

Preview 12 Release：<https://github.com/Gs-ygc/yinxing/releases/tag/v1.10.0-root-preview.12>

## 验证记录

- 环境：Gradle 9.3.1、OpenJDK 21.0.11、Android SDK Build Tools 36.0.0、BusyBox 1.36.1。
- `bash tools/test-yinxing-guard.sh all`：主机 Shell 和递归 BusyBox ash 均通过，最终源码复现耗时 43.49 秒。
- 新增回归覆盖：卡死无障碍诊断在边界内返回且无设置副作用、卡死包查询记录修复失败并禁止 HOME、卡死固定 HOME 只尝试一次、卡死卸载 Doze 清理保留 marker 与重试脚本、外层调用方先退出后仍清理阻塞后代、非法/非正超时回退安全默认值，以及会话外无关进程不受清理影响。测试中的真实阻塞子进程同时验证进程组清理。
- 所有模块内 `pm`、`settings`、`dumpsys`、`cmd`、`am`、`getprop` 调用均经统一固定命令边界；Shell 语法、BusyBox ash 语法、旧版本残留扫描和 `git diff --check` 均通过。
- `:app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon`：347 项测试，0 失败、0 错误、0 跳过；首次冷构建包含 Gradle 发行版下载，耗时 1485.31 秒。
- 独立审查发现并阻止了调用方先退出后的后代残留与回收后 PGID 复用风险；修正后强制 Android 复现耗时 104.35 秒，仍为 347 项测试、0 失败、0 错误、0 跳过，重建 APK 与模块 ZIP 均和候选逐字节一致。
- `aapt2 dump badging`：包名 `com.yinxing.launcher`、`versionCode=29`、`versionName=1.10.0-root-preview.13`。
- `apksigner verify --verbose`：APK Signature Scheme v2 验证通过。
- KernelSU ZIP：11 个条目位于归档根目录，脚本均为可执行权限，时间戳归一化为 1980-01-01 00:00:00，重复打包字节一致。

## SHA-256

```text
9e5dedc929f6e418c6606117f3eeb0309e915a8f05e9801c40835a0225814e75  yinxing-1.10.0-root-preview.13-debug.apk
52e256f8d65cbd1d9bde0c7becddc22daf127560d16b58cd5fc00f1e24b17240  yinxing-guard-1.10.0-root-preview.13.zip
```

本 Preview 未连接真实一加 15，未执行 ColorOS 16 真机验证；发布资产用于专机体验，后续将根据设备的 Root 状态、无障碍绑定状态、修复耗时和模块日志继续迭代。
