import pytest
from src.ocr_engine import OCREngine


class TestExtractTakeoutInfo:

    def setup_method(self):
        self.engine = OCREngine()

    def test_standard_takeout_order(self):
        ocr_results = [
            {"text": "取餐人：张三", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
            {"text": "取餐码：A123", "confidence": 0.98, "box": [[0, 40], [100, 40], [100, 70], [0, 70]]},
            {"text": "手机尾号：1234", "confidence": 0.97, "box": [[0, 80], [100, 80], [100, 110], [0, 110]]},
            {"text": "麦当劳", "confidence": 0.96, "box": [[0, 120], [100, 120], [100, 150], [0, 150]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["customer_name"] == "张三"
        assert info["pickup_code"] == "A123"
        assert info["phone_tail"] == "1234"
        assert info["merchant"] == "麦当劳"
        assert "取餐人：张三" in info["raw_text"]

    def test_only_customer_name(self):
        ocr_results = [
            {"text": "取餐人：李四", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["customer_name"] == "李四"
        assert info["pickup_code"] is None
        assert info["phone_tail"] is None
        assert info["merchant"] is None

    def test_only_pickup_code(self):
        ocr_results = [
            {"text": "取餐码：B456", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["customer_name"] is None
        assert info["pickup_code"] == "B456"
        assert info["phone_tail"] is None
        assert info["merchant"] is None

    def test_nothing_found(self):
        ocr_results = [
            {"text": "欢迎光临", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
            {"text": "谢谢惠顾", "confidence": 0.98, "box": [[0, 40], [100, 40], [100, 70], [0, 70]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["customer_name"] is None
        assert info["pickup_code"] is None
        assert info["phone_tail"] is None
        assert info["merchant"] is None
        assert "欢迎光临" in info["raw_text"]

    def test_phone_tail_with_asterisk_format(self):
        ocr_results = [
            {"text": "138****1234", "confidence": 0.99, "box": [[0, 0], [150, 0], [150, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["phone_tail"] == "1234"

    def test_phone_tail_with_asterisk_and_label(self):
        ocr_results = [
            {"text": "手机号：139****5678", "confidence": 0.99, "box": [[0, 0], [200, 0], [200, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["phone_tail"] == "5678"

    def test_keyword_variants_recipient(self):
        ocr_results = [
            {"text": "收件人：王五", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["customer_name"] == "王五"

    def test_keyword_variants_customer(self):
        ocr_results = [
            {"text": "顾客：赵六", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["customer_name"] == "赵六"

    def test_keyword_variants_name(self):
        ocr_results = [
            {"text": "姓名：孙七", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["customer_name"] == "孙七"

    def test_keyword_variants_pickup_number(self):
        ocr_results = [
            {"text": "取餐号：C789", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["pickup_code"] == "C789"

    def test_keyword_variants_order_number(self):
        ocr_results = [
            {"text": "订单号：D012", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["pickup_code"] == "D012"

    def test_keyword_variants_pickup_id(self):
        ocr_results = [
            {"text": "取餐编号：E345", "confidence": 0.99, "box": [[0, 0], [120, 0], [120, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["pickup_code"] == "E345"

    def test_keyword_variants_phone_tail(self):
        ocr_results = [
            {"text": "尾号：6789", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["phone_tail"] == "6789"

    def test_empty_input(self):
        info = self.engine.extract_takeout_info([])
        assert info["customer_name"] is None
        assert info["pickup_code"] is None
        assert info["phone_tail"] is None
        assert info["merchant"] is None
        assert info["raw_text"] == ""

    def test_none_input(self):
        info = self.engine.extract_takeout_info(None)
        assert info["customer_name"] is None
        assert info["pickup_code"] is None
        assert info["phone_tail"] is None
        assert info["merchant"] is None
        assert info["raw_text"] == ""

    def test_colon_variants_chinese(self):
        ocr_results = [
            {"text": "取餐人：周八", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["customer_name"] == "周八"

    def test_colon_variants_english(self):
        ocr_results = [
            {"text": "取餐人:吴九", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["customer_name"] == "吴九"

    def test_pickup_code_numeric_only(self):
        ocr_results = [
            {"text": "取餐码：12345", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["pickup_code"] == "12345"

    def test_pickup_code_mixed_alphanumeric(self):
        ocr_results = [
            {"text": "取餐码：AB123CD", "confidence": 0.99, "box": [[0, 0], [150, 0], [150, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["pickup_code"] == "AB123CD"

    def test_merchant_detection(self):
        ocr_results = [
            {"text": "商家：肯德基", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["merchant"] == "肯德基"

    def test_merchant_shop_keyword(self):
        ocr_results = [
            {"text": "店铺：星巴克", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert info["merchant"] == "星巴克"

    def test_raw_text_concatenation(self):
        ocr_results = [
            {"text": "第一行", "confidence": 0.99, "box": [[0, 0], [100, 0], [100, 30], [0, 30]]},
            {"text": "第二行", "confidence": 0.98, "box": [[0, 40], [100, 40], [100, 70], [0, 70]]},
        ]
        info = self.engine.extract_takeout_info(ocr_results)
        assert "第一行" in info["raw_text"]
        assert "第二行" in info["raw_text"]


class TestFormatSpeech:

    def setup_method(self):
        self.engine = OCREngine()

    def test_all_fields_present(self):
        info = {
            "customer_name": "张三",
            "pickup_code": "A123",
            "phone_tail": "1234",
            "merchant": "麦当劳",
        }
        speech = self.engine.format_speech(info)
        assert speech == "取餐人张三，取餐码A123，手机尾号1234，商家麦当劳"

    def test_only_customer_name(self):
        info = {
            "customer_name": "李四",
            "pickup_code": None,
            "phone_tail": None,
            "merchant": None,
        }
        speech = self.engine.format_speech(info)
        assert speech == "取餐人李四"

    def test_only_pickup_code(self):
        info = {
            "customer_name": None,
            "pickup_code": "B456",
            "phone_tail": None,
            "merchant": None,
        }
        speech = self.engine.format_speech(info)
        assert speech == "取餐码B456"

    def test_only_phone_tail(self):
        info = {
            "customer_name": None,
            "pickup_code": None,
            "phone_tail": "7890",
            "merchant": None,
        }
        speech = self.engine.format_speech(info)
        assert speech == "手机尾号7890"

    def test_only_merchant(self):
        info = {
            "customer_name": None,
            "pickup_code": None,
            "phone_tail": None,
            "merchant": "肯德基",
        }
        speech = self.engine.format_speech(info)
        assert speech == "商家肯德基"

    def test_customer_and_pickup(self):
        info = {
            "customer_name": "王五",
            "pickup_code": "C789",
            "phone_tail": None,
            "merchant": None,
        }
        speech = self.engine.format_speech(info)
        assert speech == "取餐人王五，取餐码C789"

    def test_customer_and_phone(self):
        info = {
            "customer_name": "赵六",
            "pickup_code": None,
            "phone_tail": "1111",
            "merchant": None,
        }
        speech = self.engine.format_speech(info)
        assert speech == "取餐人赵六，手机尾号1111"

    def test_pickup_and_phone(self):
        info = {
            "customer_name": None,
            "pickup_code": "D012",
            "phone_tail": "2222",
            "merchant": None,
        }
        speech = self.engine.format_speech(info)
        assert speech == "取餐码D012，手机尾号2222"

    def test_nothing_found(self):
        info = {
            "customer_name": None,
            "pickup_code": None,
            "phone_tail": None,
            "merchant": None,
        }
        speech = self.engine.format_speech(info)
        assert speech == "未识别到有效信息"

    def test_empty_strings_treated_as_none(self):
        info = {
            "customer_name": "",
            "pickup_code": "",
            "phone_tail": "",
            "merchant": "",
        }
        speech = self.engine.format_speech(info)
        assert speech == "未识别到有效信息"

    def test_raw_text_not_included_in_speech(self):
        info = {
            "customer_name": "孙七",
            "pickup_code": "E345",
            "phone_tail": "3333",
            "merchant": "星巴克",
            "raw_text": "一些原始文本",
        }
        speech = self.engine.format_speech(info)
        assert "原始文本" not in speech
        assert "取餐人孙七" in speech
