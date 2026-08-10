# 银杏老年体验 Preview 19

Preview 19 面向一加 15、中国版 ColorOS 16、KernelSU、已 Root 的受控专机。本版
把首页到可信家人的电话路径缩短为一次点击，同时处理短屏、大字体、旋转和权限回退
等容易让老年用户迷路的情况。

## 发布内容

- `yinxing-1.10.0-root-preview.19-debug.apk`：银杏 Debug APK，`versionCode=35`。
- `SHA256SUMS.txt`：本版 APK 的 SHA-256 校验值。
- KernelSU Root Guard：本版没有修改模块源码或模块元数据，继续使用
  [Preview 18 模块](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.18/yinxing-guard-1.10.0-root-preview.18.zip)。
  不重复发布内容完全相同但版本号虚高的 ZIP。

## 老年主路径变化

- 首页天气和应用入口之间新增“常用电话”区域，按现有联系人排序规则显示最多两位
  有号码联系人；无联系人时整个区域隐藏，不占用老人视线和触控空间。
- 每张常用电话卡整卡可点，直接复用电话页的权限请求、1.2 秒重复点击闸门、
  `ACTION_CALL` 和系统拨号盘回退；首页和电话页共用同一套待拨状态语义。
- 没有电话权限或直接拨号失败时，显示持续的大字回退对话框，一键打开已填号码的
  系统拨号盘；旋转或 Activity 重建不会丢失待拨联系人。
- “全部电话”是唯一的完整联系人入口，首页不放编辑、删除、导入等家属操作；原有
  电话网格入口仍保留并统一标为“全部电话”。
- 首页内容改为整页可滚动，应用网格按内容测量，不再因为状态卡、横屏或大字体把网格
  压到零；联系人卡片使用自适应高度且至少 112dp。
- 去掉首页整页入场动画，首屏直接可操作；空姓名旧数据显示“联系人”占位并提供
  明确的 TalkBack 拨打描述。

## 自启动、保活与 Root 范围

本版没有新增 Root 命令、BusyBox 依赖、轮询、常驻服务或无障碍自动授权逻辑。Preview
18 的 KernelSU 模块继续负责既有的受控专机接管、保活和无障碍恢复；本版只更新 APK
侧的老年主路径体验。ColorOS 16 自启动、后台拉起、TalkBack、功耗和系统电话权限
仍需要在目标一加 15 上验收，不能由本地测试替代。

## 安装与体验顺序

1. 下载并覆盖安装本 Release 的 APK。APK 使用 Android Debug 签名，适用于同一调试签名
   的体验安装，不是生产签名。
2. 保持 Preview 18 KernelSU 模块启用；新专机先安装上面链接的模块并按 KernelSU
   提示重启。
3. 在电话页准备一至两位有号码联系人，按需置顶；回到首页确认“常用电话”区域出现。
4. 点击联系人整卡，分别体验已授权直拨、拒绝 `CALL_PHONE` 后的拨号盘回退，以及权限
   请求期间旋转屏幕后的继续操作。
5. 在横屏、大字体和低性能模式下上下滚动首页，确认应用网格和“全部电话”仍可达；
   再用 TalkBack 检查每张卡只读出一个拨打动作。

## 回滚

1. 先安装 [Preview 18 APK](https://github.com/Gs-ygc/yinxing/releases/download/v1.10.0-root-preview.18/yinxing-1.10.0-root-preview.18-debug.apk)。
2. KernelSU 模块保持 Preview 18，或按专机维护流程禁用并重启后再回退模块。
3. 若系统拒绝覆盖安装，按专机维护流程备份配置后卸载体验 APK，再安装旧 APK。

## 本地验证记录

- `:app:testDebugUnitTest --no-daemon`：50 个 JUnit XML，400 tests、0 failures、
  0 errors、0 skipped。
- `:app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest
  --rerun-tasks --no-daemon --console=plain`：80/80 任务执行成功，耗时 100.94 秒；
  主 APK 与 androidTest APK 均生成。
- `bash tools/test-yinxing-guard.sh all`：退出码 0；两轮 host/standalone 矩阵共
  434 PASS、0 FAIL，耗时 244.20 秒。Root 源码和测试脚本本版没有变化。
- `:app:lintDebug`：退出码 1，仍只有既有的
  `RootCommandRunner.kt:72`、`RootCommandRunner.kt:150` API 26 错误，另有 132 条
  warning；Preview 19 新增文件没有 lint error。
- `aapt2 dump badging`：包名 `com.yinxing.launcher`、`versionCode=35`、
  `versionName=1.10.0-root-preview.19`、`minSdk=24`、`targetSdk=36`。
- `apksigner verify --verbose --print-certs`：单一 Android Debug signer，APK
  Signature Scheme v2 为 `true`。
- 当前 ADB 没有连接设备，因此没有宣称一加 15/ColorOS 16 的真实延时、耗电、
  TalkBack 或拨号权限结果。

## SHA-256

```text
85c38a63bd0a988b78e5dbfe66f9cd10d2e17cb39a3c33109f65716878cff06b  yinxing-1.10.0-root-preview.19-debug.apk
```
