from pathlib import Path
from ultralytics import YOLO
from src.config import YOLO_MODEL, YOLO_CONFIDENCE_THRESHOLD, YOLO_IOU_THRESHOLD, YOLO_DEVICE, MODELS_DIR


class ObjectDetector:

    def __init__(self, model_path=None):
        if model_path is None:
            local_model = Path(MODELS_DIR) / YOLO_MODEL
            if local_model.exists():
                model_path = str(local_model)
            else:
                model_path = YOLO_MODEL

        self.model = YOLO(model_path)
        self.class_names = self.model.names

    def detect(self, frame):
        results = self.model(
            frame,
            conf=YOLO_CONFIDENCE_THRESHOLD,
            iou=YOLO_IOU_THRESHOLD,
            device=YOLO_DEVICE,
            verbose=False,
        )

        detections = []
        for result in results:
            for box in result.boxes:
                x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
                confidence = float(box.conf[0].item())
                class_id = int(box.cls[0].item())
                class_name = self.class_names[class_id]
                detections.append({
                    "bbox": (x1, y1, x2, y2),
                    "confidence": confidence,
                    "class_id": class_id,
                    "class_name": class_name,
                })

        return detections

    def filter_by_classes(self, detections, class_set):
        return [d for d in detections if d["class_name"] in class_set]
