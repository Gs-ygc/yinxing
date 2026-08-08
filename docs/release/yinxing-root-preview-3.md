# 银杏 Root 自动化生命周期预览 3

本版面向中国版一加 15、ColorOS 16、KernelSU Root 专机，重点修复无障碍微信自动化在服务重连、任务取消和连续任务切换时的旧回调串入问题。Root Guard 的保活、无障碍恢复和健康面板保持不变。

## 资产

- `yinxing-1.10.0-root-preview.3-debug.apk`：包含自动化生命周期修复的体验 APK。
- `yinxing-guard-1.10.0-root-preview.3.zip`：KernelSU Root Guard 模块。
- `SHA256SUMS.txt`：两个文件的 SHA-256 校验值。

## 安装前注意

APK 使用构建机 Debug 签名，不是正式发布私钥签名。若手机上的银杏来自其他签名，Android 可能拒绝覆盖安装；请先备份联系人和设置，再决定是否清洁安装。KernelSU 模块可单独升级，模块与 APK 应保持同一预览号。

本版仍只针对 Android 用户 0 的固定 Root 专机。构建机没有连接目标一加 15；ColorOS 16 的实际授权弹窗、开机时序和厂商后台策略必须以真机体验为准。

## 安装与体验

1. 安装 APK，至少启动一次，并确认银杏仍是默认桌面。
2. 在 KernelSU 管理器中安装并启用 `yinxing-guard-1.10.0-root-preview.3.zip`。
3. 重启手机，确认桌面和无障碍服务由 Root Guard 自动恢复。
4. 从银杏发起一次微信视频自动化，分别体验取消、服务重新连接和紧接着发起第二次任务。
5. 在设置页打开“Root 专机状态”，确认健康检查与“立即修复并复查”仍然可用。

重点观察：取消或服务重连后，旧任务不应推进新任务；完成一次视频后，旧的浮层隐藏或扬声器补偿不应影响下一次任务。

## 安全边界

- APK 的 Root 调用仍仅允许模块提供的固定状态和修复入口。
- 自动化仍以无障碍语义节点、手势和全局动作作为主后端；本版没有引入任意坐标点击或任意 Root 命令。
- 回调、步骤超时、总超时和 Kiosk 拉回重试均绑定当前生命周期，失效任务会被丢弃。

## 验证边界

发布前已执行宿主 Shell 与独立 BusyBox 模块测试、完整 Debug 单元/Smoke 测试、强制 Debug 构建、APK 签名/元数据检查和模块 ZIP 完整性检查；发布后还会下载远程资产复核。最终强制构建通过 `335` 个测试（`0` 跳过、`0` 失败、`0` 错误），耗时 `75.75s`。真机侧尚未连接，OnePlus 15/ColorOS 16 的最终结果等待本次 Release 反馈。

## 回滚

1. 在 KernelSU 中禁用或卸载 `yinxing_guard`，然后重启。
2. 若需回退 APK，卸载 Preview 3 后安装上一版可用 APK；Root Guard 模块可暂时保留或一并回退到 Preview 2。
3. 无法进入系统时，使用 KernelSU 的模块救援方式禁用 `yinxing_guard`。

## SHA-256

最终资产 SHA-256（与 `SHA256SUMS.txt` 一致）：

```text
80314d0f04a5ef7fd22f2a305c67dda21966a4b766cdf1a1d0f6de1675b8a835  yinxing-1.10.0-root-preview.3-debug.apk
d7be48a9ba8ee3064328d54ca36dff9e326902cf28cd6dceae402d773ea0bd26  yinxing-guard-1.10.0-root-preview.3.zip
```
