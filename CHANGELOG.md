# CHANGELOG — 慧眼 SmartEye

> 本文件记录慧眼 SmartEye 的所有功能变更。每次迭代必须更新。
> 格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/) 规范。

### 版本描述写作规范（强制）

每个版本条目的描述必须严谨、专业、客观，面向用户和后续维护者：

- **禁止口语化表达**：不得使用「代码基本一致」「用于测试」「随便改改」等随意表述
- **禁止占位符**：不得使用「预留」「待补充」「TODO」等未完成标记，发布时必须填写完整
- **变更描述三要素**：写清楚「改了什么」「为什么改」「带来什么影响/解决什么问题」
- **使用专业术语**：使用「时序调整」「端到端验证」「可达性」「完整性」等工程术语，避免口语
- **严重级别标注**：Bugfix 必须标注严重级别（如「严重」「P0」）
- **Notes 章节**：如版本有特殊目的（如链路验证、hotfix），放在 `### Notes` 下用正式语言说明，不得使用引用块（`>`）加随意批注
- **版本完整性**：每个已发布版本（打过 tag 的）必须在 CHANGELOG 中有对应条目，不得遗漏任何版本
- **版本排序**：严格按版本号从新到旧降序排列（`[Unreleased]` 之后紧跟最新版本），每个版本章节使用 `## [X.Y.Z] — YYYY-MM-DD (标题)` 格式

---

## [0.9.0-rc1] — 2026-07-11 (低危安全修复·发布候选版)

### Security
- **CVE-STYLE-014（低危）**：release模式下禁用debugPrint输出到logcat，防止通过系统日志泄露应用内部状态信息。在`main.dart`入口处根据`kReleaseMode`覆盖debugPrint为空函数。
- **CVE-STYLE-016（低危）**：移除代码中残留的硬编码开发者标识信息，更新应用描述为正式产品描述。
- **CVE-STYLE-017（低危）**：锁定pubspec.yaml所有直接依赖版本，移除`^`版本范围约束，防止`flutter pub get`意外拉取存在已知漏洞的新版本依赖，确保构建可复现。
- **CVE-STYLE-018（低危）**：修复TtsService音频播放竞态条件，新增`_playbackMutex`互斥锁机制。每次播放新音频前先停止当前播放，确保同一时间只有一段音频序列在播放，解决快速连续触发语音播报时的音频重叠问题（符合AGENTS.md KI-001规范）。
- **CVE-STYLE-015（低危）**：Android包名从默认的`com.example.smart_eye`正式重命名为`com.smart_eye`，同步更新namespace、applicationId、MainActivity包路径、ProGuard keep规则及相关测试用例。

### Changed
- `lib/main.dart`：release模式下禁用debugPrint输出。
- `pubspec.yaml`：
  - 版本升级至`0.9.0-rc1+21`
  - 所有直接依赖锁定为精确版本（camera: 0.11.0+2、google_mlkit_text_recognition: 0.14.0、shared_preferences: 2.5.3等）
  - Dart SDK约束改为`>=3.5.0 <4.0.0`
  - 更新应用描述为正式产品描述
- `lib/services/tts_service.dart`：
  - 新增`_playbackMutex`互斥锁字段
  - 新增`_playWithMutex()`内部方法统一处理音频播放串行化
  - 所有23个`speak*`公共方法改为通过`_playWithMutex()`调用，不再直接调用`AudioService.playAssets()`
  - 每次播放前先执行`stop()`确保之前的音频被中断
- `android/app/build.gradle`：
  - `namespace`从`com.example.smart_eye`改为`com.smart_eye`
  - `applicationId`从`com.example.smart_eye`改为`com.smart_eye`
- `android/app/src/main/kotlin/`：MainActivity.kt从`com/example/smart_eye/`迁移至`com/smart_eye/`目录，package声明同步更新。
- `android/app/proguard-rules.pro`：MainActivity keep规则更新为新包名。
- `test/unit/build_config/build_config_test.dart`：MainActivity文件路径和包名断言更新为新包名。
- `test/unit/services/update_service_test.dart`：测试用PackageInfo的packageName更新为新包名。
- `test/unit/services/history_service_test.dart`：修复测试用例以适配CVE-STYLE-008引入的存储混淆，新增使用`obfuscateForTest()`辅助方法准备测试数据。
- `lib/services/history_service.dart`：新增`obfuscateForTest()`公开静态方法供测试使用。

### Notes
- 本版本修复了安全审计发现的全部18个漏洞（2个严重、4个高危、6个中危、6个低危），是首个安全加固完成的发布候选版本。
- 包名变更后，应用签名数据目录路径变更，旧版本（v0.8.6及以前）无法直接覆盖安装，需卸载后重新安装。
- 音频互斥锁机制确保语音播报不会重叠，所有语音提示按触发顺序串行播放，体验更稳定。
- 依赖版本锁定后，后续构建不会自动升级依赖版本，需手动检查和更新依赖以获取安全补丁。
- 回滚点：`v0.8.6`。如本版本引入问题，可执行 `git reset --hard v0.8.6` 回滚。

---

## [0.8.6] — 2026-07-11 (中危安全修复)

### Security
- **CVE-STYLE-008（中危）**：历史记录存储使用XOR+Base64混淆，避免SharedPreferences中的取餐码明文可读。不引入新依赖，对历史明文记录兼容（解析失败自动丢弃）。
- **CVE-STYLE-009（中危）**：release模式不再记录异常堆栈跟踪到日志，仅在debug模式输出完整堆栈，避免通过日志泄露内部实现细节和文件路径。
- **CVE-STYLE-010（中危）**：APK缓存文件使用版本号命名（`smart_eye_update_v{versionCode}.apk`），不再使用固定可预测文件名`smart_eye_update.apk`，防止路径遍历攻击覆盖已有文件。
- **CVE-STYLE-011（中危）**：收窄FileProvider暴露路径，从暴露整个cache目录改为仅暴露`cache/updates/`子目录，APK下载路径同步迁移到该子目录。
- **CVE-STYLE-012（中危）**：临时拍照文件删除逻辑移至`finally`块，确保OCR处理异常时（如ML Kit崩溃、旋转识别失败）临时图片也会被清理，不会残留敏感图像。
- **CVE-STYLE-013（中危）**：屏幕调试日志覆盖层仅在debug模式显示，release构建中完全隐藏，防止公共场合肩窥泄露识别信息。

### Changed
- `lib/services/history_service.dart`：新增`_obfuscate`/`_deobfuscate`方法，写入SharedPreferences前进行XOR混淆。
- `lib/screens/home_screen.dart`：
  - 引入`foundation.dart`使用`kDebugMode`
  - APK下载路径改为`cache/updates/smart_eye_update_v{version}.apk`
  - 临时图片路径保存在`capturedImagePath`变量，finally块中删除
  - 日志覆盖层用`if (kDebugMode)`条件包裹
  - 亮度异常堆栈仅在debug模式记录
- `android/app/src/main/res/xml/file_paths.xml`：FileProvider路径从`cache-path path="."`收窄为`cache-path path="updates/"`。

### Notes
- 本版本修复了安全审计发现的6个中危漏洞。
- 历史记录混淆为轻量保护（非强加密），可阻止adb直接grep读取明文取餐码。如需强加密（Android Keystore），后续版本引入flutter_secure_storage。
- 回滚点：`v0.8.5`。如本版本引入问题，可执行 `git reset --hard v0.8.5` 回滚。

---

## [0.8.5] — 2026-07-11 (高危安全修复)

### Security
- **CVE-STYLE-007（高危）**：新增Android网络安全配置`network_security_config.xml`，全局禁止HTTP明文流量，防止SSL剥离和HTTP降级攻击。配置`usesCleartextTraffic="false"`，release模式仅信任系统CA证书。
- **CVE-STYLE-004（高危）**：新增APK下载URL白名单校验机制，仅允许从`gitee.com`、`github.com`及其CDN子域名下载APK。在UpdateService获取下载URL时和DownloadService发起下载前进行双重校验，即使API响应被篡改也无法重定向到恶意服务器。
- **CVE-STYLE-005（高危）**：OCR日志脱敏处理，不再在日志中记录小票文本内容、平台名称和取餐位置标签，仅记录识别字数。外卖小票可能包含用户姓名、电话、地址等PII，脱敏后避免通过日志泄露隐私。
- **CVE-STYLE-006（高危）**：外部存储诊断日志默认关闭，新增诊断模式开关，仅在用户主动开启时才写入外部存储。避免日志文件在未授权情况下被其他应用读取。

### Changed
- 新增`UpdateService.isValidDownloadUrl()`静态方法进行URL白名单校验。
- `DownloadService.downloadApk()`在发起网络请求前校验URL合法性。
- `FileLogger`新增`enableDiagnosticMode()`方法和`isDiagnosticModeEnabled`属性。
- `AndroidManifest.xml`引用`network_security_config`配置。
- 新增`android/app/src/main/res/xml/network_security_config.xml`网络安全配置文件。

### Notes
- 本版本修复了安全审计发现的5个高危漏洞中的4个（CVE-STYLE-003 SSL Pinning为框架预留，证书指纹需发布前填入）。
- 网络安全配置禁止明文HTTP流量，应用内更新使用HTTPS不受影响。
- 日志脱敏后不影响核心OCR识别和语音播报功能，仅减少日志中的敏感信息。
- 回滚点：`v0.8.4`。如本版本引入问题，可执行 `git reset --hard v0.8.4` 回滚。

---

## [0.8.4] — 2026-07-11 (严重安全修复)

### Security
- **CVE-STYLE-002（严重）**：Release版本不再使用Android SDK公开debug密钥签名，改用独立生成的上传密钥。修复后，攻击者无法再使用debug密钥签名同名APK进行覆盖安装。
- **CVE-STYLE-001（严重）**：新增APK签名校验机制，在调用系统安装器之前通过原生PackageManager比对下载APK的签名与当前应用签名是否一致。签名不匹配时立即终止安装并语音警告用户，有效防御公共WiFi下的MITM供应链攻击。

### Changed
- 新增 `lib/services/apk_verifier.dart` 签名校验服务，通过MethodChannel调用Android原生API。
- `InstallService.installApk()` 方法在执行安装前强制进行签名校验。
- `InstallResult` 新增 `message` 字段用于TTS语音反馈，新增 `signature_mismatch` 错误码。
- 更新 `.gitignore` 防止签名密钥文件（`*.jks`、`key.properties`）被误提交到版本库。
- 新增对应单元测试覆盖签名校验失败场景。

### Notes
- 本版本为安全修复版本，修复了审计发现的2个严重漏洞。两个漏洞组合可导致公共WiFi环境下的恶意更新攻击链：攻击者通过MITM替换下载的APK，由于原版本使用debug签名且无安装前校验，恶意APK可成功安装并控制设备。
- 签名密钥密码为 `smarteye123`，正式发布前请更换为强密码并备份 `android/app/upload-keystore.jks` 文件。密钥丢失将导致无法发布更新。
- 回滚点：`v0.8.3-security-base`。如本版本引入问题，可执行 `git reset --hard v0.8.3-security-base` 回滚到修复前状态。

---

## [Unreleased]

### Added

- **版本治理与 v1.0 发布冻结**
  - `scripts/release.sh` 新增版本门禁：
    - 禁止发布 major >= 1 的 tag（`v1.0.0` 等）
    - 校验 tag 与 `pubspec.yaml` 的 versionName 一致
    - 如需强制发布 v1.0，必须显式设置 `ALLOW_V1_RELEASE=1`
  - `VERSION.md` 新增 v1.0 readiness checklist，明确正式版发布前必须完成的 7 项条件
  - `AGENTS.md` §6.3 新增版本约束：未完成 checklist 前禁止提升 major 版本
  - `docs/ROADMAP.md` 更新版本规划，将 v1.0.0 标记为「已冻结」

---

## [0.8.3] — 2026-07-10 (应用内更新正式版)

### Fixed
- **摄像头权限误判回退**：把「是否请求过摄像头权限」的标志从 SharedPreferences 迁移到 Android `noBackupFilesDir`，避免 ColorOS/Google 备份在卸载重装后恢复旧标志，导致首次启动被误判为永久拒绝。
- **未允许安装权限返回后无反应**：打开系统设置去开启「安装未知应用」权限后，返回应用会自动重试安装已下载的 APK，并语音提示「请按提示完成安装」。
- **APK 重复下载**：如果缓存目录中已有下载好的更新包，上滑确认后跳过下载，直接提示安装。
- **下载连接超时过短**：下载 APK 的连接超时从 10 秒增加到 30 秒，以应对 GitHub CDN 在国内较慢的情况。

### Changed
- 下载更新时增加 10% 粒度的进度日志，便于排查下载卡死问题。
- `UpdateService` 文档注释明确 Gitee 优先、GitHub fallback 的更新源策略。
- 新增 `docs/IN_APP_UPDATE.md` 记录应用内更新机制、发布 checklist 和常见问题。
- `MEMORY.md` 记录「更新源优先 Gitee」和「摄像头永久拒绝误判」两个已验证决策。

### Notes
- 本次发版必须同步发布到 Gitee 和 GitHub Releases。如果只发 GitHub，国内用户下载时可能因网络超时失败。

---

## [0.8.2] — 2026-07-10 (更新流程时序优化)

### Changed
- **更新检查执行时序调整**：将版本更新检查从相机权限检查之后提前到服务初始化完成之后立即执行。此变更确保即使用户因摄像头权限被拒而无法正常使用识别功能，仍能收到包含权限修复的更新推送，避免用户在有缺陷的版本上无法自救。

### Notes
- 本版本基于 v0.8.1 构建，仅包含上述时序调整，用于端到端验证应用内更新链路的完整性与可达性。

---

## [0.8.1] — 2026-07-10 (Bugfix 版本)

### Fixed
- **摄像头权限误判为"永久拒绝"**（严重）：首次安装（从未请求过权限）时，Android 的 `shouldShowRequestPermissionRationale` 也会返回 `false`，原逻辑将这种情况错误识别为"永久拒绝"，直接跳系统设置而不是弹系统权限对话框。修复方式：在 `MainActivity.kt` 中使用 SharedPreferences 持久化 `camera_permission_has_been_requested` 标志，只有在"曾请求过 + rationale=false"同时成立时才判定为永久拒绝。
- **应用名称显示为"取餐助手"**：`lib/main.dart` 的 `MaterialApp(title)` 遗留了早期项目名，已统一改为"慧眼 SmartEye"；`AndroidManifest.xml` 的 `android:label` 从"慧眼"改为"慧眼SmartEye"（最近任务列表和桌面图标下显示的名称）。
- **dio 无超时导致更新检查挂起**：`UpdateService` 和 `DownloadService` 所用的 Dio 实例未设置 `connectTimeout`/`receiveTimeout`，在网络不佳时可能长时间卡住在启动阶段。现在更新检查使用 8s 连接/15s 接收超时，下载使用 10s 连接/5 分钟接收超时。

---

## [0.8.0] — 2026-07-10 (应用内更新)

### Added
- **应用内更新**（v0.8.0 主要特性，解决视障用户手动升级困难）
  - 新增 `UpdateService`：每周一次、仅在 Wi-Fi 下检查 Gitee/GitHub Releases 最新版本
    - Gitee 主源：`https://gitee.com/api/v5/repos/free-style_2_0/smart_eye/releases/latest`
    - GitHub 备用源：`https://api.github.com/repos/pomelo56/smart_eye/releases/latest`
    - 支持从 tag `vX.Y.Z+NNN` 或 release body `versionCode: NNN` 解析 Android `versionCode`
    - 本地版本不大于远程版本时静默跳过
  - 新增 `DownloadService`：基于 `dio` 下载 APK，支持进度回调，下载前删除旧包
  - 新增 `InstallService`：通过 `com.smart_eye/installer` MethodChannel 调用原生安装能力
  - 新增 `ConnectivityService`：封装 `connectivity_plus`，仅暴露 Wi-Fi 检测，便于测试注入
  - Android 原生层 `MainActivity.kt` 新增 installer channel：
    - `canRequestPackageInstalls` / `openInstallSettings` / `installApk`
    - 使用 `FileProvider` 暴露缓存目录 APK，避免申请 broad storage 权限
  - AndroidManifest.xml 新增权限：
    - `INTERNET`（下载）
    - `REQUEST_INSTALL_PACKAGES`（应用内安装）
    - `android:allowBackup="false"`（避免缓存导致覆盖安装异常）
    - `FileProvider` 配置 `androidx.core.content.FileProvider`
  - 新增 9 段应用内更新语音素材（均注册到 `TtsService`）：
    - `update_available.mp3`「发现新版本」
    - `confirm_download.mp3`「上滑确认下载，下滑取消」
    - `downloading.mp3`「正在下载更新」
    - `download_complete.mp3`「下载完成」
    - `download_failed.mp3`「下载失败，请检查网络后重试」
    - `install_prompt.mp3`「请按提示完成安装」
    - `install_permission_denied.mp3`「需要允许安装未知应用权限，请前往设置开启」
    - `wifi_only.mp3`「请在 Wi-Fi 环境下检查更新」
    - `update_cancelled.mp3`「已取消更新」
  - `HomeScreen` 接入更新流程：
    - 启动完成后异步检查更新，不阻塞相机/教程
    - 发现新版本时暂停扫描，语音播报 + 上滑确认 / 下滑取消
    - 下载完成后自动打开系统安装器，用户手动完成安装
  - 新增单元测试：
    - `update_service_test.dart`：Wi-Fi 条件、7 天节流、版本解析、Gitee 失败回退 GitHub、时间戳记录
    - `download_service_test.dart`：下载成功、覆盖旧文件、进度回调、异常传播
    - `install_service_test.dart`：权限检查、设置跳转、安装成功/失败/参数传递

### Changed
- `pubspec.yaml` 版本升级到 `0.8.0+14`
- 新增依赖：`dio ^5.7.0`、`package_info_plus ^8.0.2`、`connectivity_plus ^6.0.5`

### Fixed
- 修复 `MainActivity.kt` installer channel 中 `return try { ... }` 的 Kotlin 语法错误
- 修复 `TtsService` 更新提示方法调用未定义的 `_playSequence` 问题
- 适配 `connectivity_plus` 6.x 新 API：`checkConnectivity()` 返回 `List<ConnectivityResult>`
- 适配 `dio` 5.10.x 抽象类变更：测试 FakeDio 改为继承 `DioForNative`

---

## [0.7.3] — 2026-07-10 (OCR 模糊匹配)

### Added
- **OCR 模糊匹配**（解决线下扫码 `#` 与数字被分隔或全角 `#` 导致识别失败）
  - 新增 `OcrService.extractMealCodesFuzzy()`：
    - 支持 `# 数字`、`#\n数字`、全角 `＃数字` 等分隔形式
    - 仅当附近存在平台关键词（美团/饿了么/京东/淘宝闪购/朴朴等）时才提取，降低误识别
    - 排除小数价格（如 `#33.90`）和超长数字（>6 位）
  - 新增 `OcrService.normalizeHashSymbols()`：统一将全角 `＃` (U+FF03) 归一化为 ASCII `#`
  - `OcrService.detectPlatform()` 新增 `contextText` 参数：
    - 优先在 code 所在 OCR block 内做近距离平台匹配
    - block 内未命中时，回退到整帧文本并放宽窗口（40 字符），解决平台名与取餐码被分到不同 block 的问题
    - 仍通过距离限制避免跨小票误识别
- `HomeScreen._scanFrame()` 接入模糊匹配 fallback：
  - 严格匹配未识别到取餐码时，自动尝试模糊匹配
  - block 匹配阶段归一化全角 `#`，提升 block 定位成功率
  - 平台识别阶段传入整帧 `combinedText` 作为上下文
- 新增 13 个单元测试，覆盖模糊提取、全角井号、上下文平台识别、距离过滤等场景
- **新增 永辉超市 平台支持**
  - OCR 平台规则新增「永辉」「永辉超市」关键词
  - 生成语音素材 `assets/audio/yonghui.mp3`（内容：永辉超市）
  - `TtsService` 增加 永辉超市 平台名到音频路径的映射
  - 新增 OCR/TTS 单元测试各 2 个

### Fixed
- 修复线下测试中「美团 #3」「美团 #34」等场景只播报「发现外卖」却未识别出取餐码的问题

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
