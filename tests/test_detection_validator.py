import pytest
from src.ai_guard.detection_validator import DetectionValidator


class TestDetectionValidatorInit:

    def test_default_init(self):
        validator = DetectionValidator(frame_width=640, frame_height=480)
        assert validator.frame_width == 640
        assert validator.frame_height == 480
        assert validator.min_stable_frames == 2
        assert validator.min_confidence == 0.5
        assert validator.min_bbox_size == 20
        assert validator.max_bbox_ratio == 0.9
        assert validator.class_confidence_overrides == {}

    def test_custom_init(self):
        validator = DetectionValidator(
            frame_width=1280,
            frame_height=720,
            min_stable_frames=3,
            min_confidence=0.7,
            min_bbox_size=30,
            max_bbox_ratio=0.8,
            class_confidence_overrides={"person": 0.8},
        )
        assert validator.frame_width == 1280
        assert validator.frame_height == 720
        assert validator.min_stable_frames == 3
        assert validator.min_confidence == 0.7
        assert validator.min_bbox_size == 30
        assert validator.max_bbox_ratio == 0.8
        assert validator.class_confidence_overrides == {"person": 0.8}


class TestValidateConfidence:

    def setup_method(self):
        self.validator = DetectionValidator(frame_width=640, frame_height=480, min_confidence=0.5)

    def test_above_threshold_passes(self):
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        assert self.validator.validate_confidence(detection) is True

    def test_below_threshold_filtered(self):
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.3, "class_id": 0, "class_name": "person"}
        assert self.validator.validate_confidence(detection) is False

    def test_equal_threshold_passes(self):
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.5, "class_id": 0, "class_name": "person"}
        assert self.validator.validate_confidence(detection) is True

    def test_class_override_higher_threshold(self):
        validator = DetectionValidator(
            frame_width=640,
            frame_height=480,
            min_confidence=0.5,
            class_confidence_overrides={"person": 0.8},
        )
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.7, "class_id": 0, "class_name": "person"}
        assert validator.validate_confidence(detection) is False

    def test_class_override_below_general_but_above_override(self):
        validator = DetectionValidator(
            frame_width=640,
            frame_height=480,
            min_confidence=0.5,
            class_confidence_overrides={"chair": 0.3},
        )
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.4, "class_id": 0, "class_name": "chair"}
        assert validator.validate_confidence(detection) is True

    def test_class_not_in_override_uses_default(self):
        validator = DetectionValidator(
            frame_width=640,
            frame_height=480,
            min_confidence=0.5,
            class_confidence_overrides={"person": 0.8},
        )
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.6, "class_id": 0, "class_name": "chair"}
        assert validator.validate_confidence(detection) is True

    def test_class_override_boundary_value(self):
        validator = DetectionValidator(
            frame_width=640,
            frame_height=480,
            min_confidence=0.5,
            class_confidence_overrides={"person": 0.8},
        )
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        assert validator.validate_confidence(detection) is True


class TestValidateBbox:

    def setup_method(self):
        self.validator = DetectionValidator(
            frame_width=640,
            frame_height=480,
            min_bbox_size=20,
            max_bbox_ratio=0.9,
        )

    def test_normal_bbox_passes(self):
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        assert self.validator.validate_bbox(detection) is True

    def test_bbox_too_small_width_filtered(self):
        detection = {"bbox": (100, 100, 110, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        assert self.validator.validate_bbox(detection) is False

    def test_bbox_too_small_height_filtered(self):
        detection = {"bbox": (100, 100, 200, 110), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        assert self.validator.validate_bbox(detection) is False

    def test_bbox_too_large_filtered(self):
        detection = {"bbox": (0, 0, 630, 470), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        assert self.validator.validate_bbox(detection) is False

    def test_min_bbox_boundary_width_passes(self):
        detection = {"bbox": (100, 100, 120, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        assert self.validator.validate_bbox(detection) is True

    def test_min_bbox_boundary_height_passes(self):
        detection = {"bbox": (100, 100, 200, 120), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        assert self.validator.validate_bbox(detection) is True

    def test_max_bbox_ratio_boundary_passes(self):
        validator = DetectionValidator(
            frame_width=100,
            frame_height=100,
            min_bbox_size=10,
            max_bbox_ratio=0.9,
        )
        detection = {"bbox": (5, 5, 95, 95), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        assert validator.validate_bbox(detection) is True

    def test_max_bbox_ratio_exceeded_filtered(self):
        validator = DetectionValidator(
            frame_width=100,
            frame_height=100,
            min_bbox_size=10,
            max_bbox_ratio=0.9,
        )
        detection = {"bbox": (0, 0, 96, 96), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        assert validator.validate_bbox(detection) is False

    def test_square_min_size_passes(self):
        detection = {"bbox": (100, 100, 120, 120), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        assert self.validator.validate_bbox(detection) is True

    def test_square_below_min_size_filtered(self):
        detection = {"bbox": (100, 100, 115, 115), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        assert self.validator.validate_bbox(detection) is False


class TestTrackDetections:

    def setup_method(self):
        self.validator = DetectionValidator(
            frame_width=640,
            frame_height=480,
            min_stable_frames=2,
        )

    def test_single_frame_not_passed(self):
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        stable = self.validator.track_detections([detection])
        assert len(stable) == 0

    def test_two_consecutive_frames_passes(self):
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        self.validator.track_detections([detection])
        stable = self.validator.track_detections([detection])
        assert len(stable) == 1
        assert stable[0]["stability_score"] == 2

    def test_three_consecutive_frames_stability_increases(self):
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        self.validator.track_detections([detection])
        self.validator.track_detections([detection])
        stable = self.validator.track_detections([detection])
        assert len(stable) == 1
        assert stable[0]["stability_score"] == 3

    def test_missing_one_frame_resets_count(self):
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        self.validator.track_detections([detection])
        self.validator.track_detections([detection])
        self.validator.track_detections([])
        stable = self.validator.track_detections([detection])
        assert len(stable) == 0

    def test_multiple_targets_tracked_separately(self):
        det1 = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        det2 = {"bbox": (400, 100, 500, 200), "confidence": 0.7, "class_id": 1, "class_name": "chair"}
        self.validator.track_detections([det1, det2])
        stable = self.validator.track_detections([det1, det2])
        assert len(stable) == 2
        scores = [s["stability_score"] for s in stable]
        assert all(s == 2 for s in scores)

    def test_iou_below_threshold_treated_as_different(self):
        det1 = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        det2 = {"bbox": (300, 100, 400, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        self.validator.track_detections([det1])
        stable = self.validator.track_detections([det2])
        assert len(stable) == 0

    def test_iou_above_threshold_treated_as_same(self):
        det1 = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        det2 = {"bbox": (105, 105, 205, 205), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        self.validator.track_detections([det1])
        stable = self.validator.track_detections([det2])
        assert len(stable) == 1
        assert stable[0]["stability_score"] == 2

    def test_different_class_same_position_not_matched(self):
        det1 = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        det2 = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 1, "class_name": "chair"}
        self.validator.track_detections([det1])
        stable = self.validator.track_detections([det2])
        assert len(stable) == 0

    def test_custom_min_stable_frames_3(self):
        validator = DetectionValidator(
            frame_width=640,
            frame_height=480,
            min_stable_frames=3,
        )
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        validator.track_detections([detection])
        validator.track_detections([detection])
        stable = validator.track_detections([detection])
        assert len(stable) == 1
        assert stable[0]["stability_score"] == 3

    def test_one_target_stable_other_not(self):
        det1 = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        det2 = {"bbox": (400, 100, 500, 200), "confidence": 0.7, "class_id": 1, "class_name": "chair"}
        self.validator.track_detections([det1])
        stable = self.validator.track_detections([det1, det2])
        assert len(stable) == 1
        assert stable[0]["class_name"] == "person"


class TestValidate:

    def setup_method(self):
        self.validator = DetectionValidator(
            frame_width=640,
            frame_height=480,
            min_stable_frames=2,
            min_confidence=0.5,
            min_bbox_size=20,
            max_bbox_ratio=0.9,
        )

    def test_validate_all_passing(self):
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        self.validator.validate([detection])
        result = self.validator.validate([detection])
        assert len(result) == 1
        assert "stability_score" in result[0]
        assert result[0]["stability_score"] >= 2

    def test_validate_low_confidence_filtered(self):
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.3, "class_id": 0, "class_name": "person"}
        self.validator.validate([detection])
        result = self.validator.validate([detection])
        assert len(result) == 0

    def test_validate_small_bbox_filtered(self):
        detection = {"bbox": (100, 100, 110, 110), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        self.validator.validate([detection])
        result = self.validator.validate([detection])
        assert len(result) == 0

    def test_validate_single_frame_not_returned(self):
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        result = self.validator.validate([detection])
        assert len(result) == 0

    def test_validate_empty_input(self):
        result = self.validator.validate([])
        assert len(result) == 0

    def test_validate_mixed_results(self):
        good_det = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        bad_conf = {"bbox": (300, 100, 400, 200), "confidence": 0.3, "class_id": 1, "class_name": "chair"}
        bad_bbox = {"bbox": (500, 100, 505, 105), "confidence": 0.9, "class_id": 2, "class_name": "bottle"}
        self.validator.validate([good_det, bad_conf, bad_bbox])
        result = self.validator.validate([good_det, bad_conf, bad_bbox])
        assert len(result) == 1
        assert result[0]["class_name"] == "person"

    def test_validate_preserves_detection_fields(self):
        detection = {"bbox": (100, 100, 200, 200), "confidence": 0.8, "class_id": 0, "class_name": "person"}
        self.validator.validate([detection])
        result = self.validator.validate([detection])
        assert len(result) == 1
        assert result[0]["bbox"] == (100, 100, 200, 200)
        assert result[0]["confidence"] == 0.8
        assert result[0]["class_id"] == 0
        assert result[0]["class_name"] == "person"

    def test_validate_with_class_override(self):
        validator = DetectionValidator(
            frame_width=640,
            frame_height=480,
            min_stable_frames=2,
            min_confidence=0.5,
            class_confidence_overrides={"person": 0.8},
        )
        det_person = {"bbox": (100, 100, 200, 200), "confidence": 0.7, "class_id": 0, "class_name": "person"}
        det_chair = {"bbox": (300, 100, 400, 200), "confidence": 0.7, "class_id": 1, "class_name": "chair"}
        validator.validate([det_person, det_chair])
        result = validator.validate([det_person, det_chair])
        assert len(result) == 1
        assert result[0]["class_name"] == "chair"
