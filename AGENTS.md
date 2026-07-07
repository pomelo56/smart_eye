# AGENTS.md — 慧眼 SmartEye 项目操作手册

> 本文件是写给 AI 编程助手的项目操作手册。包含仓库概览、工具链指令、编码规范、任务路由和边界约束。
>
> **接手顺序**：先读 [TASKBOARD.md](./docs/TASKBOARD.md) 看当前冲刺与待办 → 再读本文件 → 最后读 [PROJECT.md](./PROJECT.md) 了解架构决策与已知问题。

---

## 0. 项目许可证

- **许可证**：Apache License 2.0
- 完整文本：[LICENSE](./LICENSE)
- 贡献时自动签署 CLA（Apache-2.0 §5 规定，提交 PR 即视为同意）
- 严禁将代码移出 `smart_eye/` 目录以"换许可证"；所有派生作品必须保留 Apache-2.0

---

## 1. 项目概览

- **项目名称**：慧眼 SmartEye
- **项目定位**：AI 视障寻物助手（TRAE AI 创造力大赛 · 社会服务赛道）
- **项目类型**：Flutter Android 应用
- **目标用户**：视障人士（盲人/低视力用户）
- **核心功能**：通过手机摄像头识别物品（取餐码等），并用语音播报，帮助视障用户「听见物品、找到东西」
- **开发阶段**：MVP（v0.1.0）
- **口号**：听见物品，找到东西

## 关键架构决策（2026-07-02 已确认）

- **语音方案**：`flutter_tts` 在 OPPO/ColorOS 上无法绑定系统 TTS 引擎，因此 MVP 改为**预录音频 + Android MediaPlayer**。所有语音素材位于 `assets/audio/`，`TtsService` 将文本映射为音频片段序列。
- **原生音频通道**：`MainActivity.kt` 暴露 `com.smart_eye/audio` MethodChannel，`AudioService` 通过它调用 `MediaPlayer` 顺序播放 assets。
- **Flutter asset 路径陷阱**：Dart 使用 `assets/audio/xxx.mp3`，但 Android `AssetManager` 需要 `flutter_assets/assets/audio/xxx.mp3`。参见 `docs/HANDOVER.md` 第 5 节。
- **OCR 方案**：继续使用 `google_mlkit_text_recognition` 本地模型，禁止云端 OCR。

---

## 2. 技术栈与工具链

### 2.1 核心技术
| 技术 | 用途 | 版本 |
|------|------|------|
| Flutter | UI 框架 | 3.x |
| Dart | 编程语言 | 3.x |
| camera | 相机控制 | latest |
| google_mlkit_text_recognition | OCR 文字识别（本地） | latest |
| audio assets + MediaPlayer | 语音播报（替代 flutter_tts） | 内置 |
| shared_preferences | 本地数据持久化 | latest |

### 2.2 开发命令
```bash
# 安装依赖
flutter pub get

# 运行分析（零警告通过）
flutter analyze

# 格式化代码
dart format lib/ test/

# 运行单元测试
flutter test

# 运行集成测试
flutter test integration_test/

# 构建 Release APK
flutter build apk --release

# 一键测试（推荐）
./scripts/test.sh
```

---

## 3. 目录结构

```
smart_eye/
├── PRD.md                   # 产品需求文档
├── AGENTS.md                # 本文件（AI 操作手册）
├── SOUL.md                  # Agent 人格定义
├── USER.md                  # 目标用户画像
├── CHANGELOG.md              # 变更日志
├── MEMORY.md                # 踩坑记录
├── lib/
│   ├── main.dart            # 应用入口
│   ├── screens/             # 页面（仅 HomeScreen 一个）
│   ├── services/            # 核心服务（Camera/Ocr/Tts/Audio）
│   ├── models/              # 数据模型
│   ├── widgets/             # 可复用组件
│   ├── utils/               # 工具函数
│   └── l10n/                # 国际化（预留）
├── assets/
│   └── audio/               # 预录音频素材（数字、井、提示语）
├── test/
│   ├── unit/                # 单元测试（TDD 核心）
│   │   ├── services/
│   │   └── models/
│   ├── widget/              # Widget 测试（MVP 暂缓）
│   └── integration/         # 集成测试
├── scripts/
│   └── test.sh              # 一键测试脚本
└── docs/
    ├── HANDOVER.md          # Agent 接手文档（必读）
    ├── CHANGELOG.md         # 版本变更归档
    ├── AUDIO_GENERATION.md  # 音频生成工作流（say + afconvert）
    ├── 无线调试安装APK.md   # 无线 ADB 部署流程
    ├── plans/               # 实施计划
    └── specs/               # 设计规格文档
```

---

## 4. 任务路由

| 任务类型 | 入口文件 | 注意事项 |
|---------|---------|---------|
| 新增/修改页面 | `lib/screens/` + `lib/main.dart` | 必须包裹 Semantics |
| 修改相机逻辑 | `lib/services/camera_service.dart` | 注意权限和生命周期 |
| 修改 OCR 逻辑 | `lib/services/ocr_service.dart` | 纯本地处理，禁止调云端 |
| 修改语音逻辑 | `lib/services/tts_service.dart` + `lib/services/audio_service.dart` + `android/app/src/main/kotlin/com/example/smart_eye/MainActivity.kt` | 必须处理初始化失败；新增音频素材需同步更新 `_mapTextToAssets` |
| 修改音频素材 | `assets/audio/` + `pubspec.yaml` | 新素材必须注册到 `pubspec.yaml` assets |
| 新增数据模型 | `lib/models/` | 必须写单元测试 |
| 新增工具函数 | `lib/utils/` | 必须写单元测试 |

---

## 5. 编码规范

### 5.1 通用规范
- 使用 `dart format` 格式化，单行不超过 80 字符
- 所有类和方法必须有文档注释（`///`）
- 禁止使用 `dynamic` 类型，必须显式声明

### 5.2 无障碍规范（强制）
- 每个可交互 Widget 必须有 `Semantics` 包裹
- `label` 必须描述「这是什么 + 操作后会怎样」
- 禁止使用仅依赖视觉的反馈（如颜色变化无语音播报）

### 5.3 语音反馈规范（强制）
- 禁止静默失败，所有异常必须有语音解释
- 取餐码播报格式：「井 15」（`#` 读作「井」）
- 长文本分段播报，每段不超过 15 秒
- 语音使用正常语速，扬声器最大音量
- 首次启动必须播报完整操作教程
- **新增音频素材**时：
  1. 放入 `assets/audio/`
  2. 在 `pubspec.yaml` 的 `assets:` 下注册
  3. 在 `TtsService._mapTextToAssets()` 中添加映射规则
  4. 如需从原生 `AssetManager` 读取，路径需为 `flutter_assets/<asset-key>`

### 5.4 TDD 规范（强制）
```
铁律：NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

- 每个 Service 类必须有对应的 `*_test.dart`
- 每个 Model 类必须有单元测试
- RED → 验证失败 → GREEN → 验证通过 → REFACTOR
- 测试必须使用真实代码，尽量避免 mock（除非测试外部硬件）

---

## 6. 边界约束

### 6.1 隐私约束（不可违反）
- ✅ 允许：使用 `google_mlkit_text_recognition`（本地模型）
- ❌ 禁止：调用任何云端 OCR API（如百度 OCR、腾讯云 OCR）
- ❌ 禁止：上传用户图像到任何服务器
- ❌ 禁止：收集设备信息、位置信息

### 6.2 无障碍约束（不可违反）
- ❌ 禁止：仅依赖视觉的提示（Toast、Snackbar 无语音）
- ❌ 禁止：复杂手势（如双指缩放、旋转）
- ❌ 禁止：需要视觉定位的交互（如点击精确坐标）

### 6.3 技术约束
- ❌ 禁止：引入不必要的第三方依赖（每个依赖需说明理由）
- ❌ 禁止：在 main 分支直接开发（使用 feature worktree）
- ❌ 禁止：跳过测试直接提交代码

---

## 7. 常见错误排查

| 问题 | 排查路径 |
|------|---------|
| OCR 识别率低 | 检查 `camera_controller` 分辨率设置 → 检查对焦模式 → 检查图像预处理 |
| 语音不播报 | 检查 `assets/audio/` 是否已在 `pubspec.yaml` 注册 → 确认 `TtsService._mapTextToAssets()` 包含目标文本 → 确认 Android `AssetManager` 路径使用 `flutter_assets/<asset-key>` → 检查媒体音量 |
| 音频叠加 | `speak()` 是 fire-and-forget，连续调用会重叠。**正确方案**: 每次 `speak()` 前先 `await _ttsService.stop()`。禁止用 `delay` 来「等待」音频完成（时长不确定）。参见 PROJECT.md KI-001 |
| 相机黑屏 | 检查 Android 权限（Camera） → 检查 `Surface` 初始化时序 → 检查生命周期绑定 |
| 手势不响应 | 检查 `GestureDetector` 层级 → 检查 `Semantics` 是否拦截事件 |
| 测试失败 | 检查是否先写测试再看失败 → 检查测试是否用真实代码而非 mock |
| 原生层找不到 asset | 在 `MainActivity.kt` 的 `assets.openFd()` 前加 `flutter_assets/` 前缀，参见 `docs/HANDOVER.md` 第 5 节 |

---

## 8. 升级规则（何时引入人工）

当 Agent 遇到以下情况时，**立即停止并请求人工介入**：

1. 连续 3 次尝试修复同一问题未果
2. 需要修改 `AGENTS.md` 或架构文档
3. 涉及危险操作（删除文件、修改权限、引入网络请求）
4. 测试全部通过但功能实际不符合预期（验证机制失效）
5. 遇到 AGENTS.md 中未定义的边界情况

---

## 9. 自检清单（每次提交前）

- [ ] `flutter analyze` 零警告
- [ ] `flutter test` 全绿
- [ ] 新增代码有对应的测试，且先失败过
- [ ] 所有交互元素有 Semantics
- [ ] 所有用户操作有语音反馈
- [ ] 没有引入新的第三方依赖（或已说明理由）
- [ ] 没有调用任何云端 API
