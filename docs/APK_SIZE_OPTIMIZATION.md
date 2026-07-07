# APK 体积优化

> 慧眼 SmartEye — 控制 APK 安装包大小，降低视障用户下载门槛。

## v0.7.0 当前状态

| 项目 | 优化前 | 优化后 | 节省 |
|------|--------|--------|------|
| debug APK | 237 MB（4 ABI）| **89 MB**（arm64-only）| -148 MB（-62%）|
| **release APK（实测）** | ~65 MB（v0.6.0 全 ABI）| **30.2 MB**（R8 + arm64-only）| -34.8 MB（-54%）|

> v0.7.0 较 v0.6.1 的 31.6 MB 又省了 1.4 MB（R8 缩了 classes.dex）。
> 30 MB 是当前工具链下的「实际下限」：剩余体积主要是 Dart AOT + Flutter 引擎 + ML Kit 中文模型三者合计 ~25 MB。

### release APK 30.2 MB 分布（v0.7.0）

| 项 | 大小 | 占比 | 是否可压 |
|----|------|------|----------|
| `libflutter.so`（Flutter 引擎）| 10.7 MB | 35% | ❌ 引擎层 |
| `libmlkit_google_ocr_pipeline.so`（中文模型）| 11.1 MB | 37% | ⚠️ v0.8.0 评估懒加载 |
| `libapp.so`（Dart AOT）| 3.4 MB | 11% | ❌ AOT 编译产物 |
| `classes.dex`（Java/Kotlin）| 4.3 MB | 14% | ✅ 已 R8 |
| 音频 + flutter_assets | 2.9 MB | 10% | ✅ 已有清单测试 |
| 其它（manifest/资源/签名）| ~0.5 MB | 2% | ❌ 必需 |

### debug APK 89 MB 分布

| 项 | 大小 | 占比 |
|----|------|------|
| arm64-v8a 原生库（含 Dart 调试符号）| 61 MB | 73% |
| Kotlin 元数据 + kapt 注解 | 22 MB | 17% |
| flutter_assets + 音频 | 2.9 MB | 3% |
| 其它 | 3.1 MB | 4% |

> Debug APK 不可能压到 30 MB：它必须保留 Dart 调试符号、Hot Reload 引擎、Kotlin kapt 注解供 `flutter run` 使用。

### release APK 31.6 MB 分布

| 项 | 大小 | 占比 |
|----|------|------|
| arm64-v8a 原生库 | 24.1 MB | 76% |
| Kotlin/Dart dex | 3.8 MB | 12% |
| assets (音频+flutter_assets) | 2.9 MB | 9% |
| 其它（manifest/资源）| 0.8 MB | 3% |

### 历史变更

- **v0.6.1**：`ndk.abiFilters = "arm64-v8a"` 写在 `defaultConfig` 里——**同时影响 debug 和 release**
- **v0.6.2**：确认 debug 也只打 arm64，体积从 237 MB 降至 89 MB

## 已采用的优化

### 1. ABI 过滤（v0.6.1 启用，同时影响 debug + release）

```gradle
// android/app/build.gradle
defaultConfig {
    ndk {
        abiFilters "arm64-v8a"
    }
}
```

**影响**：
- ✅ Release APK 体积减少 ~50%（65 MB → 30 MB）
- ✅ Debug APK 体积减少 ~62%（237 MB → 89 MB）
- ✅ 2019 年后的 Android 设备 100% 兼容
- ❌ 2018 年及以前的 armv7 设备不能装

**如需支持 armv7**：删除 `abiFilters` 块，构建时用 `flutter build apk --release --target-platform=android-arm,android-arm64`。

### 2. 孤儿音频清理（v0.6.1 启用）

`test/unit/services/audio_assets_inventory_test.dart` 会扫描 `assets/audio/`，断言所有 `.mp3` 都在 `lib/` 中被引用。新增或删除音频前必须通过该测试。

### 3. R8 代码压缩 + 资源压缩（v0.7.0 启用）

```gradle
// android/app/build.gradle release 块
release {
    minifyEnabled true        // R8 移除未引用的 Java/Kotlin
    shrinkResources true      // 移除未引用的 drawable/string
    proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'),
                  'proguard-rules.pro'
}
```

**实测收益**：
- `classes.dex` 从 8-10 MB 压缩到 4.3 MB（-50%）
- release APK 总体 31.6 MB → 30.2 MB（-1.4 MB / -4%）
- 收益偏小是因为 v0.6.1 已经把 ABI 砍完，剩余大件（Flutter 引擎、ML Kit 模型）不受 R8 影响

**必需 keep 规则**（在 `proguard-rules.pro`）：
- `com.google.mlkit.vision.text.**`（ML Kit 反射）
- `io.flutter.**`（Flutter 引擎反射）
- `com.example.smart_eye.MainActivity`（MethodChannel 入口）
- `android.hardware.camera2.**`（camera 插件反射）
- `-dontwarn com.google.android.play.core.splitcompat.**`（项目走直接 APK，不需要 Play Core）

**回归保护**：`test/unit/build/build_config_test.dart`（v0.7.0 新增）断言以上 5 项配置都在。任何人修改 build.gradle 删掉 R8，单测会立即失败。

**首次启用踩坑**：
- R8 默认会因 `FlutterPlayStoreSplitApplication` 引用 `SplitCompatApplication` 而报 missing class 错误
- 解决：`-dontwarn com.google.android.play.core.splitcompat.**`（项目不发 Google Play，不存在该类）
- 详见 `build/app/outputs/mapping/release/missing_rules.txt`（R8 自动生成）

## 暂未启用（已评估）

| 方案 | 预估收益 | 风险 | 建议 |
|------|---------|------|------|
| ML Kit 懒加载（首次扫描时下载中文模型）| -10 MB | 首次需联网；离线用户首次失败 | v0.8.0 评估 |
| ML Kit 仅下中文（移除拉丁/日韩）| -5-8 MB | 视障用户遇到英文小票无法识别 | 不建议 |
| AAB 动态分发 | 取决于商店 | Gitee 直接发 APK 不适用 | 仅 Google Play 渠道 |
| 音频转真 MP3 | -0.1 MB | 工作量大收益小 | 不建议 |

## 构建命令

```bash
# 完整 release 构建（已默认 arm64）
flutter build apk --release

# 同时生成 arm64-only APK + per-ABI 包
flutter build apk --release --split-per-abi

# 输出位置
ls -lh build/app/outputs/flutter-apk/app-*.apk
```

## 监控清单（每次发布前）

1. 运行 `flutter test test/unit/services/audio_assets_inventory_test.dart` 确保音频无孤儿
2. 检查 `assets/audio/` 总大小 `du -sh assets/audio/`，baseline 应 < 500 KB
3. release APK 大小 baseline < 25 MB
4. 用 Android Studio APK Analyzer 检查 `lib/arm64-v8a/` 体积，确认无意外膨胀

## 历史

- 2026-07-06 v0.6.1：首次优化（ABI 过滤 + 孤儿清理），release APK 从 ~65 MB → ~31.6 MB
- 2026-07-06 v0.6.2：debug APK 验证同步生效，237 MB → 89 MB
- 2026-07-07 v0.7.0：启用 R8 + 资源压缩，release APK 31.6 MB → 30.2 MB；新增 build_config_test.dart 回归保护
