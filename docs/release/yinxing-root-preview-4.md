# 银杏 Root 自动化生命周期预览 4

本版面向中国版一加 15、ColorOS 16、KernelSU Root 专机，修复 Preview 3 在无障碍服务首次绑定或重连初始化窗口内提前收到请求时，可能访问未初始化计时器和 Kiosk 守卫的问题。服务实例现在只在完整连接初始化后发布，早到的请求留在队列中，早到的无障碍事件直接忽略。

Preview 3 的自动化会话代际保护、服务重连清理、Kiosk 拉回重试、Root Guard 保活、无障碍恢复和健康面板均保留。

## 资产

- `yinxing-1.10.0-root-preview.4-debug.apk`：绑定生命周期闸门和自动化修复的体验 APK。
- `yinxing-guard-1.10.0-root-preview.4.zip`：KernelSU Root Guard 模块，`versionCode=4`。
- `SHA256SUMS.txt`：两个文件的 SHA-256 校验值。

## 安装前注意

APK 使用构建机 Debug 签名，不是正式发布私钥签名。若手机上的银杏来自其他签名，Android 可能拒绝覆盖安装；请先备份联系人和设置，再决定是否清洁安装。KernelSU 模块可单独升级，模块与 APK 应保持同一预览号。

本版仍只针对 Android 用户 0 的固定 Root 专机。构建机没有连接目标一加 15；ColorOS 16 的实际授权弹窗、开机时序和厂商后台策略必须以真机体验为准。

## 安装与体验

1. 安装 APK，至少启动一次，并确认银杏仍是默认桌面。
2. 在 KernelSU 管理器中安装并启用 `yinxing-guard-1.10.0-root-preview.4.zip`。
3. 重启手机，确认桌面和无障碍服务由 Root Guard 自动恢复。
4. 从银杏发起一次微信视频自动化，分别体验刚开启无障碍后的立即请求、服务重新连接和紧接着发起第二次任务。
5. 在设置页打开“Root 专机状态”，确认健康检查与“立即修复并复查”仍然可用。

重点观察：服务刚开启或重连时发起请求不应崩溃；取消或重连后旧任务不应推进新任务；完成一次视频后，旧的浮层隐藏或扬声器补偿不应影响下一次任务。

## 安全边界

- APK 的 Root 调用仍仅允许模块提供的固定状态和修复入口。
- 自动化仍以无障碍语义节点、手势和全局动作作为主后端；本版没有引入任意坐标点击或任意 Root 命令。
- 回调、步骤超时、总超时和 Kiosk 拉回重试均绑定当前生命周期，失效任务会被丢弃。
- 服务未完成连接初始化时不发布可调用实例，避免外部请求触碰未初始化状态。

## 验证边界

发布前已执行宿主 Shell 与独立 BusyBox 模块测试、完整 Debug 单元/Smoke 测试、强制 Debug 构建、APK 签名/元数据检查和模块 ZIP 完整性检查；发布后会从 GitHub 下载远程资产复核。最终强制构建通过 `337` 个测试（`0` 跳过、`0` 失败、`0` 错误），Gradle 报告 `BUILD SUCCESSFUL in 1m 14s`，外部耗时 `74.90s`。真机侧尚未连接，OnePlus 15/ColorOS 16 的最终结果等待本次 Release 反馈。

## 回滚

1. 在 KernelSU 中禁用或卸载 `yinxing_guard`，然后重启。
2. 若需回退 APK，卸载 Preview 4 后安装上一版可用 APK；Root Guard 模块可暂时回退到 Preview 3。
3. 无法进入系统时，使用 KernelSU 的模块救援方式禁用 `yinxing_guard`。

## SHA-256

最终资产 SHA-256（与 `SHA256SUMS.txt` 一致）：

```text
3990343078ad18fc76213c9aaa69dc9809d478b3df23a5cd0364bec6590fac89  yinxing-1.10.0-root-preview.4-debug.apk
fb1f31a01d5c8e06c4cd5c80e166619f9b5e5f9b1bb5f31ea841af84339f0c24  yinxing-guard-1.10.0-root-preview.4.zip
```
