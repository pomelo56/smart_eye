# CHANGELOG — 慧眼 SmartEye

> 本文件记录慧眼 SmartEye 的所有功能变更。每次迭代必须更新。
> 格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/) 规范。

---

## [Unreleased]

### Added
- 多平台外卖取餐码支持：美团外卖、饿了么、京东外卖、淘宝闪购
- `OcrService.detectPlatform()` 方法：检测 OCR 文本中的平台名称
- 取餐码数字位数扩展：从 1-3 位扩展到 1-4 位（覆盖各平台）
- 调试日志记录检测到的平台名称
- 初始化项目结构和基础文档（PRD、AGENTS、SOUL、USER）
- grill-me 需求审查：通过 10+ 轮追问确认核心交互方案
- TDD 开发：OcrService（28 个测试）、TtsService（8 个测试）、MealCode（4 个测试）、HistoryService（6 个测试）
- HomeScreen：相机预览 + OCR 扫描 + 语音播报 + 手势识别 + 历史记录 + 距离反馈音 + 首次启动教程
- 音频兜底方案：14 个预录音频素材 + 数字动态拼接 + Android MediaPlayer 原生播放通道
- 手势操作：单击重听、三击重新识别、上滑播报历史记录、下滑播报操作帮助
- 历史记录：`HistoryService` 保存最近 5 条记录，24 小时自动过期清理
- 距离反馈音：检测到文字时播放慢提示音，识别到取餐码时播放快提示音
- 无障碍语义：HomeScreen 全屏包裹 `Semantics` 标签，描述操作方式
- 文档：`docs/HANDOVER.md`（未来 Agent 接手指南），更新 `AGENTS.md` 反映音频兜底方案

### Changed
- 取餐码识别范围：从仅支持美团 `# + 1-3位数字` 扩展为支持四大平台 `# + 1-4位数字`
- 语音播报语速：从 1.0x 提升到 1.3x（MediaPlayer playbackParams）
- 确认取餐码时不再播放 beep_fast 提示音，直接播报取餐码（避免音频叠加）
- 项目定位升级：从「盲人取餐小工具」升级为「慧眼 SmartEye — AI 视障寻物助手」
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
