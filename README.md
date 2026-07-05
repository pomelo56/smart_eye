# 慧眼 SmartEye

> AI 视障寻物助手 | TRAE AI 创造力大赛 · 社会服务赛道

面向视障人群的端侧 AI 寻物辅助工具。用户打开摄像头对准物品，AI 实时识别并通过语音播报结果，帮助视障用户"听见物品、找到东西"。

## 核心功能

| 功能 | 说明 |
|------|------|
| 外卖检测 | 实时检测画面中的外卖袋/外卖盒等物品（YOLOv8n） |
| 避障寻路 | 检测障碍物，语音引导方向（左/中/右 + 远近） |
| OCR 识别 | 识别外卖小票上的取餐人、取餐码、手机尾号、商家（PaddleOCR） |
| 语音播报 | 系统TTS朗读识别结果，带节流和优先级控制 |
| AI 验证层 | 检测时序连续性验证 + OCR 合理性校验，过滤误报 |
| 反馈闭环 | 一键保存错误帧和上下文，供后续模型微调 |

## 技术栈

- **语言**: Python 3.10+
- **物体检测**: Ultralytics YOLOv8n (MPS 加速)
- **OCR**: PaddleOCR PP-OCRv6 (中文)
- **图像采集**: OpenCV
- **语音播报**: pyttsx3 / macOS `say`
- **Web 演示**: Gradio
- **测试**: pytest

## 快速开始

### 环境要求

- macOS (开发环境，需 MPS 支持)
- Python 3.10+
- 摄像头权限（系统设置 → 隐私与安全性 → 摄像头）

### 安装

```bash
cd /Users/pomelo/Project/smart_eye
pip install -r requirements.txt
```

### 运行测试

```bash
python3 -m pytest tests/ -v
```

### 启动桌面版

```bash
python3 -m src.main
```

启动后操作键：

| 按键 | 功能 |
|------|------|
| 空格 | 触发 OCR 识别当前画面 |
| R | 重置语音节流 |
| F | 保存检测错误反馈 |
| O | 保存 OCR 错误反馈 |
| Q / ESC | 退出 |

### 启动 Web 演示版

```bash
# 本地访问
python3 tools/demo_web.py

# HTTPS 模式（可用手机浏览器访问摄像头）
python3 tools/demo_web.py --https

# ngrok 公网分享
python3 tools/demo_web.py --ngrok-api-key YOUR_KEY
```

## 项目结构

```
smart_eye/
├── src/
│   ├── config.py              # 全局配置 + 版本管理
│   ├── main.py                # 主程序入口
│   ├── camera.py              # 摄像头采集模块
│   ├── detector.py            # YOLO 物体检测模块
│   ├── ocr_engine.py          # PaddleOCR 文字识别模块
│   ├── navigation.py          # 避障/寻路提示模块
│   ├── speech.py              # 语音播报模块
│   ├── ai_guard/
│   │   ├── detection_validator.py   # 检测结果验证器
│   │   └── ocr_validator.py         # OCR 结果验证器
│   └── feedback/
│       └── feedback_collector.py    # 用户反馈收集模块
├── tests/                     # 单元测试
├── tools/
│   ├── demo_web.py            # Gradio Web 演示
│   └── view_feedback.py       # 反馈查看工具
├── models/                    # 模型文件（.gitignore）
├── data/                      # 测试数据
├── docs/
│   ├── CHANGELOG.md           # 版本变更记录
│   ├── specs/                 # 设计文档
│   └── plans/                 # 实施计划
├── smart-eye-proposal/        # 参赛提案页面
└── requirements.txt
```

## 版本管理

本项目使用 [SemVer](https://semver.org/) 语义化版本号，通过 git tag 管理版本。

```bash
# 查看所有版本
git tag -l

# 查看当前 Flutter App 版本
flutter --version
head -n 3 pubspec.yaml

# 切换到指定 tag（例如回滚到上一个稳定版）
git checkout v0.6.0
```

版本变更记录见 [docs/CHANGELOG.md](docs/CHANGELOG.md)。

## 开发路线

| 阶段 | 目标 | 状态 |
|------|------|------|
| 第一阶段 | Mac/Python MVP 算法验证 | ✅ 完成 (v0.2.0) |
| 第二阶段 | Flutter 移动端 App | 🚧 开发中 (当前 v0.6.0，详见 docs/CHANGELOG.md) |
| 第三阶段 | 真实用户测试与迭代 | 📋 待定 |

## 许可证

公益性项目，免费开源。
