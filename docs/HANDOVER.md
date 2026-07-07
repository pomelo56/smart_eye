# HANDOVER.md — 慧眼 SmartEye Agent 接手文档

> 本文档写给未来接手本项目的 AI Agent 或开发者。阅读后应能独立理解架构、继续开发、构建和排障。
> 版本：v0.1.0-audio-fallback
> 最后更新：2026-07-02

---

## 1. 项目是什么

**慧眼 SmartEye** 是一款面向视障人士的 Android 端侧 AI 辅助应用。当前 MVP 聚焦「识别外卖小票上的取餐码并语音播报」。

- **目标用户**：盲人、低视力用户
- **核心价值**：把手机摄像头对准物品，听见识别结果
- **核心原则**：无障碍优先、隐私优先、端侧优先、可靠优先
- **禁止事项**：任何云端 OCR、上传图片、收集位置/设备信息

项目文档：`PRD.md`（需求）、`AGENTS.md`（AI 操作手册）、`SOUL.md`（人格）、`USER.md`（用户画像）、`docs/TASKBOARD.md`（多 Agent 任务看板）、`CHANGELOG.md`（变更日志）、`MEMORY.md`（踩坑）。

---

## 2. 当前技术方案

### 2.1 技术栈

| 层级 | 选型 | 说明 |
|------|------|------|
| 框架 | Flutter 3.x | 跨平台 UI，但当前仅构建 Android |
| 语言 | Dart 3.x | 业务逻辑 |
| 原生 | Kotlin | `MainActivity.kt` 暴露音频 MethodChannel |
| 相机 | `camera` | 实时预览 + 拍照 |
| OCR | `google_mlkit_text_recognition` | 纯本地文字识别 |
| 语音 | 预录音频 + `MediaPlayer` | 替代 `flutter_tts`，解决 OPPO/ColorOS 系统 TTS 无法绑定问题 |
| 存储 | `shared_preferences` | 首次启动教程标记、历史记录 |

### 2.2 核心文件位置

```
lib/
├── main.dart                          # 应用入口，锁定竖屏
├── screens/
│   └── home_screen.dart               # 唯一页面：相机、手势、语音、日志
├── services/
│   ├── audio_service.dart             # 原生音频通道的 Dart 封装
│   ├── tts_service.dart               # 文本 → 音频片段映射
│   ├── ocr_service.dart               # 取餐码提取和多帧验证
│   ├── camera_service.dart            # 当前未使用（相机逻辑在 HomeScreen）
│   └── history_service.dart           # 预留/即将实现
├── models/
│   └── meal_code.dart                 # 取餐码数据模型
└── widgets/                           # 当前未使用

assets/audio/                          # 预录音频素材
android/app/src/main/kotlin/com/example/smart_eye/MainActivity.kt
```

### 2.3 语音实现细节

由于 OPPO/ColorOS 等国产 ROM 不允许第三方应用绑定系统 TTS 引擎（即使系统设置里 TTS 能正常播放），MVP 改用**打包音频 + 原生 MediaPlayer**。

音频素材（`assets/audio/`）：
- `num_0.mp3` ~ `num_9.mp3`：中文数字 0-9
- `jing.mp3`：「井」
- `prefix.mp3`：「取餐码是」
- `none.mp3`：「没有识别到取餐码，请重新对准小票」
- `tutorial.mp3`：首次启动完整教程

**注意**：这些文件是 `afconvert` 生成的 MP4/AAC 容器，扩展名是 `.mp3`，Android `MediaPlayer` 按内容解析，不影响播放。

Dart 侧 `TtsService` 把文本映射为片段序列。例如 `取餐码是 井 15` 会映射为：
```
assets/audio/prefix.mp3
assets/audio/jing.mp3
assets/audio/num_1.mp3
assets/audio/num_5.mp3
```

然后通过 `com.smart_eye/audio` MethodChannel 交给 Kotlin 层顺序播放。

---

## 3. 构建与测试流程

### 3.1 常规开发

```bash
# 1. 使用 feature worktree（禁止在 master 直接开发）
cd /Users/pomelo/Project/smart_eye
git branch feature/your-feature master
git worktree add /Users/pomelo/Project/smart_eye_feature_your-feature feature/your-feature

# 2. 安装依赖
cd /Users/pomelo/Project/smart_eye_feature_your-feature
flutter pub get

# 3. 格式化
dart format lib/ test/

# 4. 静态分析
flutter analyze

# 5. 测试
flutter test
```

### 3.2 构建 Release APK

```bash
cd /Users/pomelo/Project/smart_eye
flutter build apk --release
```

输出：`build/app/outputs/flutter-apk/app-release.apk`（**约 31 MB**，仅 arm64-v8a）

> **ABI 限制**：自 v0.6.1 起，`android/app/build.gradle` 中 `ndk.abiFilters = ["arm64-v8a"]`
> 只打包 64 位原生库。2019 年后所有 Android 设备均支持。
>
> **Debug APK 体积**：debug 包约 89 MB（debug 需保留 Dart 调试符号、Hot Reload 引擎、Kotlin kapt 注解），
> 同样只含 arm64-v8a。
> 详见 `docs/APK_SIZE_OPTIMIZATION.md`。

### 3.3 安装到设备（无线 ADB）

```bash
# 配对（首次）
adb pair 192.168.1.2:42000
# 输入手机上显示的配对码

# 连接
adb connect 192.168.1.2:38347

# 安装
adb -s 192.168.1.2:38347 install -r smarteye-audio-fallback.apk

# 查看日志
adb -s 192.168.1.2:38347 logcat -s "SmartEye:D" "*:S"
```

---

## 4. 已知问题与陷阱

### 4.1 Flutter asset 在原生代码中的路径

Dart 使用 `assets/audio/tutorial.mp3`，但打包到 APK 后实际位于：
```
apk/assets/flutter_assets/assets/audio/tutorial.mp3
```

因此 Android `AssetManager` 读取时必须加 `flutter_assets/` 前缀：

```kotlin
// 正确
assets.openFd("flutter_assets/assets/audio/tutorial.mp3")

// 错误（Dart 层路径）
assets.openFd("assets/audio/tutorial.mp3")
```

当前 `MainActivity.kt` 的 `playNext()` 已自动处理前缀：
```kotlin
assets.openFd("flutter_assets/$path")
```

### 4.2 音频格式与扩展名

`afconvert` 生成的文件是 MP4/AAC 容器，但命名为 `.mp3`。Android `MediaPlayer` 按文件头解析，不会误判。若将来替换为真人录音，建议统一使用 `.mp3` 或 `.m4a`，保持 `pubspec.yaml` 注册路径与 `TtsService._mapTextToAssets()` 一致即可。

### 4.3 相机在部分 ColorOS 设备上首次初始化超时

当前 `HomeScreen._initCameraWithRetry()` 会重试 3 次。如果仍然失败，通常是因为应用未完全 resumed。切到后台再返回（或截屏）会触发 `didChangeAppLifecycleState` 重新初始化。

### 4.4 手势识别

当前实现：
- 单击 → 重听上一次结果
- 三击 → 清除结果，重新识别
- 双击 → 无操作（会被吞掉，不触发单击）
- 上滑/下滑 → 已实现（历史记录 / 帮助）

手势定时器为 600ms。对视障用户而言，三击节奏可能偏快，后续可考虑延长窗口或改为「长按 + 滑动」组合。

---

## 5. 如何扩展语音

若需要新增固定语音提示：

1. 把音频文件放入 `assets/audio/`
2. 在 `pubspec.yaml` 注册：
   ```yaml
   flutter:
     assets:
       - assets/audio/
   ```
3. 在 `TtsService._mapTextToAssets()` 中增加文本匹配规则：
   ```dart
   if (trimmed.contains('你要触发的关键词')) {
     return ['assets/audio/your_new_file.mp3'];
   }
   ```
4. 重新构建 APK 并测试。

若需要支持动态文本朗读（例如任意数字串），目前只能拼接 `num_0-9.mp3`。如需更复杂合成，需要重新引入 TTS 或录制更多素材。

---

## 6. 当前已实现 vs 待实现

| 功能 | 状态 | 备注 |
|------|------|------|
| 相机预览 | 已实现 | 基本可用，部分机型首次启动需重试 |
| OCR 持续扫描 | 已实现 | 每 2 秒拍照识别，连续 2 次一致才播报 |
| 取餐码播报 | 已实现 | 格式 `#` + 1-3 位数字 |
| 首次启动教程 | 已实现 | 通过 `tutorial.mp3` 播放 |
| 单击重听 | 已实现 | 通过 `GestureDetector.onTap` |
| 三击重新识别 | 已实现 | 通过 600ms 内点击计数 |
| 历史记录 | 待实现 | 计划用 `shared_preferences` + 24h 自动清除 |
| 上滑播报历史 | 已实现 | 通过 VerticalDragGestureRecognizer |
| 下滑播报帮助 | 已实现 | 拼接预设文本播放 |
| 距离反馈音 | 已实现 | 检测到文字时慢提示，可识别时快提示 |
| 完整无障碍语义 | 部分实现 | 所有 Widget 需加 `Semantics` |
| 光线不足提示 | 未实现 | 需要图像亮度分析 |

---

## 7. 测试策略

### 7.1 单元测试

- `test/unit/services/ocr_service_test.dart`：OCR 提取、多帧验证、冷却去重
- `test/unit/services/tts_service_test.dart`：音频映射、未初始化行为、固定提示匹配
- `test/unit/models/meal_code_test.dart`：数据模型解析、时间描述

### 7.2 手动测试清单

- [ ] 首次安装启动能听到「欢迎使用慧眼」教程
- [ ] 对准 `#15` 小票，能听到「取餐码是 井 15」
- [ ] 单击屏幕重听
- [ ] 三击屏幕重新识别
- [ ] 上滑播报历史记录（实现后）
- [ ] 下滑播报操作帮助（实现后）
- [ ] 识别过程中有距离反馈音（实现后）
- [ ] 日志无 `SmartEye` 红色错误

---

## 8. 分支与版本控制

- **`main`**：唯一主分支（GitHub 和 Gitee 默认分支均已统一为 `main`）
- 历史已删除的 `master` 分支不再使用；如再出现需要排查 `git fetch --all` 后是否仍有未清理的 ref

**新增功能**必须：
1. 从 `main` 创建 feature 分支
2. 使用 feature worktree（`git worktree add <worktree-path> -b feat/<name> main`）
3. 先写测试，再写实现（TDD）
4. 更新 `CHANGELOG.md` / `VERSION.md` / `PROJECT.md` / `pubspec.yaml`
5. `flutter analyze` 零警告 + `flutter test` 全绿
6. 提交并合并到 `main`
7. 把 feature 分支 + 合并后的 `main` **同时推送到 GitHub 和 Gitee**

### 8.1 远程仓库配置

```bash
git remote -v
# origin    -> gitee.com:free-style_2_0/smart_eye.git  (国内主用)
# github    -> github.com:pomelo56/smart_eye.git  (海外镜像 / 比赛仓库)
```

### 8.2 完整发布流程

```bash
# ====== 1. 在 worktree 内开发 ======
cd <worktree-path>
git branch --show-current   # 确认在 feature/feat-xxx 上

# 改动代码 + 测试
flutter analyze
flutter test test/unit/

git add -A
git commit -m "feat(xxx): description"

# 同步版本号变更（pubspec / CHANGELOG / VERSION / PROJECT）
git add pubspec.yaml CHANGELOG.md VERSION.md PROJECT.md
git commit -m "chore(release): bump version to v0.X.0+9"

git tag v0.X.0
git push github feat/feat-xxx
git push github v0.X.0

# ====== 2. 合并到 main 并同步双仓库 ======
cd /Users/pomelo/Project/smart_eye   # 回到主项目
git fetch github feat/feat-xxx
git merge feat/feat-xxx --ff-only
git push github main
git push origin main   # Gitee

# ====== 3. 构建并无线安装到手机 ======
# 详见 docs/无线调试安装APK.md（IP/端口每次会变，禁止写死）
DEVICE=$(adb devices | awk 'NR==2 {print $1}') && \
  flutter build apk --release && \
  adb -s "$DEVICE" install -r build/app/outputs/flutter-apk/app-release.apk
```

### 8.3 音频生成与构建集成

新增语音素材时使用 `say` + `afconvert` 程序生成（详见 `docs/AUDIO_GENERATION.md`），不要录真人。生成后必须随 commit 一起推送，否则 APK 找不到资产会闪退。

### 8.4 一键发布（推荐做法）

完整发布 = 上面 1 + 2 步 + tag + 推送到双仓库。手动跑太繁琐，已封装为脚本：

```bash
# 标准发布
./scripts/release.sh v0.6.2

# 顺便装到手机（设置环境变量）
RELEASE_INSTALL=1 ./scripts/release.sh v0.6.2

# 顺便发布到 Gitee release（需要先设置令牌）
export GITEE_TOKEN=<你的Gitee私人令牌>
./scripts/release.sh v0.6.2
```

**前置条件**：
- 必须在 `main` 分支
- 工作目录必须干净
- tag 必须符合 `vX.Y.Z` 格式
- `flutter`、`adb`、`jq`、`curl` 都在 PATH 中

**release.sh 流程**：
1. 跑 `./scripts/test.sh`（analyze + format + test）
2. `flutter build apk --release`
3. 推 main + tag 到 github / origin
4. （可选）安装到 adb 设备
5. （可选）调 `./scripts/release-gitee.sh` 发 Gitee release

**Gitee 令牌获取**：
1. 打开 https://gitee.com/personal_access_tokens
2. 新建令牌，勾选 `projects` 和 `releases` 两个 scope
3. `export GITEE_TOKEN=xxx`（**仅当前 shell 会话有效**）
4. **绝不要** 把令牌写进脚本或 commit 到仓库

---

## 9. 联系上下文

- 项目目录：`/Users/pomelo/Project/smart_eye`
- 当前开发工作目录：`/Users/pomelo/Project/smart_eye`
- 目标用户：视障人士，所有改动必须优先考虑语音反馈和无障碍
- 当前硬约束：OPPO/ColorOS 设备无法使用系统 TTS，必须坚持音频兜底方案
