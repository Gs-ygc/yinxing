# Preview 25: 来电操作失败恢复设计

## 背景

老人点击“接听”或“挂断”后，`IncomingCallActivity` 会停止自动接听倒计时和语音、禁用两个按钮，
再调用 Android Telecom。成功时页面结束；失败时，当前实现只显示一条短 Toast，然后重新启用两个
按钮。电话此时可能仍在响，但页面没有持续说明“刚才没有成功”，也没有通往系统电话界面的人工
兜底。

`IncomingCallActions.Result` 已提供 `PhonePermission`、`UnsupportedPlatform` 和 `CallAction`
等结构化原因。`IncomingCallDiagnostics.recordAcceptFailure/recordDeclineFailure` 也已经把全局会话
转成 `Failed`。本版复用这些边界，把已有证据呈现为老人可执行的恢复流程，不重做通话引擎。

## 目标

- 明确告诉老人本次接听或挂断没有完成，不依赖会消失的 Toast。
- 首选打开系统电话界面处理当前来电，同时保留一次动作明确的手动重试。
- 系统界面请求失败时保留当前恢复界面并显示下一步，不制造“已经打开”的假成功。
- 用户从系统电话界面返回后，仅用一次前台状态读取清理已结束或已接通的旧来电页。
- 保留精确家属诊断：动作失败、系统界面请求、请求异常和后续重试都可区分。
- 成功接听/挂断路径不增加查询、延时、动画、协程、Root 命令或后台工作。

## 非目标

- 不把银杏改成默认拨号器或 `InCallService`。
- 不使用 Root、`input keyevent`、坐标点击、无障碍点击或 OEM 私有接口接听/挂断。
- 不自动跳系统电话界面；只有老人点击明确按钮后才请求切换。
- 不恢复失败前的自动接听倒计时，避免权限或平台错误触发无上限自动重试。
- 不宣称 `showInCallScreen` 返回等于 ColorOS 已显示系统电话页；真机前台结果仍需一加 15 验收。
- 不同时修改联系人加载失败、HOME 角色或 KernelSU 模块。

## 方案比较

### 方案 A：来电页内嵌错误条

错误与来电人同时可见，但会继续挤压现有来电人、风险提示、倒计时和两个 124dp 操作区。系统
2 倍字体下更容易发生首屏溢出，也需要为一次失败给整个 Activity 增加新的持久布局状态。

### 方案 B：失败后自动切到系统电话界面

步骤最少，但 Android API 没有“界面已可见”的回执。ColorOS 拒绝或忽略请求时，老人会看到
银杏突然消失或误以为已经切换；自动接管也违背可观察、可取消的产品边界。

### 方案 C：专用恢复对话框（选定）

失败后覆盖一个大字号、两操作的持久对话框。主操作“打开系统电话”请求平台自己的通话界面；
次操作根据失败动作显示“重新接听”或“重新挂断”。按返回键可回到原来电页，点外部不关闭，
避免误触。该方案只改变失败分支，并可用 Robolectric 完整验证。

## 组件与职责

### `IncomingCallFailureDialog`

- 输入来电人、失败动作和 `IncomingCallFailureReason`。
- 标题分别为“还没有接通 <来电人>”或“还没有挂断 <来电人>”，最长两行并尾部省略。
- `PhonePermission`、`UnsupportedPlatform` 和其他指令失败使用三组简短、非技术化正文；原始错误
  继续留在家属诊断，不直接暴露给老人。
- 主按钮固定为“打开系统电话”，次按钮为动作特定重试；两个目标至少 68dp，最多两行，具有
  完整 `contentDescription`。
- 对话框允许返回键取消，禁止点击外部取消。系统界面请求抛出普通异常时，不关闭对话框，正文
  原地更新为持续失败提示。

### `IncomingCallSystemUiGateway`

- 生产实现只调用 `TelecomManager.showInCallScreen(false)`，不传号码、不发起新呼叫。
- 返回“请求已发送”或捕获到的普通 `Exception`；不捕获 `Error`，也不把 `void` 返回解释成
  前台确认。
- 用户从系统界面返回时，通过一次 `TelephonyManager.callState` 读取聚合状态。`IDLE` 或
  `OFFHOOK` 表示旧响铃页不应继续显示，`RINGING` 保留当前页；缺权限、无服务或异常返回未知并
  保留页面。
- 不注册监听、Receiver、定时器或轮询。

### `IncomingCallRecoveryCoordinator`

- 保存“已请求系统电话界面、等待下一次 Activity 恢复”的瞬时标记。
- 首次正常 `onResume` 不读取电话状态；只有一次成功请求后的下一次恢复才读取，并立即消费标记。
- 输出 `KEEP_RINGING`、`FINISH_ANSWERED`、`FINISH_ENDED` 或 `KEEP_UNKNOWN`。`OFFHOOK` 只证明
  当前通话已接通，映射为 `Answered`；`IDLE` 无法区分拒接、错过或对方挂断，只回到 `Idle`，
  不伪报 `Rejected`。
- 新来电 Intent 和 Activity 销毁会重置标记，避免旧请求影响下一通电话。

### `IncomingCallActivity` 与诊断

1. 接听/挂断失败沿用现有诊断写入，使会话保持 `Failed`。
2. 关闭旧恢复框后显示当前动作的恢复框；恢复框存在时不会创建第二个实例。
3. “重新接听/重新挂断”关闭恢复框，再走原有动作方法和 `actionInProgress` 闸门。
4. “打开系统电话”成功发送请求时，诊断只记录“系统电话界面已请求”，关闭恢复框并等待下一次
   `onResume`；请求异常记录异常类型/详情并保留恢复框。
5. 确认 `OFFHOOK` 后把会话记为 `Answered` 并关闭旧来电页；确认 `IDLE` 后把会话回到 `Idle`
   并关闭；未知状态不关闭。
6. 重试成功时清除诊断中的当前失败原因，同时保留“先失败、后成功”的步骤链，最终会话转为
   `Answered` 或 `Rejected`。
7. `onNewIntent`、成功动作和 `onDestroy` 均清理恢复框引用与暂时标记。

## 文案与无障碍

- `PhonePermission`：说明银杏缺少电话权限，建议先用系统电话处理，之后由家属检查权限。
- `UnsupportedPlatform`：说明系统不支持银杏直接完成该动作，建议使用系统电话。
- 其他失败：说明系统没有完成刚才的动作，可打开系统电话或再试一次。
- 系统界面请求异常：说明系统电话界面也没有打开，恢复框继续保留两项选择。
- 不显示异常类名、系统包名、权限常量、退出码或技术建议；这些只进入家属诊断。
- 对话框内容使用可滚动容器，以在窄屏和 2 倍字体下保持主操作可达；标题和按钮使用稳定行数，
  不随动态内容改变目标宽度。

## 测试与验收

- 纯单元测试：恢复协调器只在成功请求后的下一次恢复读取一次状态；`RINGING` 保留，
  `IDLE/OFFHOOK` 关闭，异常/未知保留；普通异常被结构化，`Error` 继续抛出。
- Robolectric 对话框：接听/挂断标题和重试文案正确；三类正文正确；两个按钮至少 68dp；返回键
  可退出、外部点击不退出；系统界面请求失败时对话框保持显示并更新正文。
- Activity 集成：撤销 `ANSWER_PHONE_CALLS` 后点击接听/挂断显示持久恢复框、倒计时停止、按钮恢复、
  会话为 `Failed`；重试复用同一动作边界；新 Intent 和销毁清理旧框。
- 诊断：失败后重试成功清除当前失败分类但保留失败/成功步骤；系统界面只记录 requested，异常
  单独记录 failed 及原始详情。
- 大字：在 360dp x 540dp 可用区域和 2 倍字体下测量内容不超过约束，主操作能通过滚动到达，
  Accessibility 节点保留完整文字。
- 回归：完整来电测试、全量 JVM/Robolectric、Debug APK、androidTest APK、lint 和差异审查。
- 真机：一加 15/ColorOS 16 分别验证缺权限、指令异常、系统电话切换、返回清理、TalkBack 和
  2 倍字体；本地测试不替代这些结论。

## 发布边界

- 版本更新为 `versionCode=41`、`versionName=1.10.0-root-preview.25`。
- KernelSU Root Guard 继续使用 Preview 18 模块；`root/`、manifest、服务和后台调度不改。
- GitHub prerelease 只发布 Debug APK 与 `SHA256SUMS.txt`，并提供 Preview 24 回滚链接。
