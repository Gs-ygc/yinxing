# 银杏老年体验 Preview 24

Preview 24 处理两条真实体验反馈：老人点击首页应用后失败时，不再只看到一闪而过的 Toast；
家属检查 Root 时，也不再只看到无法排障的“Root 不可用”。首页失败改成可持续、可恢复的大按钮
对话框；Root 卡片按实际执行层显示 `su` 入口、权限拒绝、脚本、超时、退出码或格式错误。成功打开
应用的路径保持原样，Root 检查仍只在家属主动打开面板时执行。目标设备仍是一加 15 中国版
ColorOS 16、KernelSU、已 Root 的受控专机；本版不修改 Root Guard 模块或 BusyBox。

## 发布内容

- `yinxing-1.10.0-root-preview.24-debug.apk`：银杏 Debug APK，`versionCode=40`，
  `versionName=1.10.0-root-preview.24`。
- `SHA256SUMS.txt`：本版 APK 的 SHA-256 校验值。
- KernelSU Root Guard：模块源码、脚本和元数据均未修改，继续使用
  [Preview 18 模块](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.18/yinxing-guard-1.10.0-root-preview.18.zip)。

## 老年主路径变化

- 首页应用找不到、被停用或启动异常时，显示标题“无法打开 <应用名>”和不暴露包名/异常堆栈的
  中性说明；对话框不会自动消失，避免老人错过结果。
- `再试一次` 使用原有首页应用启动器，失败后释放原有 1.2 秒重复点击闸门；应用恢复可用后，
  下一次点击可以直接启动。
- `请家属检查设置` 直接进入银杏现有设置页。应用条目不会被自动删除、禁用、重排或改写，
  家属仍拥有最终决定权。
- 两个操作按钮均为至少 `68dp` 的稳定大目标，带可见文字和无障碍描述；Activity 销毁时会
  清理暂时性对话框，避免旋转或退出后残留窗口。
- 成功解析和 `startActivity` 路径没有新增延迟、动画、轮询、协程或网络请求，因此成功点击的
  感知延时和空闲功耗边界不变。

## Root 排障变化

- APK 不再通过 `PATH` 猜测 `su`，而是按 KernelSU 官方兼容入口直接执行
  `/system/bin/su -c /data/adb/modules/yinxing_guard/bin/status.sh`。
- Root 卡片徽章会分别显示 `su 入口不可见`、`su 被阻止`、`su 启动失败`、`权限被拒绝`、
  `缺少脚本`、`脚本不可用`、`脚本被阻止`、`检查超时`、`命令失败`、`输出异常` 或 `格式异常`；
  有效状态中的“模块未安装”仍独立显示。
- 详情会给出对应处理动作。普通非零失败保留退出码；`su` 入口不可见时显示银杏当前 UID，方便
  家属在 KernelSU 管理器核对授权。
- KernelSU 未授权当前 UID 时，内核不会对该应用接管 `/system/bin/su`，应用侧可能同样观察到
  “文件不存在”。因此银杏会明确提示这种可能，不会把它伪装成已经证明的结论。
- 合并输出中的普通 `permission denied` 可能来自 Root Profile、SELinux、脚本或依赖，银杏只显示
  “权限被拒绝”和退出码；脚本内部的 `not found` 也不会被误报成固定 Guard 脚本缺失。
- Android shell 的 `inaccessible or not found` 可能同时表示路径缺失或权限遮蔽，银杏单列为
  “脚本不可用”，并明确保留这两种可能。
- 点击“立即修复并复查”后，如果固定修复脚本失败，Toast 现在显示该动作自己的具体原因；随后
  仍按原逻辑读取一次最新健康状态。

## 自启动、低功耗与 Root 边界

- 本版没有新增 Activity、服务、Receiver、定时器、轮询、网络请求、唤醒锁、额外 Root 探针、
  无障碍命令或 KernelSU 资产；不会因为本版增加新的常驻后台耗电来源。
- KernelSU 模块、BusyBox、HOME 接管、开机恢复、Doze 白名单和无障碍恢复逻辑与 Preview 23
  相同。APK 只修改既有 Root 健康查询的入口明确性、结果分类和 UI；`root/` 模块目录未修改。
- 本地 JVM/Robolectric 和 APK 构建不能证明 ColorOS 16 真机的接管延时、自启动、保活、无障碍
  恢复或功耗；这些结论只接受一加 15 实机证据。

## 安装与体验顺序

1. 下载并覆盖安装本 Release 的 APK。APK 使用与前几版相同的 Android Debug 签名。
2. 保持 Preview 18 KernelSU 模块启用；本版不需要重装或升级模块。
3. 打开“家属设置 → Root 专机”，确认徽章不再笼统显示“Root 不可用”。若显示 `su 入口不可见`，
   用详情里的 UID 在 KernelSU 管理器中核对银杏授权；授权后返回银杏重新检查。
4. 临时停用 Root Guard 模块后重新检查，确认有效状态显示“需要处理”（模块为待处理），而不是
   错报成授权失败或脚本缺失；随后重新启用模块并重启。
5. 在银杏首页保留一个已卸载、停用或暂时不可启动的应用入口，点击一次，确认对话框持续显示，
   且老人能读到应用名和下一步。
6. 重新启用/安装该应用后点击 `再试一次`，确认对话框关闭并进入同一个应用；快速重复点击不应
   造成多次启动。
7. 再制造一次失败，点击 `请家属检查设置`，确认进入银杏设置页；返回首页后检查应用条目仍在，
   没有被自动删除或重排。
8. 用系统大字体和 TalkBack 重走一次失败、重试和设置路径；随后重启专机，记录首页首次可操作
   时间、无障碍恢复结果和一晚待机耗电，作为本版真机反馈。

## 回滚

1. 安装 [Preview 23 APK](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.23/yinxing-1.10.0-root-preview.23-debug.apk)。
2. KernelSU 模块继续保持 Preview 18；本版没有模块状态需要回退。
3. 若系统拒绝覆盖安装，按专机维护流程备份配置后卸载体验 APK，再安装 Preview 23。

## 本地验证记录

- 强制执行 `:app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest
  --rerun-tasks --no-daemon --console=plain`：80/80 任务成功，外部耗时 97.39 秒；59 份
  JUnit XML 共 462 tests、0 failures、0 errors、0 skipped，主 APK 与 androidTest APK 均生成。
- Preview24 聚焦回归：Home 应用失败恢复、首页 smoke、电话启动回退共 32 个测试通过，最近一次
  Gradle 执行耗时 23 秒；Task 2 独立审查结论为无发现、Ready。
- `:app:lintDebug` 退出码 1，报告 2 个继承自 Preview 23、逻辑未改动的
  `RootCommandRunner.kt:106`、`:184` API 26 `NewApi` errors 和 135 warnings；没有新增 Root 诊断
  lint 项。lint 外部耗时 109.57 秒。
- Root/设置聚焦回归共 62 tests、0 failures、0 errors、0 skipped，Gradle 外部耗时 35.71 秒；覆盖
  `/system/bin/su`、权限来源不明、固定脚本缺失/被阻止/二义不可用、内部依赖缺失、超时、输出上限、
  退出码、状态格式和修复动作失败原因。
- 两轮独立审查先发现并推动修正了宽泛的授权/`not found` 推断以及 Android shell 的
  `inaccessible or not found` 二义性；最终复核无阻塞代码发现。
- `git diff --check` 通过；源代码差异没有进入 `root/` KernelSU module、manifest、service 或
  background scheduling。APK Root 代码的变化只处理既有命令的入口和结果诊断。
- `aapt2` 确认包名 `com.yinxing.launcher`、`versionCode=40`、
  `versionName=1.10.0-root-preview.24`、min/target SDK 24/36；`apksigner` 确认单一 Android Debug
  signer、v2=true；本地 checksum 校验通过，APK 大小 8,681,655 字节。
- `adb devices -l` 当前没有连接设备，因此没有宣称一加 15/ColorOS 16 的真实延时、自启动、Root
  保活、无障碍恢复、应用接管或功耗结果。

## SHA-256

```text
ec03e3b490ca91074086102a1e89e7a83d951078abf1f71b9dc4cd93cda186b1  yinxing-1.10.0-root-preview.24-debug.apk
```
