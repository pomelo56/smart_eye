# CHANGELOG — 慧眼 SmartEye

> 本文件记录慧眼 SmartEye 的所有功能变更。每次迭代必须更新。
> 格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/) 规范。

---

## [Unreleased]

---

## [0.7.2] — 2026-07-07 (无障碍增强：弱光环境)

### Added
- **弱光自动检测 + 手电自动开启**（v0.7.2 主要特性）
  - 新增 `lib/services/luminance_detector.dart`：
    - `LuminanceDetector.analyze()`：YUV420 Y plane 路径（未来 v0.8.0 改用 `startImageStream` 时用）
    - `LuminanceDetector.analyzeRgba()`：JPEG 解码路径（当前实现，dart:ui 解码 + 8x8 grid 采样）
    - 亮度阈值：< 40 = `dark`（建议开手电），40-200 = `normal`，> 200 = `bright`
    - BT.601 luma 权重（0.299 R + 0.587 G + 0.114 B），与人眼感知对齐
    - 64 像素采样，1280x720 帧 < 5ms
  - `TorchController`：包装 `CameraController.setFlashMode()`，幂等 + 处理硬件不支持
  - 3 段语音素材：
    - `luminance_dim.mp3`「光线较暗，识别可能不准确。正在尝试打开手电」
    - `torch_on.mp3`「手电已打开」
    - `torch_failed.mp3`「自动打开手电失败。请从手机通知栏下拉，手动开启手电」
  - `HomeScreen._maybeHandleLuminance`：
    - JPEG → dart:ui 解码 → RGBA → 亮度检测
    - dark 触发：先 `speakLuminanceDim` → `setTorch(true)` → `speakTorchOn`
    - 8s 冷却防止每帧都播报
    - 手电已开时不重复提示
    - 30s 冷却防止 torch 失败时反复 nag
  - `lifecycle paused` 时自动关手电（防止后台耗电 + 下次开 APP 还在亮）
  - 19 个新单测（v0.7.1 的 117 → v0.7.2 的 136）

### Changed
- `HomeScreen._scanFrame` 流程加一步亮度检测（OCR 之前），不动 OCR 逻辑
- 启动流程不变，但相机初始化成功后创建 `TorchController`

### Notes
- **不引新依赖**：用 dart:ui 内置 `instantiateImageCodec` + `toByteData(rawRgba)` 解码 JPEG，节省 ~500KB（image 包）
- **v0.8.0 计划改用 YUV420 stream**：当前是 JPEG 解码路径，720p JPEG 解码要 ~30ms；改 `startImageStream` 后用 Y plane 直接算亮度，< 1ms，且不再需要 JPEG 解码。但要重写扫描流程（v0.8.0 任务）
- **手电控制权限**：Android 不需要额外权限，`CameraController.setFlashMode(torch)` 在拿到 Camera 时就可用

---

## [0.7.1] — 2026-07-07 (紧急修复)

### 🐛 Fixed — 摄像头权限缺失时 APP 静默卡死

**严重级别**：🔴 P0（视障用户无任何反馈，APP 看起来已坏）

**症状**：用户首次安装时拒绝摄像头权限，APP 反复 log "相机不可用"，视障用户听不到任何语音提示，无法知道发生了什么。

**根因**：
- `HomeScreen._initCameraWithRetry()` 把所有相机初始化失败都当成"硬件故障"处理
- 没有调用 `ContextCompat.checkSelfPermission`，也不知道当前权限状态
- 失败后只 log 4 个字就完事，没有任何语音播报（违反 AGENTS.md 5.3「禁止静默失败」）

**修复**（v0.7.1）：
- 新增 `lib/services/permission_service.dart` — 相机权限的统一入口
  - `checkCameraPermission()` / `requestCameraPermission()` / `openAppSettings()`
  - 用 `MethodChannel('com.smart_eye/permission')` 与 MainActivity 通信，**不引入 `permission_handler` 依赖**（节省 ~2 MB）
  - `PermissionStatus` 枚举：granted / denied / permanentlyDenied
- `MainActivity.kt` 扩展为双 MethodChannel（`com.smart_eye/audio` + `com.smart_eye/permission`）
  - `checkCamera`：`ContextCompat.checkSelfPermission` + `shouldShowRequestPermissionRationale` 联合判断永久拒绝
  - `requestCamera`：`ActivityCompat.requestPermissions` + `onRequestPermissionsResult` 回调
  - `openAppSettings`：`Settings.ACTION_APPLICATION_DETAILS_SETTINGS` 跳转
- `HomeScreen._initialize()` 启动时**先**检查权限，无权限直接早返回
- `HomeScreen._initCameraWithRetry()` 失败后**追加**一次权限状态检查并语音播报
- `HomeScreen._onResumedFromBackground()` 从系统设置返回时自动重检测，权限恢复后自动重初始化相机
- 单击重听 / 双击导出日志：永久拒绝时不再静默，改为播报"请去设置开启摄像头权限"

### Added
- 3 个语音素材（`assets/audio/perm_*.mp3` + `opening_settings.mp3`，合计 85 KB）
  - `perm_denied.mp3`「应用未获得摄像头权限。请在系统设置中开启摄像头权限，然后重新打开应用」
  - `perm_permanently_denied.mp3`「摄像头权限已被永久拒绝。请进入系统设置，在应用中开启摄像头权限」
  - `opening_settings.mp3`「正在打开系统设置」
- 14 个单元测试（117 → 103 + 14）：
  - `test/unit/services/permission_service_test.dart`（7 个）：default platform / 检查 / 请求 / 永久拒绝判断 / 设置跳转
  - `test/unit/services/tts_service_test.dart` 新增 4 个：3 个新语音方法 + 1 个未初始化时不崩
  - `test/unit/build_config/build_config_test.dart` 新增 2 个：androidx.core 依赖 + MainActivity handler

### Changed
- `android/app/build.gradle` 显式添加 `androidx.core:core-ktx:1.13.1`（ContextCompat / ActivityCompat 需要）
- `assets/audio/` 从 16 个文件 → 19 个文件

### Numbers
- release APK：30.2 MB → **30.3 MB**（+0.1 MB）
- 单元测试：103 → **117**（+14）
- analyze：零警告

### Lessons
- **视障工具绝不静默失败**：任何异常路径都必须有语音反馈，否则用户只能靠猜
- **永久拒绝 ≠ 普通拒绝**：系统不再弹窗，必须主动引导去设置页
- **生命周期感知**：从设置页返回时要自动重试，不要让用户再次走手动重启流程

---

## [0.7.0] — 2026-07-07

### Changed
- **R8 代码压缩启用** — release APK 体积从 31.6 MB 降至 **30.2 MB**（-4%）
  - `android/app/build.gradle` release 块添加 `minifyEnabled true` + `shrinkResources true`
  - `classes.dex` 从 8-10 MB 压缩到 4.3 MB
  - 保留 30 MB 上限：剩余体积主要是 Dart AOT（3.4 MB）、Flutter 引擎（10.7 MB）、ML Kit 中文模型（11.1 MB）三者合计 ~25 MB
  - 详见 `docs/APK_SIZE_OPTIMIZATION.md` 第三节

### Added
- `test/unit/build/build_config_test.dart` — 5 个回归测试断言 R8 配置（minifyEnabled / shrinkResources / proguardFiles / ML Kit keep 规则 / MainActivity keep 规则）
  - 防止未来有人注释掉 R8 配置但 APK 体积悄悄回弹
- `android/app/proguard-rules.pro` 补全 6 类 keep / dontwarn 规则：
  - Flutter 引擎反射（`io.flutter.**`）
  - MainActivity MethodChannel 入口
  - Kotlin 注解（`kotlin.Metadata`）
  - Camera2 反射 API
  - Google Play Split-Install 缺失类抑制（项目走直接 APK 渠道）
- `docs/TASKBOARD.md` — 多 Agent 协作任务看板
  - 6 大区块：当前冲刺 / 进行中 / 待开发 / 待修复 / 待验证 / 技术债务
  - 引用 ROADMAP.md（v0.7.x - v2.0.0）和 PROJECT.md（KI-001 - KI-005、技术债务表）
  - Agent 接手协议：「先读 TASKBOARD → 再读 AGENTS.md → 再读 PROJECT.md」

### Changed (docs)
- `AGENTS.md` 顶部添加接手顺序指引
- `docs/HANDOVER.md` §1 添加 TASKBOARD 引用
- `VERSION.md` v0.7.0 计划项前移到 v0.7.1（TalkBack / 平台音频 / 真实小票测试）

### Note
- 体积收益低于 v0.6.1（-1.4 MB vs -34 MB）：剩余 30 MB 大头是引擎 + 模型，无法通过 R8 进一步压缩
- 真正释放体积的下一步：v0.8.0 计划**懒加载 ML Kit**（首次扫描时再下载中文模型），可省 ~10 MB
- R8 配置已受单测保护，未来修改 build.gradle 必触发 CI 红灯

### Changed
- **Debug APK 体积优化** — `flutter build apk --debug` 体积从 237 MB 降至 **89 MB**（-62%）
  - 原因：`ndk.abiFilters "arm64-v8a"` 在 `defaultConfig` 中同时影响 debug 和 release，debug 此前未经验证
  - 验证：`app-debug.apk` 内已只剩 `lib/arm64-v8a/` 一个目录
- 更新 `docs/APK_SIZE_OPTIMIZATION.md` 记录 debug APK 体积与构成

### Note
- Debug APK 不可能压到 30 MB：必须保留 Dart 调试符号、Hot Reload 引擎、Kotlin kapt 注解
- 89 MB 是当前工具链下的理论下限（除非放弃调试功能）

---

## [0.6.1] — 2026-07-06

### Changed
- **APK 体积优化** — release APK 从 ~65 MB 降至 **31.6 MB**（-51%）
  - ABI 单架构：`android/app/build.gradle` 添加 `ndk.abiFilters "arm64-v8a"`，只打包 64 位原生库
  - 清理孤儿音频：删除未引用的 `closer.mp3` `farther.mp3`
  - 新增 `docs/APK_SIZE_OPTIMIZATION.md` 记录优化方案

### Added
- `test/unit/services/audio_assets_inventory_test.dart` — 断言所有 `assets/audio/*.mp3` 都被 `lib/` 引用，防止引入孤儿音频或误删在用音频

### Note
- 自 v0.6.1 起，APK 不再支持 armv7 设备（2019 年后所有 Android 设备均为 arm64）
- 后续 v0.7.0 计划启用 R8 代码压缩，可再省 5-10 MB

---

## [0.6.0] — 2026-07-05

### Added
- 「发现外卖」语音提示：当 OCR 识别到外卖平台关键词（美团/饿了么/京东/淘宝闪购/朴朴）但尚未识别到取餐码时，播报"发现外卖，识别中，手机请稳一些"
- `OcrService.hasPlatformKeyword()`：检测文本中是否包含外卖平台关键词（含模糊匹配"京...外卖"）
- `TtsService.speakDetectedTakeout()`：拼接 3 段音频播放"发现外卖 / 识别中 / 手机请稳一些"
- `_playDetectedTakeoutPrompt()` HomeScreen 方法：5 秒冷却保护，避免手机抖动时反复触发
- 单元测试 `ocr_platform_keyword_test.dart`：9 个测试覆盖各类平台关键词

### Changed
- HomeScreen `_scanFrame` 在 `codes.isEmpty` 分支先检查平台关键词，命中则播"发现外卖"提示，否则保持原有"识别中"提示

### Added (Assets)
- `assets/audio/faxian_waimai.mp3`：「发现外卖」（macOS `say` + `afconvert` 生成，与现有 `num_*.mp3` 同 `ftypmp42` 容器）
- `assets/audio/shibiezhong.mp3`：「识别中」
- `assets/audio/please_steady.mp3`：「手机请稳一些」
- `pubspec.yaml` 已使用 `assets/audio/` 整目录声明，无需额外注册

---

## [0.5.1] — 2026-07-05

### Fixed
- 修复 `AudioService._isInitialized` 硬编码为 `true` 的问题：新增 `ping` 检测原生通道，真实报告音频引擎可用性
- 修复 `AudioService.stop()` / `TtsService.stop()` 异常时无反馈的问题：现在返回 `bool`，调用者可感知停止是否成功
- 修复 `_log()` 每次触发 `setState` 重建整棵 HomeScreen 树的问题：改用 `FileLogger.screenBufferNotifier` + `ValueListenableBuilder`
- 修复 `OcrService._cooldownMap` 只增不减的内存泄漏：每次 `processFrame()` 自动清理过期冷却条目
- 修复 `MethodChannel` handler 被多次注册的风险：多个 `AudioService` 实例间只注册一次回调

### Changed
- `TtsService.initialize()` 改为异步等待 `AudioService.initialize()`，确保语音服务真正就绪
- `OcrService` 支持注入 `clock` 函数，测试中无需真实等待 5 秒冷却时间
- 更新 `audio_service_test.dart`、`file_logger_test.dart`、`ocr_service_test.dart`、`tts_service_test.dart` 以覆盖上述修复

---

## [0.5.0] — 2026-07-04

### Added
- 原生音频完成回调：Kotlin 侧播放完成后通过 MethodChannel 通知 Dart 侧，`playAssets` 阻塞到播放完成
- 历史记录分条播放：`speakHistory` 方法逐条播放"第N条 65号"
- 新增音频素材：history.mp3、di.mp3、tiao.mp3、no_history.mp3
- `speakNoHistory` 方法：无历史记录时播放专用提示音

### Changed
- `_extractCode` 收紧匹配规则：仅匹配"数字+号"、"井+数字"、"平台名+数字"模式，不再提取任意文本中的数字
- `OcrService.proximityMaxDistance` 提取为命名常量（值为8）
- 首次启动教程不再需要 `Future.delayed` 等待，`speak` 自动阻塞到播放完成

### Removed
- `Future.delayed` 时序 hack：所有播报后的固定等待全部移除，改为原生回调驱动
- 冗余音频文件：prefix.mp3、jing.mp3（不再使用的旧格式音频）

---

## [0.4.0] — 2026-07-04

### Added
- 多平台外卖取餐码支持：美团外卖、饿了么、京东外卖、淘宝闪购
- `OcrService.detectPlatform()` 方法：基于 TextBlock 近邻检测平台名称（8字符窗口）
- 京东外卖模糊匹配：`京.{0,2}外卖` 正则应对 OCR 误识别
- `OcrService.selectBestCode()` 方法：多码时选择最长数字
- `ScanResult` 模型：取餐码+平台+屏幕位置（3×3 网格分区）
- 多码检测与播报：同时识别多个取餐码，播报位置信息
- "识别中，手机请稳一些"语音提示：OCR 有文字但无取餐码时
- 多码播报格式："识别到N个取餐码。美团外卖 65 号 左上。饿了么 2 号 右上。"
- 单码播报格式精简："平台+号码+号"（如"美团外卖 65 号"）
- 13 个新音频素材：4 个平台名 + 9 个位置词 + scanning/detected/gequcanma/hao
- App 图标替换为自定义 logo
- 版本管理规范：`VERSION.md` 文档 + git tag

### Changed
- 取餐码识别范围：从仅支持美团 `# + 1-3位数字` 扩展为支持四大平台 `# + 1-4位数字`
- 语音播报语速：从 1.0x 提升到 2.0x（MediaPlayer playbackParams）
- 确认取餐码时不再播放 beep_fast 提示音，直接播报取餐码（避免音频叠加）
- 项目定位升级：从「盲人取餐小工具」升级为「慧眼 SmartEye — AI 视障寻物助手」
- 平台检测从全文搜索改为 TextBlock 内近邻检测，防止跨小票误识别
- 冷却机制从单码 5 秒改为每码独立 5 秒 Map，新码不被旧码冷却阻止
- 多码播报按屏幕位置排序（上到下、左到右）

### Removed
- "闪购"短关键词（太宽松导致误匹配，只保留"淘宝闪购"完整词）
- 播报格式中的"取餐码是"和"井"前缀（精简为"平台+号码+号"）
- 项目名称统一为「慧眼 SmartEye」（TRAE AI 创造力大赛 · 社会服务赛道）
- 扫描机制：从「手动触发」改为「持续扫描（每 2 秒）+ 单帧确认 + 5 秒冷却去重」
- 手势方案：从「单击确认/双击重识」改为「单击重听/三击重识/自动保存」
- 历史记录：从「永久保存」改为「保留 24 小时自动清除」
- 交互反馈：新增距离提示音（类似倒车雷达）、首次启动语音教程

### Fixed
- 修复取餐码播报永不触发的 Bug：`processFrame()` 返回非 null 时冗余的 `isInCooldown` 检查导致播报被拦截
- 修复确认取餐码时 beep_fast 与语音播报叠加的问题：移除确认时的 beep_fast 播放
- 修正了取餐码位置假设：从「外卖盒上」改为「外卖袋上的打印小票」
- 修正了 TTS 语速假设：从「偏慢 0.8x」改为「正常语速 1.0x」（盲人习惯倍速播放）
- 统一所有文档的项目名称和定位描述，消除版本分裂
- 修复 OPPO/ColorOS 设备 TTS 无声问题：移除 `flutter_tts`，改用打包音频 + Android MediaPlayer 播放
- 修复 Flutter assets 在原生代码中的路径前缀错误：`assets/audio/...` 需通过 `flutter_assets/assets/audio/...` 访问

---

## 版本归档

版本发布后将归档到 `docs/CHANGELOG/vX.Y.Z.md`。

| 版本 | 发布日期 | 状态 |
|------|---------|------|
| v0.1.0 | 待定 | 开发中 |

---

## 变更类型说明

| 类型 | 说明 |
|------|------|
| Added | 新增功能 |
| Changed | 功能变更 |
| Deprecated | 即将移除的功能 |
| Removed | 移除的功能 |
| Fixed | Bug 修复 |
| Security | 安全相关修复 |
