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

DETECTION_MIN_STABLE_FRAMES = 2
DETECTION_MIN_CONFIDENCE = 0.5
DETECTION_MIN_BBOX_SIZE = 20
DETECTION_MAX_BBOX_RATIO = 0.9
DETECTION_CLASS_CONFIDENCE_OVERRIDES = {
    "person": 0.6,
}

OCR_MIN_CONFIDENCE = 0.6
OCR_MAX_PICKUP_CODE_LEN = 20
OCR_MAX_NAME_LEN = 20

FEEDBACK_DIR = "data/feedback"
