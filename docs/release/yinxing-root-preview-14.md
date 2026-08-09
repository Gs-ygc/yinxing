# 银杏 Root 增强 Preview 14

Preview 14 面向一加 15 中国版 ColorOS 16、KernelSU、已 Root 专机，把“银杏能启动”提升为“系统 HOME 角色由银杏持有”。Root Guard 现在会持续校验默认桌面、自动接管异常 HOME 状态，并在卸载模块时有条件恢复接管前的桌面。

## 发布内容

- `yinxing-1.10.0-root-preview.14-debug.apk`：银杏体验 APK，`versionCode=30`。
- `yinxing-guard-1.10.0-root-preview.14.zip`：KernelSU Root Guard 模块，`versionCode=14`。
- `SHA256SUMS.txt`：两个资产的 SHA-256 校验值，仅使用资产文件名。

## Preview 14 变化

Root Guard 现在把一次无障碍、HOME、Doze 修复和一次完整卸载清理放进同一个带 boot ID、PID 与进程启动时间校验的事务锁。第二个 Guard、手动动作、卸载钩子或开机清理遇到正在执行的事务时会直接失败并保留清理助手，不会在首个所有权标记尚未发布时删除状态，也不会在 Doze 添加尚未返回时抢先清理。

HOME 接管使用两个职责分离的持久证据：`home_previous_holder` 只记录模块首次接管前的原桌面，`home_takeover_state` 记录 `pending|boot|本次接管前桌面`、`owned` 或 `released` 阶段。每个文件均为 `0600` 普通文件，并在变更 Android 状态前通过受超时控制的 `sync -f` 同步文件和目录。`pending` 发布后会再读取一次当前 HOME；护理者若在标记同步期间改选桌面，本轮立即释放未生效证据，绝不会执行接管。只有当前持有者连续通过严格单行、单包名校验且模块仍启用，才调用固定的 `com.yinxing.launcher/.feature.home.MainActivity`，随后查询确认并转为 `owned`。原本就由护理者手动选择银杏时不会伪造模块所有权。

无障碍首次启用和崩溃重绑都采用 compare-before-compensate。模块会保留其他无障碍服务，只在观察值仍等于本次事务写入值时撤销；护理者期间写入的新服务列表始终保留，同时仍会恢复本事务打开的全局 `accessibility_enabled` 开关。写设置前会同步一条严格的 `accessibility_transaction` 日志，记录原始/临时开关以及原始、目标和重绑中间服务列表。解析器拒绝 `null`、`NULL` 和空白别名，以及会把这些 sentinel 伪装成派生中间列表的记录，确保恢复前不写入设置。即时补偿失败、进程退出或模块被移除时，后续 Guard 或独立卸载助手会继续恢复；只有服务列表与全局开关都已确认安全，才删除日志。仅全局开关需要恢复时不会重复写服务列表。

Doze 所有权也分为 `pending|boot` 和 `added`。模块先同步 `pending`，再执行白名单添加，并无论客户端返回码如何都重新查询系统实际状态：已生效则转为 `added`，同一启动周期内状态不确定则禁止重复添加和 AppOps，跨启动周期才重新基线。卸载助手在同一事务锁内查询、删除并再次确认；命令报错但删除已生效时可安全结束，未确认时保留标记和助手重试。

模块在命令执行期间收到 KernelSU 的 `disable` 或 `remove` 标记时，会在每个只读探针和写入事务边界重新检查状态并停止后续无障碍、HOME、Doze、AppOps 和桌面启动动作。如果停用恰好发生在 HOME 接管命令内部，模块只在确认当前 HOME 仍是自己时恢复本次接管前最后确认的桌面；接管前没有持有者则移除银杏的 HOME 角色，期间出现的护理者新选择始终优先。回滚失败、命令超时或系统服务延迟完成时保留事务证据，由独立助手继续处理。

状态协议升级为严格 schema 2，在模块、守护、无障碍、省电、清理和上次修复之外新增 `home=owned|other|none|unknown`。Preview 14 APK 仍能解析 Preview 13 的 schema 1，但会把 HOME 显示为“未知”并保持降级；只有 schema 2 且 `home=owned` 才能显示整体健康。设置页 Root 状态摘要新增“桌面”维度。

卸载模块时不会直接抢占正在运行的修复，而是先取得共享事务锁，再根据持久证据安装或保留独立开机清理脚本。清理脚本只接受内容精确、普通文件形态的无障碍、HOME 和 Doze 状态；目录、符号链接、悬空链接或畸形内容都会保留证据和助手并停止对应变更。仅当当前 HOME 仍是银杏时才恢复本次应回滚的桌面；护理者已选择其他桌面时只释放证据。恢复包缺失、角色命令失败、未确认生效或命令超时时都会在下次开机重试。无障碍、HOME 与 Doze 可分别完成，但助手仅在所有剩余证据都安全清除后自删除。

标准命令依据 AOSP 当前实现：[`cmd package set-home-activity`](https://android.googlesource.com/platform/frameworks/base/+/master/services/core/java/com/android/server/pm/PackageManagerShellCommand.java) 接受包名或完整组件并通过 HOME role 设置默认桌面；[`cmd role`](https://android.googlesource.com/platform/packages/modules/Permission/+/refs/heads/main/PermissionController/src/com/android/permissioncontroller/role/Role.md) 提供按用户查询、添加和移除角色持有者。没有使用 ColorOS 私有接口。

APK 的 Root 调用白名单保持不变，只允许三个固定、无参数的模块路径：`/data/adb/modules/yinxing_guard/bin/status.sh`、`/data/adb/modules/yinxing_guard/action.sh` 和 `/data/adb/modules/yinxing_guard/bin/kiosk-home.sh`。没有增加任意 shell、坐标点击、任意包名/组件输入或系统进程选择。模块内恢复目标只能来自 root 状态目录中经过严格包名验证的接管前标记，所有 Android 命令继续受 Preview 13 的固定超时与进程组清理边界约束。

## 安装顺序

1. 在 KernelSU 中先安装并启用 `yinxing-guard-1.10.0-root-preview.14.zip`。如果 KernelSU 要求重启，先重启让模块生效。
2. 再安装 `yinxing-1.10.0-root-preview.14-debug.apk`，覆盖 Preview 13 时使用升级安装。
3. 启动银杏，进入 Root 增强状态执行一次检查；“桌面”应显示“正常”。如有异常，执行“立即修复并复查”。
4. 按 Home 键确认系统返回银杏，再重启一次验证 HOME、无障碍和守护状态仍然在线。

模块启用期间会持续把 HOME 恢复为银杏，这是专机最高可靠性模式的预期行为。禁用或开始移除模块后，正在运行的 Guard 和手动动作都会停止后续接管；若要恢复接管前桌面，需要完整卸载模块并按下面步骤重启一次。

这是 Debug APK，安装时可能受到设备现有签名策略限制；不要把它当作生产 Release 包分发。

## 回滚

必须先完整卸载 Preview 14 模块，再降级模块。仅在 KernelSU 中禁用 Preview 14 会停止后续强制修复，但不会立即恢复接管前的 HOME。

1. 在 KernelSU 中卸载 Preview 14 模块，不要马上安装旧模块。
2. 按 KernelSU 提示重启一次，让独立清理脚本在旧模块尚未重新出现时恢复接管前的桌面和 Doze 状态。
3. 确认 Home 键已回到原桌面后，再安装 Preview 13 模块并按提示重启。
4. APK 可用 Preview 13 Debug 包覆盖安装；若系统拒绝低版本覆盖，使用设备允许的降级安装方式或先卸载当前 APK。

Preview 13 Release：<https://github.com/Gs-ygc/yinxing/releases/tag/v1.10.0-root-preview.13>

## 验证记录

- 环境：Gradle 9.3.1、OpenJDK 21、Android SDK Build Tools 36.0.0、BusyBox 1.36.1；Root 模块最终源码提交 `e5f049e`。
- `bash tools/test-yinxing-guard.sh all`：主机 Shell、递归 BusyBox ash 和两次确定性模块打包均通过，耗时 2m38.516s。
- 新增模块回归覆盖：完整修复锁与卸载锁并发、HOME 首标记尚未发布时卸载、Doze 添加执行中卸载、HOME `pending/owned/released` 同/跨启动恢复、`pending` 发布期间护理者改选、无障碍首次写入和重绑的已生效报错、护理者服务列表与全局开关组合变化、即时补偿失败后的跨进程卸载恢复、仅全局开关恢复不重复写服务列表，以及包含 `null`/`NULL` 和嵌入式 sentinel 的畸形事务日志保留。原有 HOME/Doze/AppOps 生命周期、严格包名/单行解析、命令超时、非普通标记和双向独立重试覆盖继续通过。
- Bash/BusyBox ash 语法、固定 Android 命令包装扫描、旧版本残留扫描和 `git diff --check` 均通过。
- `:app:testDebugUnitTest :app:assembleDebug --rerun-tasks --no-daemon`：48 个 Gradle 任务全部重新执行，353 项测试、0 失败、0 错误、0 跳过，耗时 1m23.010s。
- APK `aapt2 dump badging`：包名 `com.yinxing.launcher`、`versionCode=30`、`versionName=1.10.0-root-preview.14`、min SDK 24、target/compile SDK 36。
- `apksigner verify --verbose`：APK Signature Scheme v2 验证通过，1 个 signer。
- KernelSU ZIP：11 个条目位于归档根目录，脚本均为可执行权限，时间戳归一化为 1980-01-01 00:00:00，重复打包字节一致。

## SHA-256

```text
72cb2467132cbd9871ebd65903f3476be6cdeaa42a5349c56a26ebea7a89f136  yinxing-1.10.0-root-preview.14-debug.apk
a07b8ee536e96191af1340b68ac47eee3e53f6ed64229b93de4282da7626b562  yinxing-guard-1.10.0-root-preview.14.zip
```

本 Preview 未连接真实一加 15，未执行 ColorOS 16 真机验证。SDK `adb devices -l` 当前为空；发布资产用于专机体验。真机验收需要继续确认 ColorOS 的 HOME role 输出、接管后 Home 键路由、模块卸载后的原桌面恢复、无障碍绑定状态和重启保活。
