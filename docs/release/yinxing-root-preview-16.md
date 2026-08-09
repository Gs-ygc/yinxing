# 银杏 Root 增强 Preview 16

Preview 16 面向一加 15 中国版 ColorOS 16、KernelSU、已 Root 专机。它处理一个实际的无障碍可靠性缺口：ColorOS 可能长期把银杏服务留在 `Binding services`，而一次读取会被误认为已恢复。本版增加跨健康周期的证据、有限重绑定和可观察的降级状态。

## 发布内容

- `yinxing-1.10.0-root-preview.16-debug.apk`：银杏 Debug APK，`versionCode=32`。
- `yinxing-guard-1.10.0-root-preview.16.zip`：KernelSU Root Guard 模块，`versionCode=16`。
- `SHA256SUMS.txt`：两个二进制资产的 SHA-256 校验值。

## Preview 16 变化

Root Guard 仍只使用既有的固定 Root 路径和 Android 命令。无障碍状态正常为 `bound` 时会清除诊断证据；首次启用后处于 `binding` 不会立即再次切换设置。只有在服务已经完整启用、并在两个健康周期连续观察到 `Binding services` 后，才会复用已经验证过的定向 remove/restore 重绑定。

证据保存在 Root-only 的：

```text
/data/adb/yinxing_guard/accessibility_binding_stall
binding|<boot-id>|<observations>|<rebind-attempts>
```

默认阈值是 2 次观测，每次启动最多 2 次重绑定。跨启动会重置预算；重绑定后仍在 binding 时会等待新的两个周期窗口，不会每分钟反复写设置。达到上限后本轮修复失败、状态输出为 `accessibility=stale`，但不会继续发第三次设置切换。稍后如果系统真正进入 `Bound services`，证据会被清除并恢复正常路径。

marker 使用临时文件、0600 权限、读回校验和同步；畸形文件、额外换行、非法 boot id、目录或 symlink 都会 fail-closed，绝不覆盖或猜测性修改无障碍设置。现有的 `accessibility_transaction` 仍是唯一的设置回滚证据，卸载只移除新的诊断 marker，不会因为它单独改变用户无障碍配置。

状态协议仍为九行 schema 2，APK Root 白名单仍只有 `status.sh`、`action.sh`、`kiosk-home.sh` 三个无参数路径。没有新增任意 shell、坐标点击、进程杀除、私有 ColorOS API、任意包名或任意组件输入。

## 安装顺序

1. 在 KernelSU 安装并启用 `yinxing-guard-1.10.0-root-preview.16.zip`；若系统要求重启，先重启让模块生效。
2. 覆盖安装 `yinxing-1.10.0-root-preview.16-debug.apk`。
3. 打开银杏 Root 增强状态并执行一次修复复查。首次启用或服务刚重启时，看到 `binding` 属于正常异步窗口。
4. 按 Home 键、打开一次自动化点击入口，再重启一次，复查 HOME、无障碍和守护状态。

模块启用期间会持续恢复银杏的 HOME 路由，这是专机高可靠模式的预期行为。该 APK 是 Debug 包，不是生产签名发布物。

## 回滚

1. 在 KernelSU 完整卸载 Preview 16 模块，不要立刻安装旧模块。
2. 按 KernelSU 提示重启，让独立清理脚本恢复接管前的桌面、Doze 和无障碍事务状态。
3. 确认 Home 键回到原桌面后，再安装 Preview 15 或其他旧模块并重启。
4. APK 可用旧版 Debug 包覆盖；若系统拒绝低版本覆盖，按设备允许的降级安装方式处理。

Preview 15 Release：<https://github.com/Gs-ygc/yinxing/releases/tag/v1.10.0-root-preview.15>

## 验证记录

- 所有 KernelSU Shell 脚本通过 `sh -n` 和 standalone BusyBox `ash -n`；固定命令扫描确认 Root bridge 未扩权。
- `bash tools/test-yinxing-guard.sh all` 退出码为 0，包含 host 与递归 BusyBox harness，共 372 个 PASS；耗时和构建记录在发布后补入本节。
- Android 单元测试、强制 Debug 构建、APK metadata/signature、确定性 KernelSU ZIP 和新下载校验记录在发布后补入本节。
- 当前环境没有连接真实一加 15；不会把本地 fixture 或 AOSP 行为表述为 ColorOS 16 真机验证。

## SHA-256

发布资产构建完成后以 `sha256sum -c SHA256SUMS.txt` 为准，并在此处同步记录 APK、KernelSU ZIP 和 GitHub Release URL。
