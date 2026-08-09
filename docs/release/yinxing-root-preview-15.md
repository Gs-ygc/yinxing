# 银杏 Root 增强 Preview 15

Preview 15 面向一加 15 中国版 ColorOS 16、KernelSU、已 Root 专机。它补上 Preview 14 的最后一个 HOME 可靠性缺口：Android HOME role 显示为银杏，并不必然代表按 Home 键实际会进入银杏。本版同时验证 role 持有者和 user 0 的 `MAIN` + `HOME` intent 解析结果。

## 发布内容

- `yinxing-1.10.0-root-preview.15-debug.apk`：银杏 Debug APK，`versionCode=31`。
- `yinxing-guard-1.10.0-root-preview.15.zip`：KernelSU Root Guard 模块，`versionCode=15`。
- `SHA256SUMS.txt`：两个发布资产的 SHA-256 校验值。

## Preview 15 变化

Root Guard 继续以 `cmd role get-role-holders --user 0 android.app.role.HOME` 读取 HOME role，并新增一个固定、只读且受既有 BusyBox 进程组超时边界保护的查询：

```text
cmd package resolve-activity --brief --components --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME
```

`home=owned` 现在只在 role 持有者是银杏，并且该固定 intent 实际解析到 `com.yinxing.launcher/.feature.home.MainActivity` 或等价的全限定类名时成立。role 为银杏但路由为其他桌面或无活动时，状态会降级为既有的 `other` 或 `none`；超时、失败、额外换行、`null`/`NULL`、非法包名、非法类名或多斜杠输出统一显示为 `unknown`，不会当成可写入的证据。

若 role 已由银杏持有而实际路由错误，Guard 只会调用既有固定 `set-home-activity` 命令修复，然后再次确认 role 和 route。此路径不会创建“模块接管”的回滚标记，因此不会把护理者原本手动选择银杏误写为模块所有权。新接管仍沿用 `pending` 事务证据，只有 role 和 resolver 同时确认后才升级为 `owned`，也才允许后续 HOME 启动；确认失败会保留证据并禁止启动。

独立卸载助手也使用相同的严格解析规则。恢复接管前桌面后，它会确认恢复后的 resolver 属于原桌面包；已知不一致、空结果、畸形或超时都保留 marker 和助手。若下一次运行时 role 已回到原桌面但路由仍明确指向银杏，助手会再尝试一次固定恢复；已知指向其他非银杏路由时保持照护者选择，不会强制覆盖。

状态协议仍是九行 schema 2，APK Root 白名单也仍只有原来的三个固定、无参数模块路径。没有新增任意 shell、坐标点击、私有 ColorOS API、任意包名或任意组件输入。

该固定命令的参数和输出形式基于 AOSP 的 [`resolve-activity` 与 `set-home-activity` 实现](https://android.googlesource.com/platform/frameworks/base/+/master/services/core/java/com/android/server/pm/PackageManagerShellCommand.java)；没有依赖 ColorOS 私有接口。

## 安装顺序

1. 在 KernelSU 安装并启用 `yinxing-guard-1.10.0-root-preview.15.zip`；若要求重启，先重启让模块生效。
2. 覆盖安装 `yinxing-1.10.0-root-preview.15-debug.apk`。
3. 打开银杏的 Root 增强状态并执行一次修复复查，确认“桌面”正常。
4. 按 Home 键确认实际回到银杏，再重启一次，复查 HOME、无障碍和守护状态。

模块启用期间会持续恢复银杏的 HOME 路由，这是专机最高可靠性模式的预期行为。该 APK 是 Debug 包，不应当作为生产签名发布物分发。

## 回滚

1. 在 KernelSU 完整卸载 Preview 15 模块，不要立刻安装旧模块。
2. 按 KernelSU 提示重启，让独立清理脚本在旧模块重新出现前恢复接管前桌面和 Doze 状态。
3. 确认 Home 键实际回到原桌面后，再安装 Preview 14 或其他旧模块并重启。
4. APK 可用旧版 Debug 包覆盖；若系统拒绝低版本覆盖，按设备允许的降级安装方式处理。

Preview 14 Release：<https://github.com/Gs-ygc/yinxing/releases/tag/v1.10.0-root-preview.14>

## 验证记录

最终发布前会重新执行完整 Host/BusyBox Shell 矩阵、强制 Android 单元测试与 Debug 构建、确定性模块打包、APK 元数据/签名检查，以及远端发布资产的字节和 SHA-256 复核。最终命令耗时和校验值记录在本文件的发布提交中。

本 Preview 尚未连接真实一加 15；不会把本地模拟或 AOSP 命令验证表述为 ColorOS 16 真机验证。真机体验应重点确认 ColorOS 的 resolver 输出、接管后 Home 键路由、模块卸载后的原桌面恢复、无障碍绑定和重启保活。
