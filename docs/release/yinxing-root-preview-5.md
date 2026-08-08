# 银杏 Root 自动化生命周期预览 5

本版面向中国版一加 15、ColorOS 16、KernelSU Root 专机，修复 Root Guard 在晚启动阶段首次修复失败后永久退出的问题。监督循环现在会在非锁冲突错误后自动退避重启现有 Guard；模块被禁用或标记卸载时会停止，不会反复拉起。

Preview 4 的服务连接闸门、自动化会话代际保护、服务重连清理、Kiosk 拉回重试、无障碍恢复和健康面板均保留。

## 资产

- `yinxing-1.10.0-root-preview.5-debug.apk`：包含 Root Guard 监督修复的体验 APK。
- `yinxing-guard-1.10.0-root-preview.5.zip`：KernelSU Root Guard 模块，`versionCode=5`。
- `SHA256SUMS.txt`：两个文件的 SHA-256 校验值。

## 安装前注意

APK 使用构建机 Debug 签名，不是正式发布私钥签名。若手机上的银杏来自其他签名，Android 可能拒绝覆盖安装；请先备份联系人和设置，再决定是否清洁安装。KernelSU 模块可单独升级，模块与 APK 应保持同一预览号。

本版仍只针对 Android 用户 0 的固定 Root 专机。构建机没有连接目标一加 15；ColorOS 16 的实际授权弹窗、开机时序和厂商后台策略必须以真机体验为准。

## 安装与体验

1. 安装 APK，至少启动一次，并确认银杏仍是默认桌面。
2. 在 KernelSU 管理器中安装并启用 `yinxing-guard-1.10.0-root-preview.5.zip`。
3. 重启手机，确认桌面和无障碍服务由 Root Guard 自动恢复。
4. 在开机后较早阶段发起一次视频自动化，或先暂时关闭网络/延迟微信可用性，观察 Root Guard 是否会在首次修复失败后再次尝试。
5. 在设置页打开“Root 专机状态”，确认健康检查与“立即修复并复查”仍然可用。
6. 在 KernelSU 中禁用模块，确认监督循环停止；重新启用后重启，确认恢复链重新建立。

重点观察：短暂的包管理或安全设置不可用不应让 Root Guard 永久沉默；模块禁用/卸载后不应被旧进程重新拉起；自动化取消、服务重连和连续任务切换的旧回调仍不应影响新任务。

## 安全边界

- 监督器只重启现有固定 `guard.sh`，不增加任意 Root shell、坐标点击或新的包白名单。
- 监督器只使用模块目录状态、固定日志和数字退避；所有 Root 操作仍由现有 `repair_state`、健康检查和固定 HOME 组件完成。
- `guard.sh` 的每启动锁、卸载清理和 Doze 所有权语义保持不变。
- 模块存在 `disable` 或 `remove` 标记时，监督器不会启动或重启 Guard。

## 验证边界

发布前已执行宿主 Shell 与独立 BusyBox 模块测试、完整 Debug 单元/Smoke 测试、强制 Debug 构建、APK 签名/元数据检查和模块 ZIP 完整性检查；真机侧尚未连接。最终强制构建通过 `337` 个测试（`0` 跳过、`0` 失败、`0` 错误），Gradle 报告 `BUILD SUCCESSFUL in 1m 27s`，外部耗时 `88.26s`。

## 回滚

1. 在 KernelSU 中禁用或卸载 `yinxing_guard`，然后重启。
2. 若需回退 APK，卸载 Preview 5 后安装上一版可用 APK；Root Guard 模块可回退到 Preview 4。
3. 无法进入系统时，使用 KernelSU 的模块救援方式禁用 `yinxing_guard`。

## SHA-256

最终资产 SHA-256（与 `SHA256SUMS.txt` 一致）：

```text
d72a74dfd48fcae4c6a0eb82b63e013f28a13efed188d4953c6811e3088d64b4  yinxing-1.10.0-root-preview.5-debug.apk
885e5c7cd74033a23b74b081f186ea08ddc6f4c056e5eb46afd61d40262a7b9b  yinxing-guard-1.10.0-root-preview.5.zip
```
