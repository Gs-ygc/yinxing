# 银杏 Root 恢复 Preview 27

Preview 27 针对一加 15 / 中国版 ColorOS 16 / KernelSU 专机上已经确认的两种独立故障：
`su 入口不可见`，以及 Root 命令退出码 `126 Permission denied`。本版不再把这两类结果或其他
Root 故障合并成同一句“Root 不可用”，并移除 APK 对模块脚本可执行位的依赖。

已经安装并启用 Preview 26 Root Guard 模块的手机只需更新本版 APK，不需要重新安装模块。

## 发布内容

- `yinxing-1.10.0-root-preview.27-debug.apk`：银杏 Debug APK，`versionCode=43`，
  `versionName=1.10.0-root-preview.27`。
- `SHA256SUMS.txt`：APK 的 SHA-256 校验值。
- Root Guard 模块未改变，不在本 Release 重复发布。需要模块时使用
  [Preview 26 原模块](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.26/yinxing-guard-1.10.0-root-preview.26.zip)，
  已发布 SHA-256 为 `96f243ed79bf7216a1576fdd64ba1943dd5125e07d83750ed19bca56c53b7cf9`。

## Root 执行修复

- 状态、立即修复和 Kiosk HOME 恢复仍只允许三个固定脚本；三条路径现在统一通过
  `/system/bin/su -c "/system/bin/sh <固定脚本>"` 执行。
- `/system/bin/sh` 读取脚本，不再要求 `status.sh`、`action.sh` 或 `kiosk-home.sh` 自身具有可执行位。
  固定路径、超时和输出上限不变，没有新增任意命令入口。
- KernelSU 授权边界没有绕过。若 KernelSU 未向银杏当前 UID 暴露 `/system/bin/su`，页面仍会明确
  显示 `su 入口不可见` 和该 UID，需要在 KernelSU 管理器中授权。

## 精确诊断

家属设置的 Root 专机面板现在保留并显示：

- 失败阶段：启动 `su`、执行状态/修复/HOME 脚本、解析状态或执行器异常；
- 银杏当前应用 UID；
- 实际选择的完整固定命令；
- 退出码，或在进程没有启动时显示“未启动”；
- 系统返回的原始文本，空输出明确显示“无输出”。

诊断文本有固定长度边界并过滤不可显示控制字符，开头和结尾都会保留。一次“立即修复”失败后，
即使紧接着读取到健康状态，`action.sh` 的退出码和系统原文仍保留在修复行，不会被健康状态覆盖。

## 范围边界

- 没有 BusyBox 改造，没有 Root Guard 模块、守护进程、开机流程、无障碍策略或 HOME 策略变化。
- 没有新增服务、接收器、后台轮询、唤醒锁或空闲功耗来源。
- 老人日常桌面没有增加诊断文字；完整证据只在家属主动打开的 Root 专机面板显示。
- 本地没有连接一加 15，因此不宣称已经在 ColorOS 16 真机上恢复 Root。此 Release 用于收集不再
  丢失的设备原始证据并验证固定系统 shell 路径。

## 安装与验收

1. 若手机已安装并启用 Preview 26 Root Guard 模块，只覆盖安装本版 APK。若从更早版本开始，先从
   上方链接安装 Preview 26 模块并重启。
2. APK 使用 Android Debug 签名。相同签名可以覆盖升级；若手机上的 APK 签名不同，需要先备份银杏
   配置再卸载旧包，清洁安装会清除应用数据并可能改变 UID，随后必须重新核对 KernelSU 授权。
3. 打开“家属设置 → Root 专机”，完整记录状态行中的失败阶段、应用 UID、固定命令、退出码和系统
   原文，不要只记录顶部徽标。
4. 点一次“立即修复并复查”，等待结束；分别检查状态行和修复行，并完整记录两行诊断。
5. 若仍显示 `su 入口不可见`，按页面 UID 检查 KernelSU 超级用户授权和 su 兼容功能。若有退出码或
   系统原文，原样反馈，不再根据统一文案猜测原因。

## 回滚

- 回滚到 [Preview 26](https://github.com/Gs-ygc/yinxing/releases/tag/v1.10.0-root-preview.26)
  时可以保留同一个 Preview 26 模块。
- Android 通常不允许普通覆盖安装更低 `versionCode`。需按专机维护流程备份配置后卸载，或使用明确
  允许降级的调试安装流程；卸载会清除应用数据，并可能要求重新设置 HOME、无障碍和 KernelSU 授权。
- Preview 27 没有修改模块或系统状态，回滚不需要额外撤销 Root Guard 行为。

## 本地验证边界

- Root 执行与家属面板的 74 个聚焦测试通过，0 failures、0 errors、0 skipped；强制执行 32 个
  Gradle 任务，外部耗时 71.35 秒。独立审查发现的面板端到端测试缺口已经补齐并复审通过。
- Preview 26 的完整 Root Guard 宿主与递归 standalone BusyBox `ash` 测试通过；相对 Preview 26 的
  `root/` 与 `AndroidManifest.xml` 差异为零。
- 最终源码强制执行全部 80 个 Android 任务并通过，外部耗时 101.22 秒；517 个 JUnit 测试为
  0 failures、0 errors、0 skipped，主 APK 与 androidTest APK 均生成。
- lint 为 2 errors、135 warnings；两个 error 仍是已有的 minSdk 24 / API 26
  `Process.waitFor(timeout, TimeUnit)` 兼容检查，没有新增 lint 类别。
- APK 为 8,709,676 字节，包名 `com.yinxing.launcher`、minSdk 24、targetSdk 36，v2 Debug 签名有效，
  只有一个 Android Debug 签名者。SDK 绝对路径执行 `adb devices -l` 没有发现连接设备。

## SHA-256

```text
8c3cc1d2179a378f528995b3bf572f699827d8e6e76c01779aece224a64f6dd3  yinxing-1.10.0-root-preview.27-debug.apk
```
