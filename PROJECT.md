# PROJECT.md — 慧眼 SmartEye

> 项目级知识库。记录架构决策、已知问题、技术债务、经验教训。
> 供所有 Agent 接手时阅读，避免重复踩坑。

---

## 1. 架构决策记录 (ADR)

### ADR-001: 语音方案 — 预录音频替代 TTS

**状态**: 已采纳 (2026-07-02)

**背景**: MVP 原计划使用 `flutter_tts` 进行语音播报。在 OPPO/ColorOS 实机上测试发现：
- `flutter_tts.speak()` 返回成功但无声音输出
- Android 原生 `TextToSpeech.onInit` 返回 `ERROR (-1)`
- 系统设置里的 TTS 测试可以播放，但第三方应用无法绑定

**决策**: 使用 16 个预录 MP3 音频文件，通过 Android MediaPlayer 顺序播放。文本通过 `TtsService._mapTextToAssets()` 映射为音频片段序列。

**后果**:
- ✅ 不依赖系统 TTS 引擎，任何 Android 设备都能发声
- ✅ 播报延迟低（本地文件直接播放）
- ❌ 只能播报预录内容，无法动态合成任意文字
- ❌ 新增播报内容需要录制新音频

**相关文件**:
- `lib/services/tts_service.dart` — 文本→音频映射
- `lib/services/audio_service.dart` — MethodChannel 调用原生 MediaPlayer
- `android/app/src/main/kotlin/com/example/smart_eye/MainActivity.kt` — 原生音频播放
- `assets/audio/` — 16 个预录 MP3

---

### ADR-002: OCR 方案 — google_mlkit_text_recognition

**状态**: 已采纳 (2026-06-30)

**背景**: 需要识别外卖小票上的取餐码（`#` + 1-4 位数字）。

**决策**: 使用 `google_mlkit_text_recognition` 本地模型，禁止云端 OCR。

**后果**:
- ✅ 纯本地处理，不上传用户图像，符合隐私要求
- ✅ 无需网络权限
- ❌ 对手写文字识别率低（仅适合印刷体）
- ❌ 对复杂背景（如纸巾纹理）识别率低

**识别范围**: 支持 `#` + 1-4 位数字格式，覆盖四大外卖平台：
- 美团外卖
- 饿了么
- 京东外卖
- 淘宝闪购

**平台检测**: `OcrService.detectPlatform()` 通过关键词匹配检测平台名称，用于日志记录。语音播报格式暂不区分平台（均为"取餐码是井XX"），未来如需播报平台名称需录制额外音频素材。

---

### ADR-003: 手势交互 — 全屏触摸无按钮

**状态**: 已采纳 (2026-06-30)

**背景**: 目标用户是视障人士，无法看到屏幕上的按钮。

**决策**: 全屏相机预览 + GestureDetector 捕获触摸事件，没有任何可见按钮。

**手势映射**:
| 手势 | 功能 |
|------|------|
| 单击 | 重听上一次取餐码 |
| 双击 | 导出日志到下载目录（调试用途） |
| 三击 | 重新开始识别 |
| 上滑 (velocity < -800) | 播报历史记录 |
| 下滑 (velocity > 800) | 播报操作帮助 |

**注意事项**:
- GestureDetector 必须包裹在最外层
- 日志覆盖层使用 `IgnorePointer` 避免拦截触摸
- 所有 `speak()` 调用前必须先 `stop()` 防止音频叠加

---

## 2. 已知问题 (Known Issues)

### KI-001: 音频叠加 — speak() 是 fire-and-forget

**严重级别**: 🔴 高

**症状**: 连续调用两个 `speak()` 会出现声音重叠。

**根因**: `AudioService.speak()` 通过 MethodChannel 调用原生 `MediaPlayer`，是异步 fire-and-forget，不等待播放完成。

**错误修复方式**（不可靠）:
```dart
await _ttsService.speak('A');
await Future.delayed(Duration(seconds: 2)); // 音频时长不确定！
await _ttsService.speak('B');
```

**正确方案**:
- 所有 `speak()` 调用前必须先 `await _ttsService.stop()`
- 同一时间只应有一个 `speak()` 调用
- 启动时只保留一个音频（教程已含欢迎语，不额外播报启动音）

**重复踩坑次数**: 2 次（2026-07-02, 2026-07-04）

---

### KI-002: 相机首次初始化超时

**严重级别**: 🟡 中

**症状**: OPPO/ColorOS 首次冷启动相机可能超过 15 秒，`CameraController.initialize()` 超时。

**根因**: ColorOS 系统动画、权限弹窗、Surface 绑定时序问题。

**解决方案**:
- 3 次自动重试，间隔递增（2s, 4s）
- 分辨率使用 `high`（印刷体 OCR 需要足够分辨率）
- 生命周期 `paused` 时彻底释放 controller

**相关代码**: `lib/screens/home_screen.dart::_initCameraWithRetry()`

---

### KI-003: 手写文字识别率低

**严重级别**: 🟡 中

**症状**: 手写 `#213` 在纸巾上无法识别。

**根因**: Google ML Kit OCR 对手写中文和符号（`#`）识别能力有限，仅适合印刷体。

**验证结果**:
- ❌ 手写 `#213` 在纸巾上 — 识别不到
- ✅ 印刷体 `#36` 在文档上 — 识别成功
- ✅ 真实外卖小票（热敏打印）— 待验证，预期可识别

**结论**: 这不是代码 bug，是 OCR 引擎的固有限制。真实使用场景（外卖小票）是印刷体，应该能正常工作。

---

### KI-004: flutter_assets 路径陷阱

**严重级别**: 🟡 中

**症状**: 原生 `AssetManager.openFd("assets/audio/xxx.mp3")` 找不到文件。

**根因**: Flutter 打包时 asset 文件位于 `flutter_assets/assets/audio/xxx.mp3`，不是 `assets/audio/xxx.mp3`。

**解决方案**: 原生层必须使用 `flutter_assets/` 前缀：
```kotlin
assets.openFd("flutter_assets/assets/audio/$path")
```

**相关代码**: `MainActivity.kt::playSequence()`

---

### KI-005: 无线 ADB 多设备问题

**严重级别**: 🟢 低

**症状**: `adb devices` 显示两个设备，导致 `adb install` 报 "more than one device"。

**根因**: 同一手机通过 `adb pair` 和 `adb connect` 产生两种连接记录。

**解决方案**:
```bash
adb disconnect          # 断开所有
adb connect IP:端口     # 重新连接一个
```

---

## 3. 技术债务

| 债务项 | 优先级 | 说明 |
|--------|--------|------|
| 调试日志覆盖层 | P1 | 当前屏幕顶部有 8 行绿色日志。正式版应隐藏或改为可开关（长按/特定手势触发） |
| AudioService 集成测试 | P2 | MethodChannel 通信无法单元测试，需要 `integration_test/` |
| 日志导出权限 | P2 | `WRITE_EXTERNAL_STORAGE` 在 Android 10+ 需要 Scoped Storage 适配 |
| 双机种适配 | P3 | 仅测试了 OPPO A96，其他品牌/型号未验证 |
| 平台名称语音播报 | P3 | 当前仅日志记录平台名称，语音播报需录制平台名音频素材 |
| 各平台小票实测 | P3 | 美团已验证，饿了么/京东/淘宝闪购需真实小票测试验证 |

---

## 4. 测试矩阵

| 测试项 | 状态 | 说明 |
|--------|------|------|
| 单元测试 (17 个) | ✅ 通过 | `flutter test` 全绿 |
| 预录音频播放 | ✅ 通过 | OPPO A96 实测 |
| 相机预览 | ✅ 通过 | OPPO A96 实测 |
| OCR 印刷体识别 | ⚠️ 待验证 | 真实外卖小票待测 |
| OCR 手写识别 | ❌ 不通过 | Google ML Kit 固有限制 |
| 手势操作 | ✅ 通过 | OPPO A96 实测 |
| 历史记录 | ✅ 通过 | 单元测试覆盖 |
| 日志导出 | ⚠️ 待验证 | 功能已实现，未在真机验证 |

---

## 5. 文件清单

| 文件 | 用途 | 修改频率 |
|------|------|---------|
| `lib/screens/home_screen.dart` | 主屏幕（相机+手势+OCR） | 高 |
| `lib/services/tts_service.dart` | 文本→音频映射 | 中 |
| `lib/services/audio_service.dart` | MethodChannel 音频播放 | 低 |
| `lib/services/ocr_service.dart` | OCR 提取+多帧验证 | 低 |
| `lib/services/history_service.dart` | 历史记录 CRUD | 低 |
| `lib/services/file_logger.dart` | 文件日志+导出 | 中 |
| `android/app/src/main/kotlin/.../MainActivity.kt` | 原生音频播放 | 低 |
| `assets/audio/` | 16 个预录 MP3 | 低 |
