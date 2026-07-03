# MEMORY.md - 慧眼 SmartEye 项目长期记录

## 项目关键决策

### 语音方案：预录音频 + Android MediaPlayer（最终选择）
- 原因：OPPO/ColorOS 等国产 ROM 不暴露可用的 TTS 引擎给应用，`flutter_tts` 初始化成功但无法播放。
- 实现：打包 14 个中文音频片段（数字 0-9、井、取餐码是、未识别提示、教程、帮助、快慢反馈音），通过原生 `MediaPlayer` 顺序播放。
- Dart 路径：`assets/audio/xxx.mp3`；Native 实际路径：`flutter_assets/assets/audio/xxx.mp3`。

### 已废弃方案
- `flutter_tts`：在 ColorOS 上 `getEngines` / `getDefaultEngine` 均返回空，无法使用。
- 自定义 TTS MethodChannel：已被移除，不再维护。

## 版本分支
- `master`：当前可用版本，即音频兜底方案（合并自 `fix/audio-fallback`）。
- `fix/tts-init-failure`：已删除工作树，保留分支历史，不建议回退。
- `fix/audio-fallback`：已合并并删除工作树。

## 常见设备问题
- 无线 ADB 连接会随端口变化断开，需要重新 `adb pair` + `adb connect`。
- 安装时如有多个设备，使用 `adb -s <ip:port> install -r smarteye-audio-fallback.apk`。
- 屏幕日志面板用于调试，Release 版本也会显示。

## 下一步建议
- 考虑用真人录音替换当前 `say` 生成的机器音，提升视障用户体验。
- 考虑优化 OCR 扫描频率和距离反馈音策略。
- 考虑去除屏幕日志面板，替换为更稳定的日志文件或无界面调试方式。
