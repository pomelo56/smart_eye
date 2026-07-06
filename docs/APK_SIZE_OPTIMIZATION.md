# APK 体积优化

> 慧眼 SmartEye — 控制 APK 安装包大小，降低视障用户下载门槛。

## v0.6.2 当前状态

| 项目 | 优化前 | 优化后 | 节省 |
|------|--------|--------|------|
| debug APK | 237 MB（4 ABI）| **89 MB**（arm64-only）| -148 MB（-62%）|
| **release APK（实测）** | ~65 MB（全 ABI + 全部资产） | **31.6 MB** | -33.4 MB（-51%）|

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

### 1. ABI 过滤（已启用，同时影响 debug + release）

```gradle
// android/app/build.gradle
defaultConfig {
    ndk {
        abiFilters "arm64-v8a"
    }
}
```

**影响**：
- ✅ Release APK 体积减少 ~50%（65 MB → 31 MB）
- ✅ Debug APK 体积减少 ~62%（237 MB → 89 MB）
- ✅ 2019 年后的 Android 设备 100% 兼容
- ❌ 2018 年及以前的 armv7 设备不能装

**如需支持 armv7**：删除 `abiFilters` 块，构建时用 `flutter build apk --release --target-platform=android-arm,android-arm64`。

### 2. 孤儿音频清理（已启用）

`test/unit/services/audio_assets_inventory_test.dart` 会扫描 `assets/audio/`，断言所有 `.mp3` 都在 `lib/` 中被引用。新增或删除音频前必须通过该测试。

## 暂未启用（已评估）

| 方案 | 预估收益 | 风险 | 建议 |
|------|---------|------|------|
| 启用 R8 代码压缩 | -5-10 MB | 需测试 release 行为 | 下一版本 v0.7.0 评估 |
| ML Kit 仅下中文 | -5-8 MB | 视障用户遇到英文小票无法识别 | 不建议 |
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
