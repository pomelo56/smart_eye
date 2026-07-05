# CHANGELOG — 慧眼 SmartEye

> 本文件记录慧眼 SmartEye 的所有功能变更。每次迭代必须更新。
> 格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/) 规范。

---

## [Unreleased]

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
