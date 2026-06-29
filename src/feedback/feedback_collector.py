import os
import json
from datetime import datetime


class FeedbackCollector:

    def __init__(self, feedback_dir="data/feedback"):
        self.feedback_dir = feedback_dir
        os.makedirs(self.feedback_dir, exist_ok=True)

    def save_feedback(self, frame, feedback_type, context=None):
        import cv2
        date_dir = self._get_date_dir()
        os.makedirs(date_dir, exist_ok=True)

        feedback_id = self._get_next_id(date_dir)
        image_filename = f"{feedback_id}.jpg"
        json_filename = f"{feedback_id}.json"
        image_path = os.path.join(date_dir, image_filename)
        json_path = os.path.join(date_dir, json_filename)

        cv2.imwrite(image_path, frame)

        relative_image_path = os.path.join(
            self.feedback_dir,
            os.path.basename(date_dir),
            image_filename
        )

        metadata = {
            "id": feedback_id,
            "timestamp": datetime.now().isoformat(),
            "type": feedback_type,
            "image_path": relative_image_path,
            "context": context or {}
        }

        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(metadata, f, ensure_ascii=False, indent=2)

        return json_path

    def get_feedback_list(self, date=None, feedback_type=None):
        if date:
            return self._get_feedback_by_date(date, feedback_type)

        feedback_list = []
        if not os.path.exists(self.feedback_dir):
            return feedback_list

        for date_folder in sorted(os.listdir(self.feedback_dir)):
            date_dir = os.path.join(self.feedback_dir, date_folder)
            if os.path.isdir(date_dir):
                feedback_list.extend(self._get_feedback_by_date(date_folder, feedback_type))

        feedback_list.sort(key=lambda x: x.get("timestamp", ""))
        return feedback_list

    def _get_feedback_by_date(self, date, feedback_type=None):
        date_dir = self._get_date_dir(date)
        if not os.path.exists(date_dir):
            return []

        feedback_list = []
        for filename in sorted(os.listdir(date_dir)):
            if filename.endswith(".json"):
                json_path = os.path.join(date_dir, filename)
                with open(json_path, "r", encoding="utf-8") as f:
                    metadata = json.load(f)
                if feedback_type and metadata.get("type") != feedback_type:
                    continue
                feedback_list.append(metadata)

        return feedback_list

    def get_feedback_by_id(self, feedback_id):
        if not os.path.exists(self.feedback_dir):
            return None

        for date_folder in os.listdir(self.feedback_dir):
            date_dir = os.path.join(self.feedback_dir, date_folder)
            if os.path.isdir(date_dir):
                json_path = os.path.join(date_dir, f"{feedback_id}.json")
                if os.path.exists(json_path):
                    with open(json_path, "r", encoding="utf-8") as f:
                        return json.load(f)
        return None

    def get_feedback_count(self, date=None, feedback_type=None):
        return len(self.get_feedback_list(date, feedback_type))

    def clear_feedback(self, date=None):
        if date:
            date_dir = self._get_date_dir(date)
            if not os.path.exists(date_dir):
                return 0
            count = 0
            for filename in os.listdir(date_dir):
                file_path = os.path.join(date_dir, filename)
                if os.path.isfile(file_path):
                    os.remove(file_path)
                    count += 1
            os.rmdir(date_dir)
            return count
        else:
            total_count = 0
            for date_folder in os.listdir(self.feedback_dir):
                date_dir = os.path.join(self.feedback_dir, date_folder)
                if os.path.isdir(date_dir):
                    for filename in os.listdir(date_dir):
                        file_path = os.path.join(date_dir, filename)
                        if os.path.isfile(file_path):
                            os.remove(file_path)
                            total_count += 1
                    os.rmdir(date_dir)
            return total_count

    def _get_date_dir(self, date=None):
        if date:
            date_str = date if isinstance(date, str) else date.strftime("%Y-%m-%d")
        else:
            date_str = datetime.now().strftime("%Y-%m-%d")
        return os.path.join(self.feedback_dir, date_str)

    def _get_next_id(self, date_dir):
        max_num = 0
        if os.path.exists(date_dir):
            for filename in os.listdir(date_dir):
                if filename.startswith("feedback_") and filename.endswith(".json"):
                    try:
                        num_str = filename[len("feedback_"):-len(".json")]
                        num = int(num_str)
                        if num > max_num:
                            max_num = num
                    except ValueError:
                        continue
        next_num = max_num + 1
        return f"feedback_{next_num:03d}"
