# 慧眼 SmartEye 优化评估报告

> 生成时间：2026-07-04  
> 生成者：Hermes Agent（Nous Research）  
> 版本：v0.1.0 代码审阅  
> 基线：`flutter analyze` 零警告、单元测试 `78/78` 全绿

---

## 1. 项目当前状态概览

| 维度 | 现状 |
|------|------|
| 架构 | 单页面应用，`HomeScreen` 承担相机/OCR/语音/手势/历史全部职责 |
| 测试 | 4 个单元测试文件，覆盖 Ocr/Tts/History/MealCode，无 widget/integration 测试 |
| 稳定基线 | `flutter analyze` 零警告；`flutter test test/unit/` 78 个用例全通过 |
| 已知约束 | OPPO/ColorOS TTS 不可用，已切到预录音频 + MediaPlayer |

---

## 2. 优化项详细分析

### 2.1 高优先级：用户体验与稳定性

#### 2.1.1 用播放完成信号替代固定时长 delay
- **位置**：`lib/screens/home_screen.dart:286`、:`313`、:`382`
- **问题**：用 `Future.delayed(Duration(seconds: 3))` 或 `estimatedMs` 等待音频播放完毕，违反 AGENTS.md 中“禁止用 delay 等待音频完成”的铁律。
- **影响**：低端机 / 多码场景下，延时估计不准会导致扫描过早恢复或过晚锁死。
- **建议**：在 `MainActivity.kt` 的 `playAssets()` 播放结束后通过 MethodChannel 回调 `playAssetsDone(sequenceId)`，Dart 侧用状态机管理 `_isAnnouncing`。

#### 2.1.2 首屏教程结束后由真实状态恢复扫描
- **位置**：`lib/screens/home_screen.dart:79-104`
- **问题**：教程结束后写死 `await Future.delayed(const Duration(seconds: 8))`，教程长短变化后要么相机启动过早，要么一直阻塞。
- **建议**：返回一个 `Future<void>`，由音频播放结束事件触发，状态恢复到 `_isAnnouncing = false` 后自动恢复扫描。

#### 2.1.3 历史记录分条目逐条播放
- **位置**：`lib/screens/home_screen.dart:395-404`
- **问题**：把最多 5 条记录拼接成长字符串一次性播报，长文本违反 AGENTS “每段不超过 15 秒”的分段原则。
- **建议**：改为逐条 `await _ttsService.speak(fmt)`，条目间加简短停顿或分隔语音，并支持用户中途打断。

#### 2.1.4 全屏手势与无障碍语义
- **位置**：`lib/screens/home_screen.dart:490-545`
- **问题**：全屏 `Semantics` + `GestureDetector` 绑定了 onTap/上下滑，但 TalkBack 的系统手势、双击 / 滑动语义无显式处理。
- **影响**：TalkBack 用户在复杂手势下可能无法完成操作。
- **建议**：至少给用户一个“朗读当前状态/当前模式”反馈，并记录关键状态变更语音日志用于排障。

---

### 2.2 中优先级：性能与可维护性

#### 2.2.1 每帧处理耗时可观测化
- **位置**：`lib/screens/home_screen.dart:170-325`
- **问题**：每 2 秒一次 `takePicture()` + `processImage()`，低端机容易积压；当前无耗时记录。
- **建议**：用 `Stopwatch` 统计单帧耗时，超过阈值（如 1000ms）tik时写 `OCR_SLOW` 日志并跳过本次处理。

#### 2.2.2 相机生命周期职责拆分
- **位置**：`lib/screens/home_screen.dart:61-168`
- **问题**：`HANDOVER.md` 提到 `camera_service.dart`，实际仓库不存在，相机初始化/生命周期绑定全在 HomeScreen。
- **影响**：HomeScreen 长达 547 行，单一职责被破坏。
- **建议**：新建 `CameraService`，把 `_initCamera`、`_initCameraWithRetry`、`didChangeAppLifecycleState` 中相机部分统一迁出。

#### 2.2.3 多码历史写入并发化
- **位置**：`lib/screens/home_screen.dart:306-308`
- **问题**：`for (final r in results) await _historyService.add(r.code)` 是顺序 await。
- **建议**：改为 `await Future.wait(results.map((r) => _historyService.add(r.code)))`，无依赖的写入并发完成。

#### 2.2.4 平台 proximity 距离阈值硬编码
- **位置**：`lib/services/ocr_service.dart:88`
- **问题**：`maxDistance = 8` 是魔法字，小屏/大屏一样用，多票同框时容易误判。
- **建议**：改为常量 + 注释说明来源，或基于坐标/字号比例动态化。

---

### 2.3 低优先级：细节打磨

#### 2.3.1 路径字符串硬编码
- **位置**：`pubspec.yaml:27` 及代码中多处 `'assets/audio/...'`
- **建议**：不改代码可补注释，标明新增音频素材需同步注册的位置。

#### 2.3.2 日志导出目录硬编码
- **位置**：`lib/services/file_logger.dart:126`
- **问题**：`/storage/emulated/0/Download` 在 Android Q+ 可能无通用权限，导出会失败。
- **建议**：改为系统 `Downloads` 集合，或通过 `MediaStore` 写入。

#### 2.3.3 `stop()` 异常无兜底反馈
- **位置**：`lib/screens/home_screen.dart:283, 352, 364, 375, 387, 413`
- **问题**：`_ttsService.stop()` 失败时无语音/日志兜底，原生通道异常会“沉默失败”。
- **建议**：`stop()` 增加返回结果判断，失败时语音提示“语音服务异常，请重试”。

---

## 3. 可直接落地的优化任务清单

| ID | 任务 | 文件 | 改动点 | TDD | 风险 | 预期耗时 |
|----|------|------|--------|-----|------|----------|
| OPT-001 | 替换固定 delay 为原生播放完成回调 | `HomeScreen`, `MainActivity.kt` | 新增 `playAssetsDone` 回调；用状态机管理 `_isAnnouncing` | 需补 Integration Test | 中 | 4h |
| OPT-002 | 首屏教程结束后由真实状态恢复扫描 | `HomeScreen` | 去掉 `Future.delayed(8s)`，改为事件驱动 | 可用 Timer 模拟音频结束 | 低 | 1h |
| OPT-003 | 历史记录分条目逐条播放 | `HomeScreen` | 去掉 `StringBuffer` 长句，改为逐条 `speak` | mock TtsService 验证顺序 | 极低 | 1h |
| OPT-004 | 相机职责拆出 CameraService | 新建 `CameraService` | 迁出 `_initCamera` 等相机逻辑 | 新建 6+ 单测 | 低 | 3h |
| OPT-005 | 单帧处理耗时可观测化 | `HomeScreen` | Stopwatch + OCR_SLOW 日志 | 注入 fake Recognizer | 极低 | 1.5h |
| OPT-006 | 多码历史写入并发化 | `HomeScreen` | `Future.wait` 替代逐个 await | 2 单测 | 极低 | 0.5h |
| OPT-007 | proximity 阈值常量 + 注释 | `OcrService` | 提取魔法字为常量 | 0 | 极低 | 0.2h |
| OPT-008 | stop() 异常兜底反馈 | `TtsService`/`HomeScreen` | 返回值判断 + 语音提示 | 2 单测 | 低 | 1h |

---

## 4. 建议落地顺序

| 阶段 | 任务 | 预期耗时 | 测试工作量 |
|------|------|--------|-----------|
| S1：立刻做 | OPT-003 历史分条 | 1h | 补 2 单测 |
| S1：立刻做 | OPT-005 耗时观测化 | 1.5h | 补 2 单测 |
| S1：立刻做 | OPT-007 proximity 常量 | 0.2h | 无 |
| S1：立刻做 | OPT-006 多码写入并发化 | 0.5h | 补 2 单测 |
| S2：本周 | OPT-004 CameraService 拆分 | 3h | 补 6 单测 |
| S2：本周 | OPT-002 教程结束状态驱动 | 1h | 补 3 单测 |
| S3：下个迭代 | OPT-001 原生播放完成回调 | 4h | 改 Kotlin + Integration Test |
| S4：后续 | OPT-008 stop 异常兜底 | 1h | 补 2 单测 |

---

## 5. 文档与实现温差提醒

`AGENTS.md` 第 5.3 节明确写了：

> 禁止用 `delay` 来「等待」音频完成（时长不确定）。

但当前代码仍有以下位置使用固定延时等待音频：
- `lib/screens/home_screen.dart:286` — 单码播报后 `3000ms`
- `lib/screens/home_screen.dart:313` — 多码播报后按 `estimatedMs`
- `lib/screens/home_screen.dart:382` — 重新识别提示后 `3000ms`

建议优先处理 OPT-001 和 OPT-002，让文档与实现对齐。

---

## 6. 结论

当前项目具备良好的基线质量（零分析警告、78 个单测全绿），主要瓶颈集中在：
1. 音频播放与扫描恢复的耦合（固定 delay 反模式）
2. HomeScreen 职责过重（547 行，相机/OCR/语音/手势全栈）
3. 交互反馈过长（历史记录一次性长句播报）

按以上 4 阶段落地，可在 2 周内显著提升可维护性和用户体验稳定性，且所有高风险改动都控制在 Android 原生层或可测的接口边界内。
