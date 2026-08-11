# 银杏 Root 恢复 Preview 26

Preview 26 修复一加 15 / 中国版 ColorOS 16 / KernelSU 专机上已经确认的 Root 故障：旧模块虽然
在 ZIP 中把脚本标成可执行，KernelSU 安装时仍会把普通文件统一重置为 `0644`。旧模块没有在安装
结束后恢复权限，因此状态、立即修复、HOME 接管脚本会出现退出码 `126 Permission denied`，开机
守护脚本也可能根本没有启动。

本版必须同时安装新的 KernelSU 模块和 APK。只覆盖 APK 不能修复已经安装的 Preview 18 模块。

## 发布内容

- `yinxing-1.10.0-root-preview.26-debug.apk`：银杏 Debug APK，`versionCode=42`，
  `versionName=1.10.0-root-preview.26`。
- `yinxing-guard-1.10.0-root-preview.26.zip`：Root Guard 模块，`versionCode=26`。
- `SHA256SUMS.txt`：以上两个文件的 SHA-256 校验值。

## Root 修复

- 新增 KernelSU 官方支持的 `customize.sh`。KernelSU 完成默认权限重置后，该脚本通过安装器提供的
  `set_perm`，把银杏的 `service.sh`、`action.sh`、卸载脚本和全部固定 `bin/*.sh` 恢复为 `0755`。
- 任一权限恢复失败会直接中止模块安装并显示具体脚本名，不会留下一个看似安装成功、实际无法运行
  的半成品模块。
- 打包测试现在模拟 KernelSU 的真实顺序：先把目录设为 `0755`、文件设为 `0644`，再用 BusyBox
  `ash` 独立模式加载 `customize.sh`，最后逐个验证所有脚本可执行；同时验证 `set_perm` 失败会中止。
- APK 继续使用 KernelSU 当前源码定义的固定兼容入口 `/system/bin/su`。没有改成 PATH 猜测，也没有
  增加任意命令、轮询、服务、唤醒锁或新的空闲功耗来源。

## `su 入口不可见` 与 `126` 是两件事

- `126 Permission denied` 是本版已经修复的模块脚本安装权限缺陷，需要安装新模块并重启。
- `su 入口不可见` 表示银杏当前 UID 看不到 KernelSU 的 `/system/bin/su` 兼容入口。KernelSU 会对未
  授权 UID 主动隐藏该入口；模块不能绕过 KernelSU 管理器替 APK 静默授权。
- 如果安装新模块后仍显示 `su 入口不可见`，必须在 KernelSU 管理器中给“银杏”当前 UID 开启 Root，
  保持默认完整 Root Profile，并确认 su 兼容功能已启用。银杏详情页会显示要核对的 UID。
- 其他脚本缺失、脚本不可用、权限拒绝、超时、非零退出码、输出过长或状态格式错误仍分别显示，
  不会重新合并成笼统的“Root 不可用”。

## 安装与验证顺序

1. 下载本 Release 的 APK、模块 ZIP 和 `SHA256SUMS.txt`，核对校验值。
2. 在 KernelSU 管理器中安装 `yinxing-guard-1.10.0-root-preview.26.zip`，确认模块已启用，然后重启
   手机。不要继续沿用或重新安装 Preview 18 模块。
3. 覆盖安装 Preview 26 APK。APK 使用与前几版相同的 Android Debug 签名，正常覆盖时 UID 应保持
   不变。
4. 在 KernelSU 管理器的超级用户/App Profile 中找到“银杏”，给详情页显示的当前 UID 开启 Root；
   Root Profile 使用默认的 UID/GID 0 和完整能力，不要改成 shell 或受限 Profile。
5. 打开“家属设置 → Root 专机”。预期不再出现脚本 `126`；状态应能读出模块版本、守护、无障碍、
   HOME、前台确认、省电、清理和上次修复。若仍是 `su 入口不可见`，先复核第 4 步和 su 兼容开关。
6. 点一次“立即修复并复查”，确认没有权限拒绝；随后回到老人桌面，验证 HOME、无障碍和应用入口。
7. 再重启一次，确认银杏 HOME 和无障碍自动恢复。记录首次可操作时间及一晚待机耗电；当前本地环境
   没有连接一加 15，因此这些真机结果等待本次体验反馈。

## 回滚

- APK 可回到 [Preview 25](https://github.com/Gs-ygc/yinxing/releases/tag/v1.10.0-root-preview.25)，
  但 Android 通常不允许直接覆盖更低 `versionCode`，需要先按专机维护流程备份配置。
- 回滚 APK 时可以保留 Preview 26 模块；它没有扩大 Root 行为，只修正旧模块本应具有的脚本权限。
- 不建议回滚到 Preview 18 模块，因为它就是本次 `126` 的来源。若必须停用 Root 接管，请在
  KernelSU 管理器中停用或卸载 Preview 26 模块并重启，让模块既有卸载流程恢复其拥有的状态。

## 本地验证记录

- 安装权限 RED 在旧模块形态下稳定失败；修复后包测试通过。审查补充的 BusyBox `ash` 和失败中止
  覆盖经过 mutation 检查，移除 `abort` 时测试会按预期失败；恢复后复审无剩余问题。
- Root Guard 完整宿主测试分别在 POSIX `sh` 和 BusyBox `ash` 下通过，覆盖保活、无障碍恢复、HOME
  所有权、固定 Kiosk 命令、并发保护和卸载回滚。
- 最终源码强制执行 80 个 Android 任务并全部通过，外部耗时 101.52 秒；505 个 JUnit 测试为
  0 failures、0 errors、0 skipped，主 APK 与 androidTest APK 均成功生成。
- lint 仍为 2 errors、135 warnings；两个 error 均是此前已有的 Android 7 API 24/26
  `Process.waitFor` 兼容检查，本版没有修改该 runner，也没有新增 lint error。
- APK 大小 8,705,668 字节，包名 `com.yinxing.launcher`、targetSdk 36，v2 签名有效、一个 Android
  Debug 签名者。模块大小 27,047 字节，ZIP 完整、时间戳规范化、重复打包逐字节一致。
- SDK 绝对路径执行 `adb devices -l` 没有发现连接设备；本版不宣称真机 Root 已恢复。

## SHA-256

```text
93901417c938442bc946d934b86141b5de5beb44c9e9fad338d29feb869ec94f  yinxing-1.10.0-root-preview.26-debug.apk
96f243ed79bf7216a1576fdd64ba1943dd5125e07d83750ed19bca56c53b7cf9  yinxing-guard-1.10.0-root-preview.26.zip
```
