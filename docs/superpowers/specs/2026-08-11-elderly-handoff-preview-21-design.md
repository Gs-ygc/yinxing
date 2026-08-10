# Preview 21 老年主路径接管可靠性设计

## 背景

Preview 20 已解决首页长列表的虚拟化与拖拽一致性，但首页和电话页仍有两个高频接管缺口：老人重复触摸应用卡片可能在系统完成切换前发出多个启动请求；直接拨号因权限或 OEM 拒绝时，必须先停在弹窗，再由老人再次点击进入拨号盘。前者增加外部 Activity 堆叠风险，后者增加失败路径的认知和操作成本。

## 目标

1. 保持已授权电话的 `ACTION_CALL` 快路径不变。
2. 权限被拒、权限请求失败或 `ACTION_CALL` 抛错时，自动尝试一次带号码的 `ACTION_DIAL`。拨号盘只填号码，不自动拨出；老人仍需在系统拨号盘确认。
3. 只有 `ACTION_DIAL` 也无法启动时，才显示现有失败弹窗，保留手动重试与取消入口。
4. 对首页同一应用目标增加短时重复启动防抖；不同应用之间不互相阻塞，启动异常后可立即重试。
5. 不添加 Root 命令、无障碍坐标输入、常驻轮询或新的后台服务。

## 方案

### 电话接管

`PhoneCallLauncher` 复用现有的 `launchIntent(Intent)` 边界。直接路径仍先通过现有 1.2 秒 `PhoneCallLaunchGate`；所有直接路径失败统一进入 `openDialerOrFallback`：先用同一回调启动一次 `PhoneCallIntentFactory.dialer(number)`，成功即结束当前应用侧流程，失败才调用 `showFallback(contact, directCallFailed)`。权限被拒时传 `directCallFailed=false`，直接 intent 抛错时传 `true`。拨号盘启动不记录“已拨打”次数，因为此时尚未确认通话。

两个宿主 Activity 已经提供相同的 `startActivity` 回调，无需新增宿主接口。自动进入拨号盘不再弹模态框；只有系统没有可处理的拨号盘时才沿用弹窗，因此无 Root、无电话权限和 OEM 失败仍有可恢复出口。

### 首页应用接管

新增小型 `HomeAppLauncher`，只负责解析已选应用的 launch intent、同目标防抖和错误回调。`HomeNavigator` 委托该对象，不改变现有目标 Activity 或任务栈 flags。`HomeAppLaunchGate` 按 package name 保存最近成功尝试时间，默认 1.2 秒；不同 package 独立，启动抛错立即释放该 package。这样重复触摸不会叠加同一外部应用，而老人仍可快速切换到另一个应用。

## 错误与边界

- 空 package 或无 launch intent：不调用 `startActivity`，通过现有中文失败 Toast 告知 caregiver/老人。
- 直接电话失败后，拨号盘启动成功：不再显示失败弹窗，不记为成功通话。
- 拨号盘启动失败：保留弹窗，弹窗中的“打开拨号盘”仍可再次尝试。
- Activity 重建期间的待处理权限联系人仍按 Preview 19/20 的保存恢复契约工作。
- 防抖只抑制同一 app，不影响不同 app；异常启动不留下冷却状态。

## 验收与测试

- JVM：权限拒绝自动发出一次 `ACTION_DIAL`；直接调用失败自动发出一次 `ACTION_DIAL`；拨号盘失败才产生 fallback；自动拨号盘路径不增加通话计数。
- JVM：同一 package 在 1.2 秒内只接受一次启动，不同 package 可启动，异常启动后同一 package 可重试。
- Robolectric：HomeNavigator 使用 HomeAppLauncher，验证成功启动、重复点击和无入口错误反馈。
- 强制运行现有完整 Android 单元测试、Debug APK 与 androidTest 编译；Root 矩阵保持回归验证但不修改。
- Release 文档明确：没有连接 OnePlus 15 时，不宣称 ColorOS 16 的真实拨号盘、Activity 切换延时、自启动或功耗数据。

## 非目标

本版不改变默认桌面角色、KernelSU 模块、自动无障碍恢复、来电自动接听策略、微信自动化或任何自动拨号行为。
