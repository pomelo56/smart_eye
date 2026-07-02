# CHANGELOG — 慧眼 SmartEye

> 本文件记录慧眼 SmartEye 的所有功能变更。每次迭代必须更新。
> 格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/) 规范。

---

## [Unreleased]

### Added
- 初始化项目结构和基础文档（PRD、AGENTS、SOUL、USER）
- grill-me 需求审查：通过 10+ 轮追问确认核心交互方案
- TDD 开发：OcrService（16 个测试）、TtsService（8 个测试）、MealCode（4 个测试）
- HomeScreen：相机预览 + OCR 扫描 + TTS 播报 + 手势识别 + 历史记录

### Changed
- 项目定位升级：从「盲人取餐小工具」升级为「慧眼 SmartEye — AI 视障寻物助手」
- 项目名称统一为「慧眼 SmartEye」（TRAE AI 创造力大赛 · 社会服务赛道）
- 取餐码格式：从「4-6 位纯数字」修正为「`#` + 1-3 位数字」（美团外卖小票实际格式）
- 扫描机制：从「手动触发」改为「持续扫描（每 2 秒）+ 多帧验证（连续 2 次一致才播报）+ 5 秒冷却去重」
- 手势方案：从「单击确认/双击重识」改为「单击重听/三击重识/自动保存」
- 历史记录：从「永久保存」改为「保留 24 小时自动清除」
- 交互反馈：新增距离提示音（类似倒车雷达）、首次启动语音教程

### Fixed
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
