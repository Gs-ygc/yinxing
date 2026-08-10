# 银杏老年体验 Preview 20

Preview 20 面向一加 15、中国版 ColorOS 16、KernelSU、已 Root 的受控专机。本版只处理
首页真实可感知的启动与滚动成本：恢复应用卡片按视口回收，去掉入口等待动画，并保留
Preview 19 的一键常用电话路径。

## 发布内容

- `yinxing-1.10.0-root-preview.20-debug.apk`：银杏 Debug APK，`versionCode=36`。
- `SHA256SUMS.txt`：本版 APK 的 SHA-256 校验值。
- KernelSU Root Guard：本版没有修改模块源码或元数据，继续使用
  [Preview 18 模块](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.18/yinxing-guard-1.10.0-root-preview.18.zip)。
  不重复发布内容相同、版本号却变化的模块 ZIP。

## 老年主路径变化

- 首页改为一个真正负责滚动的 `RecyclerView`。时间、天气、状态和常用电话组成全宽
  顶部区域，应用入口继续使用两列网格；不再把完整应用网格塞入外层滚动容器并一次性
  测量所有应用。
- 选择很多应用时，只创建和绑定视口附近的卡片，离屏应用的图标不会在首屏同时加载，
  降低启动时的布局、解码、内存和功耗压力。
- 应用卡片绑定后立即为完全可见状态，移除逐项淡入、位移、等待以及 RecyclerView
  增删动画；老人看到入口后即可点击。
- 应用卡片从固定高度改为自适应高度加稳定最小高度，系统字体或图标比例增大时可向下
  扩展，名称仍可显示两行。
- 拖动排序只接受应用子列表自己的位置，顶部时间、天气和常用电话不能被拖入排序；
  应用较多时由同一个 RecyclerView 负责跨屏滚动。
- 快速滚动离屏但仍在 RecyclerView 缓存中的卡片会继续完成图标加载，真正回收时才取消；
  调整图标比例后按新尺寸重载，并保留旧图直到新图完成。
- 拖拽过程中只派发一次位置移动；结束时更新内部列表快照而不重复移动。若拖拽期间应用
  列表刷新，最新列表会在拖拽提交后继续应用，不会被旧顺序覆盖。
- 新增 40 个已选应用的回归场景，验证列表不会绑定全部 44 个总条目，并且最后一个入口
  仍可滚动到达。

## 自启动、低功耗与接管边界

- 低功耗收益来自首页虚拟化和取消入口动画；本版没有新增定时器、轮询、常驻服务或
  网络请求。
- 本版没有修改 KernelSU 模块、BusyBox、HOME 接管、开机恢复、Doze 白名单、无障碍
  自动恢复、电话权限或拨号状态机。Preview 18 模块和 Preview 19 的常用电话直拨/拨号盘
  回退继续原样使用。
- 完整 Root Guard host/standalone 矩阵仍通过，用于确认上述能力没有因首页重构发生回归，
  但它不能替代 ColorOS 16 真机的自启动、后台限制和耗电验收。

## 安装与体验顺序

1. 下载并覆盖安装本 Release 的 APK。APK 使用 Android Debug 签名，只适用于相同调试
   签名的体验安装。
2. 保持 Preview 18 KernelSU 模块启用；新专机先安装上面的模块并按 KernelSU 提示重启。
3. 在应用管理中选择较多应用，返回首页连续上下滚动，确认卡片及时出现、没有逐项淡入，
   并能到达最后一个入口。
4. 增大系统字体和银杏图标比例，检查两列卡片文字不会被固定高度裁掉。
5. 长按第三方应用图标跨屏排序，确认不能把卡片拖到时间、天气或常用电话区域。
6. 再体验常用电话直拨、无权限时的拨号盘回退，以及 HOME/无障碍的开机恢复。

## 回滚

1. 安装 [Preview 19 APK](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.19/yinxing-1.10.0-root-preview.19-debug.apk)。
2. KernelSU 模块保持 Preview 18，或按专机维护流程禁用并重启后再回退模块。
3. 若系统拒绝覆盖安装，按专机维护流程备份配置后卸载体验 APK，再安装旧 APK。

## 本地验证记录

- `:app:testDebugUnitTest --rerun-tasks --no-daemon`：52 个 JUnit XML，408 tests、
  0 failures、0 errors、0 skipped，耗时 88 秒。
- `:app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest --rerun-tasks
  --no-daemon --console=plain`：80/80 任务执行成功，耗时 93.60 秒；主 APK 与 androidTest
  APK 均生成。
- `bash tools/test-yinxing-guard.sh all`：退出码 0；两轮 host/standalone 矩阵共
  434 PASS、0 FAIL，耗时 243.47 秒。Root 源码和测试脚本本版没有变化。
- `:app:lintDebug`：退出码 1，仍只有既有的 `RootCommandRunner.kt:72`、`:150` 两个
  API 26 错误，另有 134 条 warning；Preview 20 新增和修改文件没有 lint error。
- `aapt2 dump badging`：包名 `com.yinxing.launcher`、`versionCode=36`、
  `versionName=1.10.0-root-preview.20`、`minSdk=24`、`targetSdk=36`。
- `apksigner verify --verbose --print-certs`：单一 Android Debug signer，APK Signature
  Scheme v2 为 `true`。
- 当前 ADB 没有连接设备，因此没有宣称一加 15/ColorOS 16 的真实首屏时延、滚动帧率、
  耗电、跨屏拖拽、TalkBack、自启动或拨号权限结果。

## SHA-256

```text
e260318f261238ae67b67335f4d15d6a7c2c3c4b60ded3281e0332129510cd01  yinxing-1.10.0-root-preview.20-debug.apk
```
