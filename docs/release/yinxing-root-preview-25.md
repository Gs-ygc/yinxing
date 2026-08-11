# 银杏老年体验 Preview 25

Preview 25 处理老人接听或挂断来电失败后的恢复路径。原先失败只显示短暂 Toast，老人容易错过，
也不知道该重试还是转到系统电话；现在改为持续显示、动作和来电人明确的大按钮面板。目标设备仍是
一加 15 中国版 ColorOS 16、KernelSU、已 Root 的受控专机，但本版不修改 Root、KernelSU 模块、
BusyBox、HOME 接管、无障碍自动化或后台保活。

## 发布内容

- `yinxing-1.10.0-root-preview.25-debug.apk`：银杏 Debug APK，`versionCode=41`，
  `versionName=1.10.0-root-preview.25`。
- `SHA256SUMS.txt`：本版 APK 的 SHA-256 校验值。
- KernelSU Root Guard：继续使用
  [Preview 18 模块](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.18/yinxing-guard-1.10.0-root-preview.18.zip)，
  本版不需要重装模块。

## 来电失败恢复

- 接听失败显示“还没有接通 <来电人>”，挂断失败显示“还没有挂断 <来电人>”。权限缺失、系统
  不支持和普通动作失败各有老人可读说明，不再只显示一闪而过的 Toast。
- `重新接听` / `重新挂断` 只在老人明确点击后执行一次；失败不会恢复自动接听倒计时，也不会在
  后台轮询或自动点击。
- `打开系统电话` 调用 Android 官方系统电话界面请求。这个 API 没有成功回执，因此银杏只记录
  “系统电话界面已请求”，绝不把它写成已经打开或已经处理来电。
- 请求抛出异常时面板不会关闭，提示改为“系统电话也没有打开”；旋转或 Activity 重建后仍保留
  这个阶段，不会再次推荐一个已经失败但没有说明的动作。
- 从系统电话返回时只读取一次聚合电话状态：明确 `OFFHOOK` 才记录系统电话已接通；`IDLE` 只
  返回空闲，不推断是谁或用什么方式结束；仍在 `RINGING` 或读取失败时保留银杏来电页。
- 面板外部误触不会关闭，Back 可以主动取消；两个操作均为至少 `68dp` 的完整文字按钮。主按钮
  使用日间 7.68:1、夜间 5.48:1 的高对比配色，标题为无障碍 heading，动态失败消息使用
  assertive live region。
- 失败动作、来电人、失败分类、面板可见性和系统电话等待阶段会随 Activity 保存。旋转不会重新
  播报、重启倒计时或重复执行通知栏带来的接听/挂断动作。

## 诊断、延时与功耗边界

- 诊断链分别记录“系统电话界面已请求”“系统电话界面请求失败”“系统电话已接通”和“系统来电
  已结束”。请求失败保留原始接听/挂断失败分类和异常详情，确认恢复后才清除当前失败。
- 正常接听/挂断路径没有新增系统状态读取、延时、动画、Root 命令、网络或后台任务。只有老人点击
  系统电话并返回银杏后，才进行一次电话状态读取。
- 没有新增 Activity、Service、Receiver、定时器、轮询、唤醒锁或开机任务；本版不会增加新的
  常驻空闲功耗来源。
- Preview 24 的 Root 具体原因展示保持不变：`su`、权限、脚本、超时、退出码、输出和格式错误
  继续分别显示；停用模块的有效状态是 `需要处理`，不会统一成“Root 不可用”。

## 安装与体验顺序

1. 下载并覆盖安装本 Release 的 APK。APK 仍使用与此前体验版相同的 Android Debug 签名；保持
   Preview 18 KernelSU 模块启用。
2. 在系统应用权限里临时关闭银杏的“接听电话”权限，让另一台电话呼入，分别点一次接听和挂断，
   确认面板持续显示正确动作和来电人，倒计时不会重新开始。
3. 点 `重新接听` 或 `重新挂断`，确认只执行一次并在仍失败时只出现一个新的恢复面板。
4. 点 `打开系统电话`，确认跳到系统电话界面；若系统拒绝请求，确认银杏面板不消失并改为“系统
   电话也没有打开”。
5. 从系统电话返回：仍在响铃时银杏不应宣布成功；已经接通时银杏来电页应关闭；来电已结束时只
   结束银杏来电页，不显示“已拒接”之类未经证实的结果。
6. 在失败面板或系统电话请求失败后旋转屏幕，确认失败文案保留；等待系统电话返回时旋转屏幕，
   确认等待状态保留。所有场景均不得重复播报、恢复自动倒计时或重复接听/挂断。
7. 开启系统 2 倍字体和 TalkBack，重走失败、动态失败提示、重试和系统电话路径；确认两个按钮
   文字完整、可滚动到达，TalkBack 会读出标题和更新后的失败提示。
8. 打开“家属设置 → Root 专机”，继续按 Preview 24 的具体原因反馈记录徽章、详情、UID 和退出码；
   不要把不同 Root 失败概括为同一个“不可用”。

## 回滚

1. 下载 [Preview 24 APK](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.24/yinxing-1.10.0-root-preview.24-debug.apk)。
2. KernelSU 模块继续保持 Preview 18；本版没有模块状态需要回退。
3. Android 通常不允许直接覆盖安装更低 `versionCode`。如需回滚，先按专机维护流程备份银杏配置，
   再卸载 Preview 25 并安装 Preview 24。

## 本地验证记录

- 完整来电包在最终行为修复后包含 198 项测试，0 failures、0 errors、0 skipped；覆盖接听/挂断失败、
  显式重试、系统电话请求/返回、Activity 重建、通知动作单次消费、2 倍字体、TalkBack 语义和日夜
  对比度。
- 独立审查先发现 Activity 重建会重放动作、TalkBack 动态提示不足和主按钮对比度不足；修复后复核
  又发现系统电话请求失败阶段未保存。以上问题均以 RED 回归复现后修复。
- 最终源码执行 `testDebugUnitTest + assembleDebug + assembleDebugAndroidTest --rerun-tasks`，80 个任务全部
  重新执行并通过，耗时 100.02 秒。JUnit 共 505 项，0 failures、0 errors、0 skipped。
- Android lint 为 2 errors、133 warnings；两处 error 都是 Preview 25 之前已有的
  `RootCommandRunner.kt` API 24/26 `Process.waitFor` 兼容问题。本版新增的来电恢复代码没有 lint error。
- APK 包名 `com.yinxing.launcher`，`versionCode=41`，`targetSdk=36`，大小 8,705,668 字节；
  `apksigner` 确认 v2 签名有效、签名者数量为 1，证书为 Android Debug。
- 当前没有连接一加 15；本地测试不宣称 ColorOS 16 的真实界面接管、返回状态、延时、重启恢复、
  TalkBack 或待机功耗结果。

## SHA-256

`ad1258b78c6dc0056577b6daaae1cab15a32bdc788a113eb0aadec4232cd37e6  yinxing-1.10.0-root-preview.25-debug.apk`
