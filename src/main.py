import cv2
import sys

from src.camera import Camera
from src.detector import ObjectDetector
from src.ocr_engine import OCREngine
from src.navigation import NavigationGuide
from src.speech import SpeechEngine
from src.ai_guard.detection_validator import DetectionValidator
from src.ai_guard.ocr_validator import OCRValidator
from src.feedback.feedback_collector import FeedbackCollector
from src.config import (
    FRAME_WIDTH, FRAME_HEIGHT,
    DETECTION_MIN_STABLE_FRAMES, DETECTION_MIN_CONFIDENCE,
    DETECTION_MIN_BBOX_SIZE, DETECTION_MAX_BBOX_RATIO,
    DETECTION_CLASS_CONFIDENCE_OVERRIDES,
    OCR_MIN_CONFIDENCE, OCR_MAX_PICKUP_CODE_LEN, OCR_MAX_NAME_LEN,
    FEEDBACK_DIR,
    __version__, __app_name__,
)


class BlindFindApp:
    def __init__(self):
        print(f"[BlindFind] {__app_name__} v{__version__} 正在初始化...")

        self.camera = Camera()
        print("[BlindFind] 摄像头初始化完成")

        self.detector = ObjectDetector()
        print("[BlindFind] YOLO检测器初始化完成")

        self.detection_validator = DetectionValidator(
            frame_width=FRAME_WIDTH,
            frame_height=FRAME_HEIGHT,
            min_stable_frames=DETECTION_MIN_STABLE_FRAMES,
            min_confidence=DETECTION_MIN_CONFIDENCE,
            min_bbox_size=DETECTION_MIN_BBOX_SIZE,
            max_bbox_ratio=DETECTION_MAX_BBOX_RATIO,
            class_confidence_overrides=DETECTION_CLASS_CONFIDENCE_OVERRIDES,
        )
        print("[BlindFind] 检测验证器初始化完成")

        self.ocr_validator = OCRValidator(
            min_confidence=OCR_MIN_CONFIDENCE,
            max_pickup_code_len=OCR_MAX_PICKUP_CODE_LEN,
            max_name_len=OCR_MAX_NAME_LEN,
        )
        print("[BlindFind] OCR验证器初始化完成")

        self.navigation = NavigationGuide(FRAME_WIDTH, FRAME_HEIGHT)
        print("[BlindFind] 导航模块初始化完成")

        self.speech = SpeechEngine()
        print("[BlindFind] 语音模块初始化完成")

        self.feedback_collector = FeedbackCollector(feedback_dir=FEEDBACK_DIR)
        print("[BlindFind] 反馈收集模块初始化完成")

        self.ocr_engine = None
        print("[BlindFind] OCR模块待加载（懒加载）")

        self._last_detections = []
        self._last_ocr_results = None
        self._last_takeout_info = None
        self.running = False

        print("[BlindFind] 初始化完成")

    def _ensure_ocr(self):
        if self.ocr_engine is None:
            print("[BlindFind] 正在加载OCR模型...")
            self.ocr_engine = OCREngine()
            print("[BlindFind] OCR模型加载完成")

    def run(self):
        self.running = True
        self.speech.speak(f"{__app_name__}已启动", category="system")

        while self.running:
            frame = self.camera.read()
            if frame is None:
                print("[BlindFind] 无法读取摄像头帧")
                break

            raw_detections = self.detector.detect(frame)
            validated_detections = self.detection_validator.validate(raw_detections)
            self._last_detections = validated_detections

            nearest_obstacle, obstacle_messages = self.navigation.analyze_obstacles(validated_detections)
            if obstacle_messages:
                for msg in obstacle_messages:
                    self.speech.speak(msg, category="obstacle")

            if not obstacle_messages:
                best_takeout, takeout_message = self.navigation.analyze_takeout(validated_detections)
                if takeout_message:
                    self.speech.speak(takeout_message, category="takeout")

            display_frame = self._draw_detections(frame, validated_detections)

            cv2.imshow("BlindFind", display_frame)

            key = cv2.waitKey(1) & 0xFF
            if key == ord(' '):
                self._trigger_ocr(frame)
            elif key == ord('r'):
                self.speech.reset_throttle()
                self.speech.speak("语音节流已重置", category="system")
            elif key == ord('f'):
                self._save_feedback(frame, "detection_error")
            elif key == ord('o'):
                self._save_feedback(frame, "ocr_error")
            elif key == ord('q') or key == 27:
                break

        self._cleanup()

    def _trigger_ocr(self, frame):
        self._ensure_ocr()
        self.speech.speak("正在识别", category="ocr")

        try:
            ocr_results = self.ocr_engine.recognize(frame)
            self._last_ocr_results = ocr_results
            info = self.ocr_engine.extract_takeout_info(ocr_results)
            self._last_takeout_info = info

            validation = self.ocr_validator.validate(info, ocr_results)

            if validation["overall_valid"]:
                validated_info = validation["validated_info"]
                speech_text = self.ocr_engine.format_speech(validated_info)
                self.speech.speak(speech_text, category="ocr")
            else:
                self.speech.speak("识别结果不确定，请靠近小票再试一次", category="ocr")
        except Exception as e:
            print(f"[BlindFind] OCR识别出错: {e}")
            self.speech.speak("识别失败", category="ocr")

    def _save_feedback(self, frame, feedback_type):
        context = {
            "detections": self._last_detections,
        }
        if feedback_type == "ocr_error":
            context["ocr_results"] = self._last_ocr_results
            context["takeout_info"] = self._last_takeout_info

        path = self.feedback_collector.save_feedback(frame, feedback_type, context)
        count = self.feedback_collector.get_feedback_count()
        self.speech.speak(f"反馈已保存，共{count}条", category="system")
        print(f"[BlindFind] 反馈已保存: {path}")

    def _draw_detections(self, frame, detections):
        display_frame = frame.copy()

        for det in detections:
            x1, y1, x2, y2 = det["bbox"]
            class_name = det["class_name"]
            confidence = det["confidence"]
            stability = det.get("stability_score", 1)

            from src.config import OBSTACLE_CLASSES, TAKEOUT_CLASSES

            if class_name in OBSTACLE_CLASSES:
                color = (0, 0, 255)
            elif class_name in TAKEOUT_CLASSES:
                color = (0, 255, 0)
            else:
                color = (255, 0, 0)

            thickness = 3 if stability >= 2 else 1
            cv2.rectangle(display_frame, (int(x1), int(y1)), (int(x2), int(y2)), color, thickness)

            label = f"{class_name} {confidence:.2f} S{stability}"
            label_size, _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
            cv2.rectangle(
                display_frame,
                (int(x1), int(y1) - label_size[1] - 4),
                (int(x1) + label_size[0], int(y1)),
                color,
                -1
            )
            cv2.putText(
                display_frame,
                label,
                (int(x1), int(y1) - 2),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (255, 255, 255),
                1
            )

        return display_frame

    def _cleanup(self):
        self.camera.release()
        cv2.destroyAllWindows()
        self.speech.speak("程序已退出", category="system")
        print("[BlindFind] 程序已退出")


def main():
    try:
        app = BlindFindApp()
        app.run()
    except KeyboardInterrupt:
        print("\n[BlindFind] 用户中断")
    except Exception as e:
        print(f"[BlindFind] 程序出错: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
