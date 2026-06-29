# 盲寻 MVP（第一阶段：Mac端）实施计划

> **For agentic workers:** 按照任务顺序逐个实现，每完成一个任务进行测试验证。步骤使用 checkbox (`- [ ]`) 语法跟踪进度。

**Goal:** 在 Mac 上实现一个可运行的外卖查找辅助工具，包含实时物体检测、避障提示、OCR 识别和语音播报功能。

**Architecture:** 模块化设计，主循环逐帧采集图像，分发到检测、避障、OCR 模块处理，通过统一的语音模块输出结果。各模块独立、接口清晰，便于后续移植到移动端。

**Tech Stack:** Python 3.10+, OpenCV, Ultralytics YOLOv8, PaddleOCR, pyttsx3 / macOS say

---

## 文件结构

| 文件路径 | 职责 | 状态 |
|----------|------|------|
| `requirements.txt` | Python 依赖清单 | 新建 |
| `src/config.py` | 全局配置参数 | 新建 |
| `src/camera.py` | 摄像头采集模块 | 新建 |
| `src/speech.py` | 语音播报模块（含节流控制） | 新建 |
| `src/detector.py` | YOLO 物体检测模块 | 新建 |
| `src/ocr_engine.py` | PaddleOCR 文字识别模块 | 新建 |
| `src/navigation.py` | 避障/寻路提示模块 | 新建 |
| `src/main.py` | 主程序入口，主循环 | 新建 |
| `data/` | 测试图片/视频目录 | 新建 |
| `models/` | 模型文件目录（.gitignore） | 新建 |

---

## Task 1: 项目初始化与依赖配置

**Files:**
- Create: `requirements.txt`
- Create: `src/__init__.py`
- Create: `src/config.py`
- Create: `models/.gitkeep`
- Create: `data/.gitkeep`

- [ ] **Step 1: 创建 requirements.txt**

```txt
# 核心依赖
opencv-python>=4.8.0
numpy>=1.24.0

# 物体检测
ultralytics>=8.0.0
torch>=2.0.0
torchvision>=0.15.0

# OCR
paddlepaddle>=2.5.0
paddleocr>=2.7.0

# 语音播报
pyttsx3>=2.90

# 工具
Pillow>=10.0.0
```

- [ ] **Step 2: 创建 src/config.py**

```python
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
MODELS_DIR = BASE_DIR / "models"
DATA_DIR = BASE_DIR / "data"

CAMERA_INDEX = 0
FRAME_WIDTH = 640
FRAME_HEIGHT = 480
TARGET_FPS = 30

YOLO_MODEL = "yolov8n.pt"
YOLO_CONFIDENCE_THRESHOLD = 0.5
YOLO_IOU_THRESHOLD = 0.45
YOLO_DEVICE = "mps"

PADDLEOCR_LANG = "ch"
PADDLEOCR_USE_ANGLE_CLS = True

SPEECH_RATE = 200
SPEECH_VOLUME = 1.0

OBSTACLE_CLASSES = {"person", "chair", "couch", "table", "bottle", "backpack", "suitcase", "book"}
TAKEOUT_CLASSES = {"backpack", "suitcase", "book", "bottle", "cup", "bowl", "laptop"}

SPEECH_THROTTLE_SECONDS = {
    "obstacle": 3.0,
    "takeout": 2.0,
    "ocr": 0.0,
}

NAVIGATION_ZONES = 3
```

- [ ] **Step 3: 创建空的 `src/__init__.py`**

```python

```

- [ ] **Step 4: 创建 models 和 data 目录占位文件**

创建 `models/.gitkeep` 和 `data/.gitkeep`（空文件）

- [ ] **Step 5: 验证目录结构**

Run: `ls -la /Users/pomelo/Project/blind_find/`
Expected: 能看到 docs/, src/, models/, data/, requirements.txt

---

## Task 2: 摄像头采集模块

**Files:**
- Create: `src/camera.py`
- Test: 手动验证（无法自动化测试摄像头）

- [ ] **Step 1: 编写摄像头模块**

```python
import cv2
from src.config import FRAME_WIDTH, FRAME_HEIGHT, CAMERA_INDEX


class Camera:
    def __init__(self, camera_index=CAMERA_INDEX):
        self.cap = cv2.VideoCapture(camera_index)
        if not self.cap.isOpened():
            raise RuntimeError(f"无法打开摄像头，索引: {camera_index}")
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)

    def read(self):
        ret, frame = self.cap.read()
        if not ret:
            return None
        return frame

    def release(self):
        self.cap.release()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.release()
```

- [ ] **Step 2: 手动验证摄像头（可选，需要用户确认）**

Run: `python -c "import cv2; cap=cv2.VideoCapture(0); ret,frame=cap.read(); print('摄像头状态:', '正常' if ret else '失败'); cap.release()"`
Expected: 输出 "摄像头状态: 正常"

---

## Task 3: 语音播报模块

**Files:**
- Create: `src/speech.py`
- Test: 手动验证

- [ ] **Step 1: 编写语音播报模块**

```python
import time
import subprocess
import threading
from collections import defaultdict
from src.config import SPEECH_THROTTLE_SECONDS, SPEECH_RATE, SPEECH_VOLUME


class SpeechEngine:
    def __init__(self):
        self._last_speak_time = defaultdict(float)
        self._last_message = {}
        self._lock = threading.Lock()
        self._init_engine()

    def _init_engine(self):
        try:
            import pyttsx3
            self.engine = pyttsx3.init()
            self.engine.setProperty("rate", SPEECH_RATE)
            self.engine.setProperty("volume", SPEECH_VOLUME)
            self._use_pyttsx3 = True
        except ImportError:
            self._use_pyttsx3 = False

    def speak(self, text, category="info", priority=1):
        with self._lock:
            now = time.time()
            throttle = SPEECH_THROTTLE_SECONDS.get(category, 1.0)
            last_time = self._last_speak_time.get(category, 0)
            last_msg = self._last_message.get(category, "")

            if throttle > 0 and (now - last_time) < throttle and last_msg == text:
                return

            self._last_speak_time[category] = now
            self._last_message[category] = text

        threading.Thread(target=self._speak_async, args=(text,), daemon=True).start()

    def _speak_async(self, text):
        if self._use_pyttsx3:
            try:
                self.engine.say(text)
                self.engine.runAndWait()
            except Exception:
                self._fallback_speak(text)
        else:
            self._fallback_speak(text)

    def _fallback_speak(self, text):
        try:
            subprocess.run(["say", "-r", str(SPEECH_RATE), text], check=False)
        except Exception:
            print(f"[语音] {text}")

    def reset_throttle(self, category=None):
        with self._lock:
            if category:
                self._last_speak_time[category] = 0
            else:
                self._last_speak_time.clear()
```

- [ ] **Step 2: 验证语音模块**

Run: `python -c "from src.speech import SpeechEngine; s=SpeechEngine(); s.speak('语音模块测试正常', 'test'); import time; time.sleep(2)"`
Expected: 听到"语音模块测试正常"

---

## Task 4: YOLO 物体检测模块

**Files:**
- Create: `src/detector.py`
- Test: 用测试图片验证检测结果

- [ ] **Step 1: 编写物体检测模块**

```python
from ultralytics import YOLO
from src.config import (
    YOLO_MODEL, YOLO_CONFIDENCE_THRESHOLD,
    YOLO_IOU_THRESHOLD, YOLO_DEVICE, MODELS_DIR
)
from pathlib import Path


class ObjectDetector:
    def __init__(self, model_path=None):
        if model_path is None:
            model_path = MODELS_DIR / YOLO_MODEL
            if not Path(model_path).exists():
                model_path = YOLO_MODEL

        self.model = YOLO(str(model_path))
        self.conf = YOLO_CONFIDENCE_THRESHOLD
        self.iou = YOLO_IOU_THRESHOLD
        self.device = YOLO_DEVICE
        self.class_names = self.model.names

    def detect(self, frame):
        results = self.model(
            frame,
            conf=self.conf,
            iou=self.iou,
            device=self.device,
            verbose=False
        )
        detections = []
        for result in results:
            for box in result.boxes:
                x1, y1, x2, y2 = box.xyxy[0].tolist()
                conf = box.conf[0].item()
                cls_id = int(box.cls[0].item())
                cls_name = self.class_names[cls_id]
                detections.append({
                    "bbox": (int(x1), int(y1), int(x2), int(y2)),
                    "confidence": conf,
                    "class_id": cls_id,
                    "class_name": cls_name,
                })
        return detections

    def filter_by_classes(self, detections, class_set):
        return [d for d in detections if d["class_name"] in class_set]
```

- [ ] **Step 2: 下载 YOLOv8n 模型（首次运行自动下载）**

Run: `python -c "from ultralytics import YOLO; model = YOLO('yolov8n.pt'); print('模型加载成功')"`
Expected: 输出"模型加载成功"，模型文件自动下载到当前目录

- [ ] **Step 3: 将模型移动到 models 目录**

Run: `mv /Users/pomelo/Project/blind_find/yolov8n.pt /Users/pomelo/Project/blind_find/models/ 2>/dev/null || echo "模型文件可能已在正确位置"`

---

## Task 5: OCR 识别模块

**Files:**
- Create: `src/ocr_engine.py`
- Test: 用测试图片验证识别结果

- [ ] **Step 1: 编写 OCR 模块**

```python
import re
from src.config import PADDLEOCR_LANG, PADDLEOCR_USE_ANGLE_CLS


class OCREngine:
    def __init__(self):
        from paddleocr import PaddleOCR
        self.ocr = PaddleOCR(
            use_angle_cls=PADDLEOCR_USE_ANGLE_CLS,
            lang=PADDLEOCR_LANG,
            show_log=False
        )

    def recognize(self, image):
        result = self.ocr.ocr(image, cls=True)
        if not result or not result[0]:
            return []

        texts = []
        for line in result[0]:
            box = line[0]
            text = line[1][0]
            confidence = line[1][1]
            texts.append({
                "text": text,
                "confidence": confidence,
                "box": box,
            })
        return texts

    def extract_takeout_info(self, ocr_results):
        full_text = "\n".join([r["text"] for r in ocr_results])
        info = {
            "customer_name": None,
            "pickup_code": None,
            "merchant": None,
            "phone_tail": None,
            "raw_text": full_text,
        }

        name_patterns = [
            r"取餐人[：:]\s*(\S+)",
            r"收件人[：:]\s*(\S+)",
            r"顾客[：:]\s*(\S+)",
            r"姓名[：:]\s*(\S+)",
        ]
        for pattern in name_patterns:
            match = re.search(pattern, full_text)
            if match:
                info["customer_name"] = match.group(1)
                break

        code_patterns = [
            r"取餐码[：:]\s*(\d+[A-Za-z]*)",
            r"取餐号[：:]\s*(\d+)",
            r"订单号[：:]\s*(\d+)",
            r"取餐编号[：:]\s*(\d+)",
        ]
        for pattern in code_patterns:
            match = re.search(pattern, full_text)
            if match:
                info["pickup_code"] = match.group(1)
                break

        phone_patterns = [
            r"(\d{4})\*+\d{4}",
            r"手机尾号[：:]\s*(\d{4})",
            r"尾号[：:]\s*(\d{4})",
        ]
        for pattern in phone_patterns:
            match = re.search(pattern, full_text)
            if match:
                info["phone_tail"] = match.group(1)
                break

        return info

    def format_speech(self, info):
        parts = []
        if info["customer_name"]:
            parts.append(f"取餐人{info['customer_name']}")
        if info["pickup_code"]:
            parts.append(f"取餐码{info['pickup_code']}")
        if info["phone_tail"]:
            parts.append(f"手机尾号{info['phone_tail']}")
        if info["merchant"]:
            parts.append(f"商家{info['merchant']}")

        if not parts:
            return "未识别到有效信息"
        return "，".join(parts)
```

- [ ] **Step 2: 验证 PaddleOCR 安装和模型下载**

Run: `python -c "from paddleocr import PaddleOCR; ocr = PaddleOCR(use_angle_cls=True, lang='ch', show_log=False); print('PaddleOCR初始化成功')"`
Expected: 输出"PaddleOCR初始化成功"（首次运行会下载模型，需要等待）

---

## Task 6: 避障/寻路提示模块

**Files:**
- Create: `src/navigation.py`
- Test: 单元测试

- [ ] **Step 1: 编写导航模块**

```python
from src.config import NAVIGATION_ZONES, OBSTACLE_CLASSES, TAKEOUT_CLASSES


class NavigationGuide:
    def __init__(self, frame_width=640, frame_height=480):
        self.frame_width = frame_width
        self.frame_height = frame_height
        self.zones = NAVIGATION_ZONES

    def get_zone(self, bbox):
        x1, y1, x2, y2 = bbox
        center_x = (x1 + x2) / 2
        zone_width = self.frame_width / self.zones

        if center_x < zone_width:
            return "left"
        elif center_x < zone_width * 2:
            return "center"
        else:
            return "right"

    def get_distance_estimate(self, bbox):
        x1, y1, x2, y2 = bbox
        box_height = y2 - y1
        ratio = box_height / self.frame_height

        if ratio < 0.15:
            return "far"
        elif ratio < 0.4:
            return "medium"
        else:
            return "near"

    def zone_to_chinese(self, zone):
        mapping = {"left": "左侧", "center": "正前方", "right": "右侧"}
        return mapping.get(zone, "前方")

    def distance_to_chinese(self, distance):
        mapping = {"far": "远处", "medium": "不远处", "near": "就在眼前"}
        return mapping.get(distance, "")

    def analyze_obstacles(self, detections):
        obstacles = [d for d in detections if d["class_name"] in OBSTACLE_CLASSES]
        if not obstacles:
            return None, []

        zones_with_obstacles = set()
        nearest_obstacle = None
        nearest_area = 0

        for det in obstacles:
            zone = self.get_zone(det["bbox"])
            zones_with_obstacles.add(zone)

            x1, y1, x2, y2 = det["bbox"]
            area = (x2 - x1) * (y2 - y1)
            if area > nearest_area:
                nearest_area = area
                nearest_obstacle = det

        prompts = []
        if "center" in zones_with_obstacles:
            prompts.append("正前方有障碍物，请小心")
        if "left" in zones_with_obstacles and "right" not in zones_with_obstacles:
            prompts.append("左侧有障碍物，请靠右走")
        if "right" in zones_with_obstacles and "left" not in zones_with_obstacles:
            prompts.append("右侧有障碍物，请靠左走")
        if "left" in zones_with_obstacles and "right" in zones_with_obstacles and "center" not in zones_with_obstacles:
            prompts.append("两侧都有障碍物，请走中间")

        return nearest_obstacle, prompts

    def analyze_takeout(self, detections):
        takeouts = [d for d in detections if d["class_name"] in TAKEOUT_CLASSES]
        if not takeouts:
            return None, ""

        best = max(takeouts, key=lambda d: d["confidence"])
        zone = self.get_zone(best["bbox"])
        distance = self.get_distance_estimate(best["bbox"])
        zone_cn = self.zone_to_chinese(zone)
        dist_cn = self.distance_to_chinese(distance)

        prompt = f"{zone_cn}{dist_cn}发现疑似外卖"
        return best, prompt
```

- [ ] **Step 2: 验证导航模块逻辑**

Run: 
```bash
python -c "
from src.navigation import NavigationGuide
guide = NavigationGuide(640, 480)
dets = [{'bbox': (300, 200, 400, 400), 'class_name': 'person', 'confidence': 0.9}]
nearest, prompts = guide.analyze_obstacles(dets)
print('障碍物提示:', prompts)
takeout_dets = [{'bbox': (100, 100, 200, 300), 'class_name': 'backpack', 'confidence': 0.8}]
best, prompt = guide.analyze_takeout(takeout_dets)
print('外卖提示:', prompt)
"
```
Expected: 输出障碍物提示和外卖提示的中文文本

---

## Task 7: 主程序整合

**Files:**
- Create: `src/main.py`
- Test: 端到端运行测试

- [ ] **Step 1: 编写主程序**

```python
import cv2
import sys
from src.camera import Camera
from src.detector import ObjectDetector
from src.ocr_engine import OCREngine
from src.navigation import NavigationGuide
from src.speech import SpeechEngine
from src.config import FRAME_WIDTH, FRAME_HEIGHT


class BlindFindApp:
    def __init__(self):
        print("[系统] 正在初始化各模块...")
        self.camera = Camera()
        self.detector = ObjectDetector()
        self.navigation = NavigationGuide(FRAME_WIDTH, FRAME_HEIGHT)
        self.speech = SpeechEngine()
        self.ocr_engine = None
        self._ocr_loaded = False
        print("[系统] 基础模块初始化完成")
        print("[系统] 按空格键识别外卖单，按Q键退出")

    def _ensure_ocr(self):
        if not self._ocr_loaded:
            print("[系统] 正在加载OCR模型...")
            self.ocr_engine = OCREngine()
            self._ocr_loaded = True
            print("[系统] OCR模型加载完成")
            self.speech.speak("OCR模型已就绪", "system")

    def run(self):
        self.speech.speak("盲寻已启动，正在寻找外卖", "system")
        window_name = "BlindFind - 盲寻"

        while True:
            frame = self.camera.read()
            if frame is None:
                print("[错误] 无法获取摄像头画面")
                break

            detections = self.detector.detect(frame)
            self._draw_detections(frame, detections)

            _, obstacle_prompts = self.navigation.analyze_obstacles(detections)
            if obstacle_prompts:
                for prompt in obstacle_prompts:
                    self.speech.speak(prompt, "obstacle", priority=0)

            _, takeout_prompt = self.navigation.analyze_takeout(detections)
            if takeout_prompt:
                self.speech.speak(takeout_prompt, "takeout", priority=1)

            cv2.imshow(window_name, frame)

            key = cv2.waitKey(1) & 0xFF
            if key == ord('q') or key == 27:
                break
            elif key == ord(' '):
                self._trigger_ocr(frame)
            elif key == ord('r'):
                self.speech.reset_throttle()
                self.speech.speak("已重置播报", "system")

        self.camera.release()
        cv2.destroyAllWindows()
        self.speech.speak("盲寻已退出", "system")

    def _trigger_ocr(self, frame):
        self._ensure_ocr()
        self.speech.speak("正在识别", "system")
        ocr_results = self.ocr_engine.recognize(frame)
        info = self.ocr_engine.extract_takeout_info(ocr_results)
        speech_text = self.ocr_engine.format_speech(info)
        print(f"[OCR] {info['raw_text'][:100]}...")
        print(f"[OCR] 提取信息: {speech_text}")
        self.speech.speak(speech_text, "ocr", priority=2)

    def _draw_detections(self, frame, detections):
        for det in detections:
            x1, y1, x2, y2 = det["bbox"]
            label = f"{det['class_name']} {det['confidence']:.2f}"

            if det["class_name"] in {"person", "chair", "couch", "table"}:
                color = (0, 0, 255)
            elif det["class_name"] in {"backpack", "suitcase", "book"}:
                color = (0, 255, 0)
            else:
                color = (255, 0, 0)

            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            cv2.putText(frame, label, (x1, y1 - 10),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)


def main():
    try:
        app = BlindFindApp()
        app.run()
    except KeyboardInterrupt:
        print("\n[系统] 用户中断")
        sys.exit(0)
    except Exception as e:
        print(f"[错误] {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: 验证主程序能正常启动（不报错）**

Run: `cd /Users/pomelo/Project/blind_find && timeout 5 python -m src.main 2>&1 || true`
Expected: 看到"基础模块初始化完成"，没有报错。由于 timeout 5秒会自动退出，属于正常现象。

---

## Task 8: 功能验证与微调

- [ ] **Step 1: 测试实时检测**

打开摄像头，对准常见物品，验证：
- 检测框能正确识别物体
- 语音播报障碍物方向
- 语音播报疑似外卖位置

- [ ] **Step 2: 测试 OCR 识别**

准备一张外卖小票或有文字的图片，对准后按空格键：
- 能听到识别结果播报
- 控制台输出原始文字和提取的信息

- [ ] **Step 3: 测试语音节流**

- 同一方向障碍物持续存在时，播报不频繁
- 移动到不同方向，会有新的播报

- [ ] **Step 4: 验证退出功能**

按 Q 键或 ESC 键能正常退出程序。

---

## 完成标准

- [ ] 所有模块代码编写完成，无语法错误
- [ ] 摄像头能正常采集画面
- [ ] YOLO 检测实时运行，帧率 ≥ 15 FPS
- [ ] PaddleOCR 能识别中文文字
- [ ] 语音播报功能正常
- [ ] 主程序能完整运行，三大核心功能（检测、避障、OCR）均可用
- [ ] 有需要调整的参数记录到 config.py

---

## 后续事项（第二阶段准备）

1. 收集外卖场景真实图片，用于微调 YOLO 模型
2. 调研移动端 OCR 方案（chineseocr_lite TFLite / ML Kit）
3. 学习 Flutter + tflite_flutter 开发
4. 设计盲人友好的触控交互方式
