from src.config import NAVIGATION_ZONES, OBSTACLE_CLASSES, TAKEOUT_CLASSES


class NavigationGuide:
    def __init__(self, frame_width=640, frame_height=480):
        self.frame_width = frame_width
        self.frame_height = frame_height

    def get_zone(self, bbox):
        x1, y1, x2, y2 = bbox
        center_x = (x1 + x2) / 2
        zone_width = self.frame_width // NAVIGATION_ZONES
        if center_x < zone_width:
            return "left"
        elif center_x < 2 * zone_width:
            return "center"
        else:
            return "right"

    def get_distance_estimate(self, bbox):
        x1, y1, x2, y2 = bbox
        height = y2 - y1
        if height < self.frame_height * 0.15:
            return "far"
        elif height < self.frame_height * 0.4:
            return "medium"
        else:
            return "near"

    def zone_to_chinese(self, zone):
        mapping = {
            "left": "左侧",
            "center": "正前方",
            "right": "右侧",
        }
        return mapping.get(zone, "")

    def distance_to_chinese(self, distance):
        mapping = {
            "far": "远处",
            "medium": "不远处",
            "near": "就在眼前",
        }
        return mapping.get(distance, "")

    def analyze_obstacles(self, detections):
        obstacles = [d for d in detections if d["class_name"] in OBSTACLE_CLASSES]
        if not obstacles:
            return None, []

        nearest = max(obstacles, key=lambda d: d["bbox"][3] - d["bbox"][1])

        zones = set()
        for d in obstacles:
            zones.add(self.get_zone(d["bbox"]))

        messages = []
        if "center" in zones:
            messages.append("正前方有障碍物，请小心")
        elif "left" in zones and "right" in zones:
            messages.append("两侧都有障碍物，请走中间")
        elif "left" in zones:
            messages.append("左侧有障碍物，请靠右走")
        elif "right" in zones:
            messages.append("右侧有障碍物，请靠左走")

        return nearest, messages

    def analyze_takeout(self, detections):
        takeout_items = [d for d in detections if d["class_name"] in TAKEOUT_CLASSES]
        if not takeout_items:
            return None, ""

        best = max(takeout_items, key=lambda d: d["confidence"])
        zone = self.get_zone(best["bbox"])
        distance = self.get_distance_estimate(best["bbox"])
        zone_cn = self.zone_to_chinese(zone)
        distance_cn = self.distance_to_chinese(distance)
        message = f"{zone_cn}{distance_cn}有疑似外卖物品"

        return best, message
