# 银杏老年体验 Preview 23

Preview 23 聚焦老人每天使用微信视频时最容易迷失的接管阶段：明确告诉老人正在联系谁、
微信当前在做什么，并提供一个真正看得见、点一下就生效的取消动作。视频联系人列表也不再
用逐项入场动画拖延首次操作。目标设备仍是一加 15 中国版 ColorOS 16、KernelSU、已 Root
的受控专机；本版不修改 Root Guard 或 BusyBox。

## 发布内容

- `yinxing-1.10.0-root-preview.23-debug.apk`：银杏 Debug APK，`versionCode=39`，
  `versionName=1.10.0-root-preview.23`。
- `SHA256SUMS.txt`：本版 APK 的 SHA-256 校验值。
- KernelSU Root Guard：模块源码、脚本和元数据均未修改，继续使用
  [Preview 18 模块](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.18/yinxing-guard-1.10.0-root-preview.18.zip)。

## 老年主路径变化

- 微信接管浮层始终以 `正在联系 <联系人>` 为主标题；下方只显示“正在打开微信”等当前
  动作，不再把“第几步/共几步”的内部诊断信息暴露给老人。
- 2 倍系统字体和超长联系人下，标题最多显示 3 行、状态最多 2 行，超出时明确显示尾部
  省略；底层文字与无障碍节点仍保留全文，浮层高度有界，`取消` 按钮不会被内容推出浮层。
- 原来低对比度、36dp、必须长按的 `x` 已改为明确的 `取消` 按钮。按钮为 `88dp x 56dp`，
  带 `取消联系` 无障碍描述，普通单击立即复用既有取消会话和返回银杏路径。
- 成功发起后，浮层仍保留联系人标题，并短暂显示 `视频通话已发起`，避免结果与目标对象
  脱节。
- 视频联系人 RecyclerView 不再播放增删改动画；普通性能模式下也移除了每行 220ms、
  每项额外 35ms 的入场延时。绑定或回收后的联系人卡片始终从可点击的稳定状态出现。
- 图片缓存、缩略图任务取消、联系人操作、无障碍语义、自动化选择器、重试、超时、终态
  回调和返回桌面路径保持不变。

## 自启动、低功耗与 Root 边界

- 本版没有新增 Activity、服务、Receiver、定时器、轮询、网络请求、唤醒锁、Root 命令、
  无障碍命令或 KernelSU 资产；因此不会因为这一版增加新的常驻后台耗电来源。
- KernelSU 模块、BusyBox、HOME 接管、开机恢复、Doze 白名单和无障碍恢复逻辑与
  Preview 22 相同。文件边界检查确认本版差异没有进入 Root/模块测试面，因而不重复与本版
  产品改动无关的 BusyBox 矩阵。
- 本地 JVM/构建测试不能证明 ColorOS 16 真机接管延时、自启动、保活、无障碍恢复或功耗；
  这些结论只接受一加 15 实机证据。

## 安装与体验顺序

1. 下载并覆盖安装本 Release 的 APK。APK 使用与前几版相同的 Android Debug 签名。
2. 保持 Preview 18 KernelSU 模块启用；本版不需要重装或升级模块。
3. 在银杏中准备一个容易辨认的微信视频联系人，例如“女儿”，点击视频通话。
4. 确认浮层始终显示 `正在联系 女儿`，下方动作会更新；第一次尝试单击 `取消`，确认任务
   终止并回到银杏，且不需要长按。
5. 再次发起并让流程走完，确认显示 `视频通话已发起`；返回视频联系人页，确认联系人直接
   出现、没有逐项淡入或上下移动。
6. 用系统大字体和 TalkBack 再走一次取消流程，确认标题、状态和取消按钮可读、可达、无
   遮挡；随后重启专机，记录首页首次可操作时间、无障碍恢复结果和一晚待机耗电。
7. 若微信接管、取消、回桌面、自启动或权限恢复异常，请记录联系人名、浮层最后一条状态、
   时间点，以及 `设置 -> Root 健康` 页面状态。

## 回滚

1. 安装 [Preview 22 APK](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.22/yinxing-1.10.0-root-preview.22-debug.apk)。
2. KernelSU 模块继续保持 Preview 18；本版没有模块状态需要回退。
3. 若系统拒绝覆盖安装，按专机维护流程备份配置后卸载体验 APK，再安装 Preview 22。

## 本地验证记录

- 强制执行 `:app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest
  --rerun-tasks --no-daemon --console=plain`：80/80 任务成功，外部耗时 95.17 秒；57 份
  JUnit XML 共 442 tests、0 failures、0 errors、0 skipped，主 APK 与 androidTest APK
  均生成。
- Task 1 浮层测试、视频通话测试与 select-to-speak 服务回归在最终小项清理后再次通过；
  新增覆盖包括按钮尺寸/文案/普通单击、监听替换、联系人标题回退、无列表动画、稳定行状态，
  以及有限屏幕高度下的大字体/长联系人/完整无障碍文字/取消按钮可达边界。
- `:app:lintDebug` 仍以退出码 1 报告 2 个既有 `RootCommandRunner.kt:72`、`:150` API 26
  `NewApi` errors 和 134 warnings。本版变更文件没有新增 lint error；视频适配器命中的
  `String.toUri` warning 位于未改动的既有缩略图代码。
- Preview 22 到 23 的完整差异复核覆盖取消监听生命周期、WindowManager 触控/焦点标志、
  大字体边界、会话身份保护、联系人状态更新、RecyclerView 回收和无障碍语义；没有发现
  Critical 或 Important 问题。审查发现的静默两行截断与随后识别的无限高度风险均已在
  发版前改为 3 行标题、2 行状态和明确省略的有界方案；最终独立复审结论为 Ready。
- Root 边界核对没有命中 `root/`、KernelSU module 或 `tools/test-yinxing-guard.sh`；浮层源码
  也不再命中长按监听、老人可见步骤计数或 `stepLabel()`。
- `aapt2 dump badging`：包名 `com.yinxing.launcher`、`versionCode=39`、
  `versionName=1.10.0-root-preview.23`、`minSdk=24`、`targetSdk=36`。
- `apksigner verify --verbose --print-certs`：单一 Android Debug signer，APK Signature
  Scheme v2 为 `true`；证书 SHA-256 为
  `68168b637a07c0b77befbdce9f589f149a00869b50d893d111eaef73f7957175`。
- `adb devices -l` 没有列出设备，因此没有宣称一加 15/ColorOS 16 的真实延时、自启动、
  Root 保活、无障碍恢复、应用接管或功耗结果。

## SHA-256

```text
d4eb3a54928d1fa6e3923f7cbed6c5bb27f93d9c0e18ca3b3ae65681e226146c  yinxing-1.10.0-root-preview.23-debug.apk
```
