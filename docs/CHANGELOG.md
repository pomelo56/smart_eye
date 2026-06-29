# Changelog

所有重要的版本变更都会记录在此文档。

## [v0.2.0] - 2026-06-25

### AI 验证层与用户反馈闭环

参考 Harness Engineering 思路，增加 AI 输出验证层和用户反馈闭环，提升系统可靠性和可迭代性。

#### 新增功能

- **AI 验证层 - 检测结果验证器** (`src/ai_guard/detection_validator.py`)
  - 时空连续性验证：连续 N 帧检测到同一目标才确认（IOU 匹配）
  - 置信度门槛过滤：低于阈值的结果不播报
  - 检测框合理性校验：过滤太小/太大的检测框
  - 按类别差异化置信度阈值
  - 稳定性分数（stability_score）输出
  - 37 个单元测试，全部通过

- **AI 验证层 - OCR 结果验证器** (`src/ai_guard/ocr_validator.py`)
  - 整体置信度验证：平均置信度低于阈值则结果不可靠
  - 取餐码合理性校验：格式、长度、字符合规性检查
  - 手机尾号严格校验：必须 4 位纯数字
  - 取餐人姓名校验：中英文支持，过滤纯数字/纯符号
  - 商家名称校验
  - 综合验证返回 validated_info + overall_valid + confidence_score
  - 60 个单元测试，全部通过

- **用户反馈收集模块** (`src/feedback/feedback_collector.py`)
  - 一键保存当前画面 + 识别上下文
  - 支持两种反馈类型：detection_error（检测错误）、ocr_error（OCR错误）
  - 按日期分目录存储（图片 + JSON 元数据）
  - 反馈列表查询、数量统计、清空功能
  - 自动创建存储目录

- **反馈查看工具** (`tools/view_feedback.py`)
  - 列出所有反馈（支持按类型/日期过滤）
  - 查看单条反馈详情
  - 统计反馈总数
  - 清空反馈（需确认）
  - 不依赖 OpenCV，纯标准库实现

#### 主程序更新 (`src/main.py`)

- 集成 DetectionValidator：所有检测结果先验证再播报
- 集成 OCRValidator：OCR 结果验证后再语音输出
- 识别不确定时提示"请靠近再试一次"，而非直接播报错误结果
- 新增快捷键 F：保存检测错误反馈
- 新增快捷键 O：保存 OCR 错误反馈
- 保存反馈时语音提示数量
- 检测框可视化增加稳定性标记（S 数字，稳定的框更粗）

#### 配置项新增 (`src/config.py`)

```
# 检测验证配置
DETECTION_MIN_STABLE_FRAMES = 2
DETECTION_MIN_CONFIDENCE = 0.5
DETECTION_MIN_BBOX_SIZE = 20
DETECTION_MAX_BBOX_RATIO = 0.9
DETECTION_CLASS_CONFIDENCE_OVERRIDES = {"person": 0.6}

# OCR验证配置
OCR_MIN_CONFIDENCE = 0.6
OCR_MAX_PICKUP_CODE_LEN = 20
OCR_MAX_NAME_LEN = 20

# 反馈配置
FEEDBACK_DIR = "data/feedback"
```

#### 测试

- 新增 97 个单元测试
- 总测试数：187 个，全部通过
- 零回归

### 操作键更新

| 按键 | 功能 |
|------|------|
| 空格 | 触发 OCR 识别 |
| R | 重置语音节流 |
| F | 保存检测错误反馈 |
| O | 保存 OCR 错误反馈 |
| Q / ESC | 退出 |

## [v0.1.0] - 2026-06-24

### 首次发布 (Phase 1)

MVP 第一阶段完成，实现了盲人外卖识别辅助工具的核心功能。

#### 新增功能

- **物体检测模块** (`src/detector.py`)
  - 基于 YOLOv8n 的实时物体检测
  - 支持 80 类 COCO 物体识别
  - 可按类别过滤检测结果

- **OCR 识别模块** (`src/ocr_engine.py`)
  - 基于 PaddleOCR 的文字识别
  - 支持外卖单关键信息提取（取餐人、取餐码、手机尾号、商家）
  - 懒加载模式，首次使用时初始化
  - 文本信息格式化用于语音播报

- **导航/避障模块** (`src/navigation.py`)
  - 三区域（左右中）障碍物分析
  - 基于检测框位置和大小估算距离
  - 外卖目标优先检测和语音引导
  - 支持左右方向和远近距离提示

- **语音播报模块** (`src/speech.py`)
  - 基于系统 TTS 的语音输出
  - 多类别节流控制（避免重复播报）
  - OCR 结果零节流（每次都播报）
  - 支持分类重置节流

- **主程序** (`src/main.py`)
  - 摄像头实时画面采集和显示
  - 检测框可视化（红=障碍物，绿=外卖，蓝=其他）
  - 键盘交互（空格=OCR，R=重置，Q=退出）
  - OCR 懒加载机制

#### 配置项 (`src/config.py`)

- YOLO 模型配置（置信度阈值、IOU阈值、计算设备）
- OCR 配置（语言、角度分类）
- 导航参数（区域划分、距离计算）
- 语音节流配置
- 分类配置（障碍物类别、外卖相关类别）

#### 测试

- 90 个单元测试，全部通过
- 覆盖：语音播报(12)、OCR文本逻辑(33)、导航分析(45)
- 集成测试验证所有模块协同工作

#### 技术栈

- Python 3.10+
- OpenCV (opencv-python)
- Ultralytics YOLOv8
- PaddlePaddle + PaddleOCR
- PyTorch
- pytest

#### 已知限制

- 摄像头需要 macOS 系统授权（系统设置 → 隐私与安全性 → 摄像头）
- 中文 OCR 识别效果待真实场景验证
- 外卖检测使用通用 YOLO 模型，可能需要针对外卖场景微调
- YOLO 模型尚未针对外卖/小票场景微调

#### 项目结构

```
blind_find/
├── src/
│   ├── main.py              # 主程序入口
│   ├── camera.py            # 摄像头采集模块
│   ├── detector.py          # YOLO 物体检测模块
│   ├── ocr_engine.py        # OCR 识别模块
│   ├── navigation.py        # 导航/避障模块
│   ├── speech.py            # 语音播报模块
│   └── config.py            # 配置参数
├── tests/                   # 单元测试
├── models/                  # YOLO 模型文件
├── docs/                    # 设计文档和计划
│   ├── specs/              # 规格说明书
│   └── plans/              # 实施计划
├── requirements.txt        # Python 依赖
└── .gitignore             # Git 忽略文件
```

#### 如何使用

```bash
# 安装依赖
pip install -r requirements.txt

# 运行测试
python3.10 -m pytest tests/ -v

# 启动程序（需要摄像头授权）
python3.10 -m src.main
```

---

## 版本历史格式说明

每个版本包含以下部分：

- **版本号** - 语义化版本 (SemVer)
- **日期** - 发布日期 (YYYY-MM-DD)
- **新增 (Added)** - 新功能
- **修改 (Changed)** - 功能变更
- **废弃 (Deprecated)** - 即将废弃的功能
- **修复 (Fixed)** - bug 修复
- **移除 (Removed)** - 移除的功能
- **安全 (Security)** - 安全相关变更
