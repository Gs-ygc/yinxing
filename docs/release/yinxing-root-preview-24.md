# 银杏老年体验 Preview 24

Preview 24 聚焦老人点击首页应用后“没有反应、只能猜”的失败路径：把原来的短 Toast
改成可持续、可恢复的大按钮对话框。老人可以立即重试；仍打不开时，家属可以直接进入银杏
已有的设置页面检查首页应用。成功打开应用的路径保持原样，不增加探测、等待或后台任务。
目标设备仍是一加 15 中国版 ColorOS 16、KernelSU、已 Root 的受控专机；本版不修改 Root
Guard、KernelSU 模块或 BusyBox。

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

## 自启动、低功耗与 Root 边界

- 本版没有新增 Activity、服务、Receiver、定时器、轮询、网络请求、唤醒锁、Root 命令、无障碍
  命令或 KernelSU 资产；不会因为本版增加新的常驻后台耗电来源。
- KernelSU 模块、BusyBox、HOME 接管、开机恢复、Doze 白名单和无障碍恢复逻辑与 Preview 23
  相同。本次源代码差异未进入 Root/模块测试面。
- 本地 JVM/Robolectric 和 APK 构建不能证明 ColorOS 16 真机的接管延时、自启动、保活、无障碍
  恢复或功耗；这些结论只接受一加 15 实机证据。

## 安装与体验顺序

1. 下载并覆盖安装本 Release 的 APK。APK 使用与前几版相同的 Android Debug 签名。
2. 保持 Preview 18 KernelSU 模块启用；本版不需要重装或升级模块。
3. 在银杏首页保留一个已卸载、停用或暂时不可启动的应用入口，点击一次，确认对话框持续显示，
   且老人能读到应用名和下一步。
4. 重新启用/安装该应用后点击 `再试一次`，确认对话框关闭并进入同一个应用；快速重复点击不应
   造成多次启动。
5. 再制造一次失败，点击 `请家属检查设置`，确认进入银杏设置页；返回首页后检查应用条目仍在，
   没有被自动删除或重排。
6. 用系统大字体和 TalkBack 重走一次失败、重试和设置路径；随后重启专机，记录首页首次可操作
   时间、无障碍恢复结果和一晚待机耗电，作为本版真机反馈。

## 回滚

1. 安装 [Preview 23 APK](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.23/yinxing-1.10.0-root-preview.23-debug.apk)。
2. KernelSU 模块继续保持 Preview 18；本版没有模块状态需要回退。
3. 若系统拒绝覆盖安装，按专机维护流程备份配置后卸载体验 APK，再安装 Preview 23。

## 本地验证记录

- 强制执行 `:app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest
  --rerun-tasks --no-daemon --console=plain`：80/80 任务成功，外部耗时 96.49 秒；59 份
  JUnit XML 共 449 tests、0 failures、0 errors、0 skipped，主 APK 与 androidTest APK 均生成。
- Preview24 聚焦回归：Home 应用失败恢复、首页 smoke、电话启动回退共 32 个测试通过，最近一次
  Gradle 执行耗时 23 秒；Task 2 独立审查结论为无发现、Ready。
- `:app:lintDebug` 退出码 1，报告 2 个未改动的 `RootCommandRunner.kt:72`、`:150` API 26
  `NewApi` errors 和 135 warnings；Preview24 改动文件没有 lint error。两处 Root 行与 Preview23
  基线字节一致，本版不借机扩大 BusyBox/Root 范围。
- `git diff --check` 通过；源代码差异没有进入 `root/`、KernelSU module、manifest、service 或
  background scheduling。
- `adb devices -l` 当前没有连接设备，因此没有宣称一加 15/ColorOS 16 的真实延时、自启动、Root
  保活、无障碍恢复、应用接管或功耗结果。

## SHA-256

```text
38f12bc412f2bd82e7156f112803dac857c4b22fd074844fddf76881c3755381  yinxing-1.10.0-root-preview.24-debug.apk
```
