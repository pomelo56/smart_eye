import pytest
from src.navigation import NavigationGuide


class TestGetZone:
    def setup_method(self):
        self.guide = NavigationGuide(frame_width=640, frame_height=480)

    def test_left_zone(self):
        bbox = (0, 0, 200, 100)
        assert self.guide.get_zone(bbox) == "left"

    def test_center_zone(self):
        bbox = (250, 0, 400, 100)
        assert self.guide.get_zone(bbox) == "center"

    def test_right_zone(self):
        bbox = (500, 0, 640, 100)
        assert self.guide.get_zone(bbox) == "right"

    def test_boundary_left_center(self):
        bbox = (213, 0, 214, 100)
        assert self.guide.get_zone(bbox) == "center"

    def test_boundary_center_right(self):
        bbox = (426, 0, 427, 100)
        assert self.guide.get_zone(bbox) == "right"

    def test_exact_left_third(self):
        bbox = (0, 0, 213, 100)
        assert self.guide.get_zone(bbox) == "left"

    def test_exact_right_third_start(self):
        bbox = (427, 0, 640, 100)
        assert self.guide.get_zone(bbox) == "right"

    def test_small_bbox_center(self):
        bbox = (318, 200, 322, 210)
        assert self.guide.get_zone(bbox) == "center"


class TestGetDistanceEstimate:
    def setup_method(self):
        self.guide = NavigationGuide(frame_width=640, frame_height=480)

    def test_far_distance(self):
        bbox = (0, 0, 100, 50)
        assert self.guide.get_distance_estimate(bbox) == "far"

    def test_medium_distance(self):
        bbox = (0, 0, 100, 150)
        assert self.guide.get_distance_estimate(bbox) == "medium"

    def test_near_distance(self):
        bbox = (0, 0, 100, 300)
        assert self.guide.get_distance_estimate(bbox) == "near"

    def test_far_boundary(self):
        bbox = (0, 0, 100, 71)
        assert self.guide.get_distance_estimate(bbox) == "far"

    def test_medium_boundary_lower(self):
        bbox = (0, 0, 100, 73)
        assert self.guide.get_distance_estimate(bbox) == "medium"

    def test_medium_boundary_upper(self):
        bbox = (0, 0, 100, 191)
        assert self.guide.get_distance_estimate(bbox) == "medium"

    def test_near_boundary(self):
        bbox = (0, 0, 100, 193)
        assert self.guide.get_distance_estimate(bbox) == "near"

    def test_full_height_is_near(self):
        bbox = (0, 0, 640, 480)
        assert self.guide.get_distance_estimate(bbox) == "near"


class TestZoneToChinese:
    def setup_method(self):
        self.guide = NavigationGuide()

    def test_left_to_chinese(self):
        assert self.guide.zone_to_chinese("left") == "左侧"

    def test_center_to_chinese(self):
        assert self.guide.zone_to_chinese("center") == "正前方"

    def test_right_to_chinese(self):
        assert self.guide.zone_to_chinese("right") == "右侧"


class TestDistanceToChinese:
    def setup_method(self):
        self.guide = NavigationGuide()

    def test_far_to_chinese(self):
        assert self.guide.distance_to_chinese("far") == "远处"

    def test_medium_to_chinese(self):
        assert self.guide.distance_to_chinese("medium") == "不远处"

    def test_near_to_chinese(self):
        assert self.guide.distance_to_chinese("near") == "就在眼前"


class TestAnalyzeObstacles:
    def setup_method(self):
        self.guide = NavigationGuide(frame_width=640, frame_height=480)

    def test_empty_detections(self):
        nearest, messages = self.guide.analyze_obstacles([])
        assert nearest is None
        assert messages == []

    def test_center_obstacle(self):
        detections = [
            {"bbox": (250, 100, 400, 300), "class_name": "chair", "confidence": 0.9}
        ]
        nearest, messages = self.guide.analyze_obstacles(detections)
        assert nearest is not None
        assert "正前方有障碍物，请小心" in messages

    def test_left_obstacle_only(self):
        detections = [
            {"bbox": (50, 100, 150, 300), "class_name": "person", "confidence": 0.8}
        ]
        nearest, messages = self.guide.analyze_obstacles(detections)
        assert nearest is not None
        assert "左侧有障碍物，请靠右走" in messages

    def test_right_obstacle_only(self):
        detections = [
            {"bbox": (500, 100, 600, 300), "class_name": "couch", "confidence": 0.7}
        ]
        nearest, messages = self.guide.analyze_obstacles(detections)
        assert nearest is not None
        assert "右侧有障碍物，请靠左走" in messages

    def test_both_sides_no_center(self):
        detections = [
            {"bbox": (50, 100, 150, 300), "class_name": "person", "confidence": 0.8},
            {"bbox": (500, 100, 600, 300), "class_name": "chair", "confidence": 0.9},
        ]
        nearest, messages = self.guide.analyze_obstacles(detections)
        assert nearest is not None
        assert "两侧都有障碍物，请走中间" in messages

    def test_center_and_left_obstacle(self):
        detections = [
            {"bbox": (50, 100, 150, 300), "class_name": "person", "confidence": 0.8},
            {"bbox": (250, 100, 400, 300), "class_name": "chair", "confidence": 0.9},
        ]
        nearest, messages = self.guide.analyze_obstacles(detections)
        assert "正前方有障碍物，请小心" in messages

    def test_center_and_right_obstacle(self):
        detections = [
            {"bbox": (250, 100, 400, 300), "class_name": "chair", "confidence": 0.9},
            {"bbox": (500, 100, 600, 300), "class_name": "couch", "confidence": 0.7},
        ]
        nearest, messages = self.guide.analyze_obstacles(detections)
        assert "正前方有障碍物，请小心" in messages

    def test_all_three_zones(self):
        detections = [
            {"bbox": (50, 100, 150, 300), "class_name": "person", "confidence": 0.8},
            {"bbox": (250, 100, 400, 300), "class_name": "chair", "confidence": 0.9},
            {"bbox": (500, 100, 600, 300), "class_name": "couch", "confidence": 0.7},
        ]
        nearest, messages = self.guide.analyze_obstacles(detections)
        assert "正前方有障碍物，请小心" in messages

    def test_non_obstacle_classes_ignored(self):
        detections = [
            {"bbox": (250, 100, 400, 300), "class_name": "car", "confidence": 0.9},
            {"bbox": (100, 100, 200, 300), "class_name": "dog", "confidence": 0.8},
        ]
        nearest, messages = self.guide.analyze_obstacles(detections)
        assert nearest is None
        assert messages == []

    def test_nearest_obstacle_returned(self):
        detections = [
            {"bbox": (50, 100, 150, 200), "class_name": "person", "confidence": 0.8},
            {"bbox": (250, 100, 400, 400), "class_name": "chair", "confidence": 0.9},
        ]
        nearest, messages = self.guide.analyze_obstacles(detections)
        assert nearest is not None
        assert nearest["class_name"] == "chair"

    def test_multiple_obstacle_classes(self):
        classes = ["person", "chair", "couch", "table", "bottle", "backpack", "suitcase", "book"]
        for cls in classes:
            detections = [{"bbox": (250, 100, 400, 300), "class_name": cls, "confidence": 0.9}]
            nearest, messages = self.guide.analyze_obstacles(detections)
            assert nearest is not None, f"{cls} should be recognized as obstacle"
            assert len(messages) > 0


class TestAnalyzeTakeout:
    def setup_method(self):
        self.guide = NavigationGuide(frame_width=640, frame_height=480)

    def test_empty_detections(self):
        best, message = self.guide.analyze_takeout([])
        assert best is None
        assert message == ""

    def test_single_takeout_item(self):
        detections = [
            {"bbox": (100, 100, 200, 200), "class_name": "backpack", "confidence": 0.9}
        ]
        best, message = self.guide.analyze_takeout(detections)
        assert best is not None
        assert best["class_name"] == "backpack"
        assert "疑似外卖" in message

    def test_highest_confidence_selected(self):
        detections = [
            {"bbox": (100, 100, 200, 200), "class_name": "backpack", "confidence": 0.7},
            {"bbox": (300, 100, 400, 200), "class_name": "suitcase", "confidence": 0.95},
            {"bbox": (500, 100, 600, 200), "class_name": "bottle", "confidence": 0.8},
        ]
        best, message = self.guide.analyze_takeout(detections)
        assert best is not None
        assert best["class_name"] == "suitcase"
        assert best["confidence"] == 0.95

    def test_left_far_takeout(self):
        detections = [
            {"bbox": (50, 50, 150, 100), "class_name": "backpack", "confidence": 0.9}
        ]
        best, message = self.guide.analyze_takeout(detections)
        assert "左侧" in message
        assert "远处" in message
        assert "疑似外卖" in message

    def test_center_medium_takeout(self):
        detections = [
            {"bbox": (250, 100, 400, 250), "class_name": "suitcase", "confidence": 0.9}
        ]
        best, message = self.guide.analyze_takeout(detections)
        assert "正前方" in message
        assert "不远处" in message
        assert "疑似外卖" in message

    def test_right_near_takeout(self):
        detections = [
            {"bbox": (500, 50, 640, 400), "class_name": "book", "confidence": 0.9}
        ]
        best, message = self.guide.analyze_takeout(detections)
        assert "右侧" in message
        assert "就在眼前" in message
        assert "疑似外卖" in message

    def test_non_takeout_classes_ignored(self):
        detections = [
            {"bbox": (250, 100, 400, 300), "class_name": "person", "confidence": 0.9},
            {"bbox": (100, 100, 200, 300), "class_name": "chair", "confidence": 0.8},
        ]
        best, message = self.guide.analyze_takeout(detections)
        assert best is None
        assert message == ""

    def test_multiple_takeout_classes(self):
        classes = ["backpack", "suitcase", "book", "bottle", "cup", "bowl", "laptop"]
        for cls in classes:
            detections = [{"bbox": (250, 100, 400, 300), "class_name": cls, "confidence": 0.9}]
            best, message = self.guide.analyze_takeout(detections)
            assert best is not None, f"{cls} should be recognized as takeout"
            assert message != ""


class TestNavigationGuideInit:
    def test_default_init(self):
        guide = NavigationGuide()
        assert guide.frame_width == 640
        assert guide.frame_height == 480

    def test_custom_init(self):
        guide = NavigationGuide(frame_width=1280, frame_height=720)
        assert guide.frame_width == 1280
        assert guide.frame_height == 720

    def test_custom_frame_zone_calculation(self):
        guide = NavigationGuide(frame_width=900, frame_height=600)
        assert guide.get_zone((0, 0, 299, 100)) == "left"
        assert guide.get_zone((301, 0, 599, 100)) == "center"
        assert guide.get_zone((601, 0, 900, 100)) == "right"

    def test_custom_frame_distance_calculation(self):
        guide = NavigationGuide(frame_width=900, frame_height=600)
        assert guide.get_distance_estimate((0, 0, 100, 89)) == "far"
        assert guide.get_distance_estimate((0, 0, 100, 91)) == "medium"
        assert guide.get_distance_estimate((0, 0, 100, 241)) == "near"
