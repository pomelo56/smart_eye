# 05 - Flutter & Android 踩坑手册

> 本文档记录慧眼 SmartEye 开发过程中踩过的所有坑、失败的尝试、以及验证过的解决方案。每个坑都耗费了少则 30 分钟多则数小时的调试时间，阅读本文档可以帮你避免重复踩坑。

---

## 目录

- [Flutter/Dart 相关](#fluttdart-相关)
- [Android 原生相关](#android-原生相关)
- [音频系统相关](#音频系统相关)
- [相机与 OCR 相关](#相机与-ocr-相关)
- [权限相关](#权限相关)
- [构建与发布相关](#构建与发布相关)
- [Git 与版本管理相关](#git-与版本管理相关)
- [开发工具与环境相关](#开发工具与环境相关)

---

## Flutter/Dart 相关

### 坑 1：flutter_tts 在 OPPO/ColorOS 上完全无声

**症状**：`await flutterTts.speak("xxx")` 调用成功返回，但手机完全没有声音。系统 TTS 测试正常，其他应用（如微信朗读）可以发声。

**根因**：OPPO/ColorOS 对第三方应用绑定系统 TTS 引擎做了限制，`TextToSpeech.onInit` 回调静默返回 `ERROR`，没有任何错误码可以检测。

**解决方案**：放弃 flutter_tts，改用预录音频 + Android MediaPlayer 方案。详见 [04-音频系统实现](./04-音频系统实现.md)。

**重复踩坑次数**：1次（最开始尝试各种参数配置、换 TTS 引擎，浪费约 4 小时）

---

### 坑 2：debugPrint 在 release 模式下仍输出到 logcat

**症状**：以为 release 构建不会输出 debugPrint，结果安全审计发现 release APK 仍然通过 logcat 泄露 OCR 识别内容。

**根因**：Flutter 的 `debugPrint` 在 release 模式下默认仍然输出到 logcat，不会自动禁用。

**解决方案**：在 `main()` 中手动覆盖：
```dart
if (kReleaseMode) {
  debugPrint = (String? message, {int? wrapWidth}) {};
}
```

---

### 坑 3：GestureDetector 单击和多击的区分

**症状**：实现三击手势时，每次三击都会先触发一次单击。

**根因**：Flutter 的 `GestureDetector` 没有内置的多击识别，`onTap` 在第一次点击时立即触发，不会等待是否有后续点击。

**解决方案**：使用 Timer 延迟判断，600ms 内累计点击次数：
```dart
int _tapCount = 0;
DateTime? _lastTapTime;

void _handleTap() {
  _tapCount++;
  _lastTapTime = DateTime.now();
  Future.delayed(const Duration(milliseconds: 600), () {
    if (DateTime.now().difference(_lastTapTime!).inMilliseconds >= 600) {
      if (_tapCount == 1) _replay();
      else if (_tapCount >= 3) _rescan();
      _tapCount = 0;
    }
  });
}
```

---

### 坑 4：相机预览铺满屏幕时的比例问题

**症状**：CameraPreview 在不同屏幕比例上拉伸变形，OCR 识别率下降。

**根因**：相机传感器的宽高比与屏幕宽高比不一致。

**解决方案**：使用 `Transform.scale` + `AspectRatio` 裁剪，保持相机预览比例正确：
```dart
final size = MediaQuery.of(context).size;
final scale = _cameraController!.value.aspectRatio / size.aspectRatio;
Transform.scale(
  scale: scale < 1 ? 1 / scale : scale,
  child: Center(child: CameraPreview(_cameraController!)),
);
```

---

### 坑 5：setState() 在 dispose 后调用导致崩溃

**症状**：快速退出页面时，Timer 回调中调用 `setState()` 抛出异常。

**根因**：异步操作（Timer、Future 回调）在 Widget 销毁后仍然执行。

**解决方案**：在 `setState` 前检查 `mounted`：
```dart
if (mounted) {
  setState(() { /* ... */ });
}
```

---

## Android 原生相关

### 坑 6：flutter_assets 路径陷阱 ⭐ 高频踩坑

**症状**：原生 `assets.openFd("assets/audio/xxx.mp3")` 抛出 `FileNotFoundException`，但 Dart 层 `rootBundle.load("assets/audio/xxx.mp3")` 能正常加载。

**根因**：Flutter 打包时，asset 文件实际位于 APK 的 `assets/flutter_assets/` 目录下：
```
Dart 层路径:      assets/audio/xxx.mp3
APK 内实际路径:   assets/flutter_assets/assets/audio/xxx.mp3
```

**解决方案**：原生层必须加 `flutter_assets/` 前缀：
```kotlin
// ❌ 找不到文件
assets.openFd("assets/audio/xxx.mp3")

// ✅ 正确
assets.openFd("flutter_assets/assets/audio/xxx.mp3")
```

**重复踩坑次数**：3次（每次写新的原生 asset 读取都会忘）

---

### 坑 7：FileProvider 配置错误导致安装 APK 失败

**症状**：应用内更新下载完 APK 后，调用安装器报 `FileUriExposedException` 或"解析包时出现问题"。

**根因**：Android 7.0+ 不允许通过 `file://` URI 共享文件，必须使用 FileProvider 生成 `content://` URI。

**解决方案**：
1. 在 `AndroidManifest.xml` 中声明 FileProvider
2. 创建 `res/xml/file_paths.xml`，严格限制可访问目录
3. 使用 `FileProvider.getUriForFile()` 获取 URI
4. 授予 URI 临时读权限：`intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)`

**安全注意**：file_paths.xml 不要配置为根路径 `<external-path name="." path="."/>`，这会暴露整个存储。

---

### 坑 8：PackageInfo 请求在 Android 13+ 上的 flag 变化

**症状**：`packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)` 在 Android 13 上返回空签名。

**根因**：Android 13 (API 33) 废弃了 `GET_SIGNATURES`，改为 `GET_SIGNING_CERTIFICATES`。

**解决方案**：做版本兼容处理：
```kotlin
val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    PackageManager.GET_SIGNING_CERTIFICATES
} else {
    @Suppress("DEPRECATION")
    PackageManager.GET_SIGNATURES
}
val pi = pm.getPackageInfo(packageName, flags)
```

---

### 坑 9：cleartextTrafficPermitted 默认禁止

**症状**：Android 9+ 上 HTTP 请求失败，日志显示 `Cleartext HTTP traffic to X not permitted`。

**根因**：Android 9 (API 28) 起默认禁止明文 HTTP 流量。

**解决方案**（v0.8.5安全加固已处理）：
- 创建 `network_security_config.xml`
- 正式环境禁止明文流量
- 仅在 debug 模式下允许

---

## 音频系统相关

### 坑 10：音频叠加（连续 speak() 声音重叠）⭐ 高频踩坑

**症状**：连续调用两次 `_ttsService.speak()`，两个声音同时播放，嘈杂听不清。

**错误尝试**：
```dart
// ❌ 错误：用 delay 等待播放完成
await _ttsService.speak('A');
await Future.delayed(const Duration(seconds: 2)); // 猜测时长
await _ttsService.speak('B');
```
为什么错误？音频时长不确定（数字位数不同、平台名长度不同），2秒可能不够也可能太长。

**正确解决方案**（CVE-STYLE-018修复）：
1. Dart 层使用 `Future<void>? _playbackMutex` 互斥锁
2. 每次 `speak()` 前先 `await stop()`
3. 原生层 `stopPlayback()` 真正 stop + release MediaPlayer（不是设标志位）
4. 使用 `onCompletion` 回调精确等待播放完成
5. 原生层用 `AtomicBoolean` + `@Volatile` 保证多线程可见性

**重复踩坑次数**：3次

---

### 坑 11：MediaPlayer 资源泄漏

**症状**：连续播放几十次音频后，应用崩溃或无声音，logcat 显示 `MediaPlayer: error (-19, 0)`。

**根因**：创建了 MediaPlayer 但没有在播放完成后调用 `release()`，导致系统资源耗尽。

**解决方案**：在 `onCompletionListener` 和 `onErrorListener` 中必须 `release()`：
```kotlin
setOnCompletionListener { mp ->
    mp.release()
    currentPlayer = null
    playNext(paths, volume)
}
```

---

### 坑 12：MethodChannel 消息方向混乱

**症状**：Dart 调用原生方法后收不到回调，或者原生主动调用 Dart 方法时崩溃。

**根因**：MethodChannel 是双向的，但调用方向需要明确区分：
- Dart → Native：`channel.invokeMethod('methodName', args)`
- Native → Dart：`channel.invokeMethod('methodName', args)`（在原生线程中调用 Dart 注册的 handler）

**解决方案**：
- Dart 端在初始化时只注册一次 MethodCallHandler（用静态标志防止重复注册）
- 原生端在主线程 Handler 上执行 invokeMethod
- 使用 Completer 模式等待异步回调

---

## 相机与 OCR 相关

### 坑 13：相机首次初始化在 ColorOS 上超时

**症状**：OPPO 手机首次冷启动时，`CameraController.initialize()` 超过 15 秒超时，相机黑屏。

**根因**：ColorOS 系统动画、权限弹窗、Surface 绑定时序问题，相机服务启动慢。

**解决方案**：
- 自动重试 3 次，间隔递增（2s, 4s）
- 分辨率使用 `ResolutionPreset.high`（不是 `max`，过高分辨率反而可能初始化失败）
- 生命周期 `paused` 时彻底 dispose controller，`resumed` 时重新初始化
- 重试失败后语音告知用户"摄像头不可用，请检查权限"

---

### 坑 14：拍照文件的生命周期管理

**症状**：长时间使用后，应用缓存目录占满存储空间。

**根因**：`takePicture()` 生成临时 XMP/JPEG 文件，用完后没有删除。

**解决方案**：
- OCR 处理完成后在 `finally` 块中删除临时文件
- 即使 OCR 识别抛出异常，也要确保文件被删除
- 使用随机文件名（CVE-STYLE-008），避免文件名预测攻击

```dart
final tempFile = await _cameraController!.takePicture();
try {
  await _processImage(tempFile.path);
} finally {
  await tempFileFile.delete(); // 无论成功失败都删除
}
```

---

### 坑 15：ML Kit 旋转/方向处理

**症状**：竖屏拍照后，OCR 识别的文字坐标是横屏的，位置计算完全错误。

**根因**：ML Kit 的 InputImage 需要正确的 `imageRotation`，且不同设备传感器方向不同。

**解决方案**：使用 `InputImage.fromFilePath()` 时，camera 插件已经写入了 EXIF 方向信息，ML Kit 能自动处理。但手动旋转图像（180°倒置识别）时，坐标需要手动映射：
```dart
// 180°旋转后的坐标映射回正立坐标系
transformedBox = Rect.fromLTRB(
  imageWidth - block.boundingBox.right,
  imageHeight - block.boundingBox.bottom,
  imageWidth - block.boundingBox.left,
  imageHeight - block.boundingBox.top,
);
```

---

### 坑 16：取餐码正则误匹配

**症状**：小票上的订单号（长数字）、价格（如"¥15"）被误识别为取餐码。

**根因**：简单的 `#\d+` 正则太宽泛。

**解决方案**：
- 严格模式：必须匹配 `#` 后跟数字，且数字前后有边界
- 模糊模式：`#` 和数字间允许空格，但要求附近（8字符窗口内）有外卖平台关键词
- 多帧验证：连续2帧识别到相同结果才确认
- 最佳码选择：位数最多的码优先（真实取餐码通常比订单号短，不对...需要结合上下文）

---

## 权限相关

### 坑 17：shouldShowRequestPermissionRationale 在首次安装返回 false

**症状**：首次安装启动应用时，直接被判定为"永久拒绝"权限，跳转到设置页。

**根因**：`shouldShowRequestPermissionRationale()` 的返回值含义：
- 首次安装（从未请求过）→ 返回 `false`
- 用户拒绝过一次（没有选"不再询问"）→ 返回 `true`
- 用户选了"不再询问"（永久拒绝）→ 返回 `false`

首次安装和永久拒绝都返回 `false`，无法仅凭这个 API 区分！

**解决方案**：
1. 在 `noBackupFilesDir`（不是 SharedPreferences！）下创建一个标志文件
2. 请求过一次权限后，写入标志文件
3. 判定"永久拒绝"三条件：权限被拒 AND 标志文件存在 AND shouldShow...返回 false
4. 使用 `noBackupFilesDir` 而非 SharedPreferences 的原因：ColorOS/Google 备份会在卸载重装后恢复 SharedPreferences，导致新安装被误判

---

### 坑 18：SharedPreferences 被备份恢复导致权限标志错误

**症状**：卸载重装后，应用仍然认为用户曾经永久拒绝过权限。

**根因**：Android 默认备份会备份 SharedPreferences 到云端，重装时自动恢复。

**解决方案**：
- 权限请求标志文件放在 `noBackupFilesDir`（`context.noBackupFilesDir`），这个目录不会被备份
- 或在 `AndroidManifest.xml` 中设置 `android:allowBackup="false"`（v0.8.5已设置）

---

## 构建与发布相关

### 坑 19：Flutter SDK 缓存目录权限问题

**症状**：执行 `flutter pub get` 或 `flutter test` 时报权限错误，提示无法写入 `bin/cache` 目录。

**根因**：Flutter SDK 安装时使用了 sudo 或其他用户，导致 `bin/cache` 目录属于 root。

**解决方案**：
```bash
sudo chown -R $(whoami) <你的Flutter安装目录>/bin/cache
flutter pub get
```

---

### 坑 20：Release APK 用 debug 签名

**症状**：安装 Release APK 时提示"应用未安装"，或签名与旧版本不一致。

**根因**：没有配置 release signingConfig，Gradle 默认使用 debug keystore 签名 release 构建。

**解决方案**（v0.8.4已修复）：
1. 生成 release keystore：`keytool -genkey -v -keystore upload-keystore.jks ...`
2. 创建 `android/key.properties`（不提交到 git）
3. 在 `build.gradle` 中配置 signingConfigs：
```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
android {
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile file(keystoreProperties['storeFile'])
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```

---

### 坑 21：ABI 过滤导致模拟器无法安装

**症状**：配置了 `ndk.abiFilters = ["arm64-v8a"]` 后，Android 模拟器（x86_64）无法安装 APK。

**根因**：x86_64 模拟器需要 x86_64 的 native 库，但我们只打包了 arm64-v8a。

**解决方案**：这是预期行为——项目只支持真机（arm64-v8a），不支持模拟器。如果需要在模拟器上调试，暂时注释掉 abiFilters 配置。

---

### 坑 22：ProGuard/R8 混淆导致 ML Kit 崩溃

**症状**：Release APK 中 OCR 初始化崩溃，debug 模式正常。

**根因**：ProGuard/R8 混淆了 ML Kit 需要的类。

**解决方案**：在 `proguard-rules.pro` 中添加 ML Kit 的 keep 规则：
```proguard
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
```

---

### 坑 23：包名重命名需要修改多处

**症状**：将包名从 `com.example.smart_eye` 改为 `com.smart_eye` 后，编译失败或运行时崩溃。

**根因**：Android 包名分散在多个位置，只改一处不够。

**需要修改的位置**：
1. `android/app/build.gradle` 中的 `applicationId` 和 `namespace`
2. `android/app/src/main/AndroidManifest.xml` 中的 `package`
3. `MainActivity.kt` 的目录路径和包声明
4. `android/app/src/profile/AndroidManifest.xml` 和 `debug/AndroidManifest.xml` 中的 package
5. 原生 MethodChannel 不受包名影响（channel 名是字符串常量）

v0.9.0-rc1 已全部修复。

---

## Git 与版本管理相关

### 坑 24：git push --tags 不会创建 GitHub/Gitee Release

**症状**：执行了 `git push --tags`，但在 Gitee/GitHub Releases 页面看不到新版本。

**根因**：`git tag` 只是代码版本标记，`git push --tags` 只推送标签到仓库。Release 是附加了发布说明和构建产物（APK）的正式发布，需要通过平台 API 或网页手动创建。

**解决方案**：使用项目自带的发布脚本：
```bash
export GITEE_TOKEN=<你的令牌>
./scripts/release-gitee.sh v0.9.0-rc1 build/app/outputs/flutter-apk/app-release.apk
./scripts/release-github.sh v0.9.0-rc1 build/app/outputs/flutter-apk/app-release.apk
```

---

### 坑 25：awk 正则匹配 CHANGELOG 中的 [ 和 ]

**症状**：发布脚本提取 CHANGELOG 内容时始终为空，Release body 显示 fallback 链接。

**根因**：`[` 和 `]` 在正则表达式中是字符类元字符，不会被当作字面量匹配：
```bash
# ❌ 错误：[0.8.3] 被当作正则字符类
awk '$0 ~ "## [0.8.3]" { ... }'
```

**解决方案**：使用字符串精确匹配而非正则：
```bash
# ✅ 正确：使用 index() 做字符串匹配
awk 'index($0, "## [0.8.3]") == 1 { ... }'
```

---

### 坑 26：export 的环境变量只在当前 shell 有效

**症状**：在终端执行了 `export GITEE_TOKEN=xxx`，关闭终端后下次发布时提示找不到 token。

**根因**：`export` 设置的环境变量仅在当前 shell 会话有效。

**解决方案**：将 token 写入 `~/.zshrc`（或 `~/.bashrc`）持久化：
```bash
echo 'export GITEE_TOKEN=你的令牌' >> ~/.zshrc
source ~/.zshrc
```

**安全注意**：不要将 token 写入项目目录的任何文件中（包括脚本），避免被 commit 到仓库。

---

### 坑 27：release-github.sh 中 local 关键字在函数外使用

**症状**：执行 `./scripts/release-github.sh` 报错 `local: can only be used in a function`。

**根因**：bash 的 `local` 关键字只能在函数内部使用，脚本主体中不能使用。

**解决方案**：去掉 `local` 关键字，直接赋值。v0.9.0-rc1 已修复。

---

## 开发工具与环境相关

### 坑 28：无线 ADB 配对后显示两个设备

**症状**：`adb devices` 显示两个相同 IP 的设备，`adb install` 报 "more than one device and emulator"。

**根因**：`adb pair` 产生配对连接，`adb connect` 产生数据连接，两者都会显示在设备列表中。

**解决方案**：
```bash
adb disconnect           # 断开所有连接
adb connect IP:端口       # 只重新连接数据端口
adb devices               # 确认只有一个设备
```

---

### 坑 29：macOS 防火墙阻止 adb 连接

**症状**：无线 ADB 配对成功但连接失败，或连接后立即断开。

**根因**：macOS 防火墙阻止了 adb 的入站连接。

**解决方案**：系统设置 → 网络 → 防火墙 → 选项，将 `adb` 添加到允许列表。

---

### 坑 30：Hot Reload 不刷新原生代码

**症状**：修改了 MainActivity.kt 后，Hot Reload 不生效，必须重新运行。

**根因**：Flutter Hot Reload 只刷新 Dart 代码，不重新编译原生（Kotlin/Java）代码。

**解决方案**：
- Dart 代码改动：Hot Reload（`r` 键）即可
- 原生代码/资源文件改动：Hot Restart（`R` 键）或完全重新运行
- `pubspec.yaml` 改动（新增 asset）：需要完全重新运行

---

## 快速排错流程图

遇到问题时，按以下顺序排查：

```
没有声音？
├── 检查媒体音量（不是通话音量）
├── 检查是否 release 模式禁用了 debugPrint（语音不受影响，但日志看不到）
├── 检查 TtsService._mapTextToAssets() 是否包含目标文本
├── 检查 assets/audio/ 文件是否存在且在 pubspec.yaml 注册
└── 检查原生层是否加了 flutter_assets/ 前缀

相机黑屏？
├── 检查是否授予摄像头权限
├── 检查是否其他应用占用相机
├── 切到后台再返回触发生命周期重连
├── 检查 _initCameraWithRetry 重试是否 exhausted
└── 重启应用

OCR 识别不到？
├── 检查光线是否充足（听到"光线不足"提示）
├── 检查是否对准了小票（距离反馈音节奏）
├── 检查小票是否倒置（双方向OCR已处理，但确认一下）
├── 检查取餐码格式是否在支持范围内（#数字 或 平台+数字）
└── 确认是印刷体（手写体不支持）

手势不响应？
├── 检查是否有 IgnorePointer 或 AbsorbPointer 拦截
├── 检查 Semantics 是否包裹正确
├── 检查手势识别器的 velocity 阈值
└── 检查是否在 TalkBack 模式（TalkBack 需要双指操作）
```

---

## 待补充

本手册持续更新。遇到新坑后，请按照以下格式补充：

```markdown
### 坑 N：问题简述

**症状**：用户能观察到的现象

**根因**：为什么会发生

**解决方案**：怎么修复的（附代码）

**重复踩坑次数**：N次（可选）
```
