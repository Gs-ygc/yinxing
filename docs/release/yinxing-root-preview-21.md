# 银杏老年体验 Preview 21

Preview 21 面向一加 15、中国版 ColorOS 16、KernelSU、已 Root 的受控专机。本版只优化
老人点击电话和首页应用后的交接可靠性：失败时尽量直接到达系统拨号盘，并抑制同一应用的
短时重复启动。没有继续扩展 BusyBox 或 Root 模块。

## 发布内容

- `yinxing-1.10.0-root-preview.21-debug.apk`：银杏 Debug APK，`versionCode=37`。
- `SHA256SUMS.txt`：本版 APK 的 SHA-256 校验值。
- KernelSU Root Guard：本版没有修改模块源码、脚本或元数据，继续使用
  [Preview 18 模块](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.18/yinxing-guard-1.10.0-root-preview.18.zip)。

## 老年主路径变化

- 已授权电话权限时仍使用原有 `ACTION_CALL` 直拨，成功后才增加联系人通话次数。
- 电话权限被拒、权限请求组件异常，或者直接拨号被系统拦截时，会自动把号码交给
  `ACTION_DIAL`。系统拨号盘会显示号码，仍需用户按拨号键确认；银杏不会绕过确认自动通话。
- 只有系统拨号盘也无法启动时，才显示原有兜底对话框，不再让常见失败路径先多点一次弹窗。
- 首页同一应用在 1.2 秒内连续点击只启动一次，避免老人手抖或系统响应慢时叠出多个任务。
  不同应用互不阻塞；应用不存在或启动失败会立即释放限制，允许立刻重试。
- 应用不可用时继续显示“无法打开应用”的中文提示；新增真实导航与 Toast 回归测试。
- Intent 交接只吸收可恢复的 `Exception`。`OutOfMemoryError` 等进程级错误不会被伪装成
  “应用不可用”后继续执行。

## 自启动、低功耗与接管边界

- 本版没有新增服务、定时器、轮询、网络请求、后台唤醒、Root 命令或无障碍命令，待机功耗
  模型不变。
- 本版没有修改 KernelSU 模块、BusyBox、HOME 接管、开机恢复、Doze 白名单或无障碍恢复。
  Preview 18 模块继续承担这些职责。
- 新增的防连点状态只保存在当前首页进程内，按包名记录一个时间戳，不落盘、不唤醒设备。
- Root Guard host/standalone 矩阵通过只说明未发生脚本回归，不能替代 ColorOS 16 真机的
  自启动、后台限制、拨号盘兼容性和耗电验收。

## 安装与体验顺序

1. 下载并覆盖安装本 Release 的 APK。APK 使用 Android Debug 签名，只适用于相同调试签名
   的体验安装。
2. 保持 Preview 18 KernelSU 模块启用；本版不需要重装或升级模块。
3. 先允许电话权限，点击常用联系人，确认仍能直接拨号且不会重复启动。
4. 再撤销电话权限，点击联系人并拒绝权限，确认直接进入系统拨号盘、号码正确，且需要手动
   按拨号键。
5. 在首页快速连续点击同一个第三方应用，确认只打开一个任务；随后快速点击两个不同应用，
   确认两者都能分别打开。
6. 重启专机后检查银杏 HOME、自启动和无障碍恢复，并记录首次可操作时间与一晚待机耗电。

## 回滚

1. 安装 [Preview 20 APK](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.20/yinxing-1.10.0-root-preview.20-debug.apk)。
2. KernelSU 模块保持 Preview 18，或按专机维护流程禁用并重启后再回退模块。
3. 若系统拒绝覆盖安装，按专机维护流程备份配置后卸载体验 APK，再安装旧 APK。

## 本地验证记录

- `:app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest --rerun-tasks
  --no-daemon --console=plain`：80/80 任务执行成功，耗时 92.45 秒；54 份 JUnit XML 共
  428 tests、0 failures、0 errors、0 skipped，主 APK 与 androidTest APK 均生成。
- 电话、应用启动和两个宿主行为的 34 个聚焦测试通过；独立复核结论为 Ready，
  0 Critical、0 Important。
- `bash tools/test-yinxing-guard.sh all`：退出码 0；host 与 BusyBox standalone 两轮均无 FAIL。
  Root 源码和测试脚本本版没有变化。
- `:app:lintDebug`：退出码 1，仍为既有 `RootCommandRunner.kt:72`、`:150` 两个 API 26
  错误，另有 135 条 warning；本版新增逻辑没有 lint error。
- `aapt2 dump badging`：包名 `com.yinxing.launcher`、`versionCode=37`、
  `versionName=1.10.0-root-preview.21`、`minSdk=24`、`targetSdk=36`。
- `apksigner verify --verbose --print-certs`：单一 Android Debug signer，APK Signature
  Scheme v2 为 `true`，证书 SHA-256 为
  `68168b637a07c0b77befbdce9f589f149a00869b50d893d111eaef73f7957175`。
- 当前 ADB 没有连接设备，因此没有宣称一加 15/ColorOS 16 的真实拨号盘交接、任务栈、
  自启动、无障碍恢复、首屏延时或功耗结果。

## SHA-256

```text
6ecc12435390d03e67dc43bf4d40bbf03e836e08df464fb76131fa628e4b73ed  yinxing-1.10.0-root-preview.21-debug.apk
```
