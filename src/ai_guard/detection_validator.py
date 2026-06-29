class DetectionValidator:

    def __init__(self, frame_width=640, frame_height=480, min_stable_frames=2,
                 min_confidence=0.5, min_bbox_size=20, max_bbox_ratio=0.9,
                 class_confidence_overrides=None):
        self.frame_width = frame_width
        self.frame_height = frame_height
        self.min_stable_frames = min_stable_frames
        self.min_confidence = min_confidence
        self.min_bbox_size = min_bbox_size
        self.max_bbox_ratio = max_bbox_ratio
        self.class_confidence_overrides = class_confidence_overrides or {}
        self._tracker = []

    def validate(self, detections):
        filtered = [d for d in detections if self.validate_confidence(d)]
        filtered = [d for d in filtered if self.validate_bbox(d)]
        stable = self.track_detections(filtered)
        return stable

    def validate_confidence(self, detection):
        class_name = detection["class_name"]
        threshold = self.class_confidence_overrides.get(class_name, self.min_confidence)
        return detection["confidence"] >= threshold

    def validate_bbox(self, detection):
        x1, y1, x2, y2 = detection["bbox"]
        width = x2 - x1
        height = y2 - y1
        if width < self.min_bbox_size or height < self.min_bbox_size:
            return False
        frame_area = self.frame_width * self.frame_height
        bbox_area = width * height
        if bbox_area / frame_area > self.max_bbox_ratio:
            return False
        return True

    def track_detections(self, detections):
        if not self._tracker:
            self._tracker = [
                {**det, "stable_count": 1}
                for det in detections
            ]
            return []

        matched_prev = set()
        matched_curr = set()
        new_tracker = []

        for i, det in enumerate(detections):
            best_iou = 0.0
            best_idx = -1
            for j, prev in enumerate(self._tracker):
                if j in matched_prev:
                    continue
                if det["class_id"] != prev["class_id"]:
                    continue
                iou_val = self._iou(det["bbox"], prev["bbox"])
                if iou_val > best_iou and iou_val > 0.5:
                    best_iou = iou_val
                    best_idx = j
            if best_idx >= 0:
                matched_prev.add(best_idx)
                matched_curr.add(i)
                prev_det = self._tracker[best_idx]
                new_count = prev_det["stable_count"] + 1
                new_tracker.append({**det, "stable_count": new_count})

        for i, det in enumerate(detections):
            if i not in matched_curr:
                new_tracker.append({**det, "stable_count": 1})

        self._tracker = new_tracker

        result = []
        for det in self._tracker:
            if det["stable_count"] >= self.min_stable_frames:
                stability_score = det["stable_count"]
                result.append({
                    "bbox": det["bbox"],
                    "confidence": det["confidence"],
                    "class_id": det["class_id"],
                    "class_name": det["class_name"],
                    "stability_score": stability_score,
                })
        return result

    def _iou(self, bbox1, bbox2):
        x1_1, y1_1, x2_1, y2_1 = bbox1
        x1_2, y1_2, x2_2, y2_2 = bbox2

        inter_x1 = max(x1_1, x1_2)
        inter_y1 = max(y1_1, y1_2)
        inter_x2 = min(x2_1, x2_2)
        inter_y2 = min(y2_1, y2_2)

        if inter_x1 >= inter_x2 or inter_y1 >= inter_y2:
            return 0.0

        inter_area = (inter_x2 - inter_x1) * (inter_y2 - inter_y1)
        area1 = (x2_1 - x1_1) * (y2_1 - y1_1)
        area2 = (x2_2 - x1_2) * (y2_2 - y1_2)
        union_area = area1 + area2 - inter_area

        if union_area <= 0:
            return 0.0

        return inter_area / union_area
