import pytest
from src.ai_guard.ocr_validator import OCRValidator


class TestOCRValidatorInit:

    def test_default_init(self):
        validator = OCRValidator()
        assert validator.min_confidence == 0.6
        assert validator.max_pickup_code_len == 20
        assert validator.max_name_len == 20

    def test_custom_init(self):
        validator = OCRValidator(
            min_confidence=0.7,
            max_pickup_code_len=15,
            max_name_len=10,
        )
        assert validator.min_confidence == 0.7
        assert validator.max_pickup_code_len == 15
        assert validator.max_name_len == 10


class TestValidateOverallConfidence:

    def setup_method(self):
        self.validator = OCRValidator(min_confidence=0.6)

    def test_average_above_threshold_passes(self):
        ocr_results = [
            {"text": "hello", "confidence": 0.8},
            {"text": "world", "confidence": 0.9},
        ]
        assert self.validator.validate_overall_confidence(ocr_results) is True

    def test_average_below_threshold_fails(self):
        ocr_results = [
            {"text": "hello", "confidence": 0.3},
            {"text": "world", "confidence": 0.4},
        ]
        assert self.validator.validate_overall_confidence(ocr_results) is False

    def test_empty_results_returns_false(self):
        assert self.validator.validate_overall_confidence([]) is False

    def test_single_high_confidence_passes(self):
        ocr_results = [{"text": "hello", "confidence": 0.9}]
        assert self.validator.validate_overall_confidence(ocr_results) is True

    def test_average_equal_threshold_passes(self):
        ocr_results = [
            {"text": "hello", "confidence": 0.6},
            {"text": "world", "confidence": 0.6},
        ]
        assert self.validator.validate_overall_confidence(ocr_results) is True

    def test_mixed_confidence_average_below(self):
        ocr_results = [
            {"text": "hello", "confidence": 0.9},
            {"text": "world", "confidence": 0.2},
        ]
        assert self.validator.validate_overall_confidence(ocr_results) is False


class TestValidatePickupCode:

    def setup_method(self):
        self.validator = OCRValidator()

    def test_pure_numeric_passes(self):
        assert self.validator.validate_pickup_code("1234") is True

    def test_short_numeric_passes(self):
        assert self.validator.validate_pickup_code("88") is True

    def test_alphanumeric_passes(self):
        assert self.validator.validate_pickup_code("A12") is True

    def test_alphanumeric_longer_passes(self):
        assert self.validator.validate_pickup_code("B123") is True

    def test_pure_symbols_fails(self):
        assert self.validator.validate_pickup_code("!@#$") is False

    def test_chinese_symbols_fails(self):
        assert self.validator.validate_pickup_code("。。。") is False

    def test_none_returns_none(self):
        assert self.validator.validate_pickup_code(None) is None

    def test_too_long_fails(self):
        long_code = "A" * 21
        assert self.validator.validate_pickup_code(long_code) is False

    def test_exact_max_length_passes(self):
        max_code = "A" * 20
        assert self.validator.validate_pickup_code(max_code) is True

    def test_contains_chinese_fails(self):
        assert self.validator.validate_pickup_code("取餐123") is False

    def test_lowercase_alphanumeric_passes(self):
        assert self.validator.validate_pickup_code("a123") is True

    def test_mixed_symbols_fails(self):
        assert self.validator.validate_pickup_code("12#4") is False


class TestValidatePhoneTail:

    def setup_method(self):
        self.validator = OCRValidator()

    def test_four_digits_passes(self):
        assert self.validator.validate_phone_tail("1234") is True

    def test_three_digits_fails(self):
        assert self.validator.validate_phone_tail("123") is False

    def test_five_digits_fails(self):
        assert self.validator.validate_phone_tail("12345") is False

    def test_contains_letters_fails(self):
        assert self.validator.validate_phone_tail("12a4") is False

    def test_none_returns_none(self):
        assert self.validator.validate_phone_tail(None) is None

    def test_all_zeros_passes(self):
        assert self.validator.validate_phone_tail("0000") is True

    def test_contains_symbols_fails(self):
        assert self.validator.validate_phone_tail("12-4") is False

    def test_empty_string_fails(self):
        assert self.validator.validate_phone_tail("") is False


class TestValidateCustomerName:

    def setup_method(self):
        self.validator = OCRValidator()

    def test_normal_chinese_name_passes(self):
        assert self.validator.validate_customer_name("张三") is True

    def test_three_chars_chinese_name_passes(self):
        assert self.validator.validate_customer_name("李小明") is True

    def test_four_chars_chinese_name_passes(self):
        assert self.validator.validate_customer_name("欧阳小明") is True

    def test_english_name_passes(self):
        assert self.validator.validate_customer_name("John") is True

    def test_empty_string_fails(self):
        assert self.validator.validate_customer_name("") is False

    def test_too_long_name_fails(self):
        long_name = "张" * 21
        assert self.validator.validate_customer_name(long_name) is False

    def test_pure_numbers_fails(self):
        assert self.validator.validate_customer_name("12345") is False

    def test_pure_symbols_fails(self):
        assert self.validator.validate_customer_name("!!!") is False

    def test_none_returns_none(self):
        assert self.validator.validate_customer_name(None) is None

    def test_two_chars_boundary_passes(self):
        assert self.validator.validate_customer_name("李四") is True

    def test_mixed_chinese_english_passes(self):
        assert self.validator.validate_customer_name("李Tom") is True


class TestValidateMerchant:

    def setup_method(self):
        self.validator = OCRValidator()

    def test_normal_merchant_passes(self):
        assert self.validator.validate_merchant("麦当劳") is True

    def test_empty_string_fails(self):
        assert self.validator.validate_merchant("") is False

    def test_pure_symbols_fails(self):
        assert self.validator.validate_merchant("###") is False

    def test_none_returns_none(self):
        assert self.validator.validate_merchant(None) is None

    def test_english_merchant_passes(self):
        assert self.validator.validate_merchant("KFC") is True

    def test_mixed_merchant_passes(self):
        assert self.validator.validate_merchant("奶茶1号店") is True


class TestIsTextMeaningful:

    def setup_method(self):
        self.validator = OCRValidator()

    def test_normal_text_returns_true(self):
        assert self.validator.is_text_meaningful("取餐码1234") is True

    def test_pure_spaces_returns_false(self):
        assert self.validator.is_text_meaningful("   ") is False

    def test_pure_newlines_returns_false(self):
        assert self.validator.is_text_meaningful("\n\n\n") is False

    def test_pure_symbols_returns_false(self):
        assert self.validator.is_text_meaningful("!@#$%") is False

    def test_single_char_returns_true(self):
        assert self.validator.is_text_meaningful("好") is True

    def test_mixed_spaces_and_text_returns_true(self):
        assert self.validator.is_text_meaningful("  你好  ") is True

    def test_empty_string_returns_false(self):
        assert self.validator.is_text_meaningful("") is False


class TestValidate:

    def setup_method(self):
        self.validator = OCRValidator(min_confidence=0.6)

    def _make_ocr_results(self, confidences):
        return [{"text": f"text{i}", "confidence": c} for i, c in enumerate(confidences)]

    def test_all_fields_valid_returns_valid(self):
        info = {
            "customer_name": "张三",
            "pickup_code": "1234",
            "phone_tail": "5678",
            "merchant": "麦当劳",
            "raw_text": "取餐人：张三\n取餐码：1234\n手机尾号：5678\n商家：麦当劳",
        }
        ocr_results = self._make_ocr_results([0.9, 0.85, 0.8, 0.95])
        result = self.validator.validate(info, ocr_results)
        assert result["overall_valid"] is True
        assert "confidence_score" in result
        assert result["validated_info"]["customer_name"] == "张三"
        assert result["validated_info"]["pickup_code"] == "1234"
        assert result["validated_info"]["phone_tail"] == "5678"
        assert result["validated_info"]["merchant"] == "麦当劳"

    def test_partial_fields_invalid_keeps_valid(self):
        info = {
            "customer_name": "张三",
            "pickup_code": "!@#$",
            "phone_tail": "5678",
            "merchant": None,
            "raw_text": "取餐人：张三\n取餐码：!@#$\n手机尾号：5678",
        }
        ocr_results = self._make_ocr_results([0.9, 0.8, 0.85])
        result = self.validator.validate(info, ocr_results)
        assert result["validated_info"]["customer_name"] == "张三"
        assert result["validated_info"]["pickup_code"] is None
        assert result["validated_info"]["phone_tail"] == "5678"
        assert result["validated_info"]["merchant"] is None

    def test_all_fields_invalid_returns_empty_and_invalid(self):
        info = {
            "customer_name": "123",
            "pickup_code": "!@#$",
            "phone_tail": "abc",
            "merchant": "###",
            "raw_text": "乱码内容",
        }
        ocr_results = self._make_ocr_results([0.9, 0.8, 0.85, 0.75])
        result = self.validator.validate(info, ocr_results)
        assert result["overall_valid"] is False
        assert result["validated_info"]["customer_name"] is None
        assert result["validated_info"]["pickup_code"] is None
        assert result["validated_info"]["phone_tail"] is None
        assert result["validated_info"]["merchant"] is None

    def test_returns_validated_info_structure(self):
        info = {
            "customer_name": None,
            "pickup_code": None,
            "phone_tail": None,
            "merchant": None,
            "raw_text": "",
        }
        ocr_results = []
        result = self.validator.validate(info, ocr_results)
        assert "validated_info" in result
        assert "overall_valid" in result
        assert "confidence_score" in result
        validated = result["validated_info"]
        assert "customer_name" in validated
        assert "pickup_code" in validated
        assert "phone_tail" in validated
        assert "merchant" in validated
        assert "raw_text" in validated

    def test_low_confidence_makes_overall_invalid(self):
        info = {
            "customer_name": "张三",
            "pickup_code": "1234",
            "phone_tail": "5678",
            "merchant": "麦当劳",
            "raw_text": "取餐人：张三\n取餐码：1234",
        }
        ocr_results = self._make_ocr_results([0.3, 0.25])
        result = self.validator.validate(info, ocr_results)
        assert result["overall_valid"] is False

    def test_confidence_score_is_float(self):
        info = {
            "customer_name": "张三",
            "pickup_code": "1234",
            "phone_tail": "5678",
            "merchant": "麦当劳",
            "raw_text": "取餐人：张三\n取餐码：1234\n手机尾号：5678\n商家：麦当劳",
        }
        ocr_results = self._make_ocr_results([0.9, 0.8, 0.7, 0.6])
        result = self.validator.validate(info, ocr_results)
        assert isinstance(result["confidence_score"], float)

    def test_none_fields_stay_none_in_validated(self):
        info = {
            "customer_name": None,
            "pickup_code": None,
            "phone_tail": None,
            "merchant": None,
            "raw_text": "无内容",
        }
        ocr_results = self._make_ocr_results([0.9])
        result = self.validator.validate(info, ocr_results)
        assert result["validated_info"]["customer_name"] is None
        assert result["validated_info"]["pickup_code"] is None
        assert result["validated_info"]["phone_tail"] is None
        assert result["validated_info"]["merchant"] is None

    def test_raw_text_preserved(self):
        raw = "取餐人：张三\n取餐码：1234"
        info = {
            "customer_name": "张三",
            "pickup_code": "1234",
            "phone_tail": None,
            "merchant": None,
            "raw_text": raw,
        }
        ocr_results = self._make_ocr_results([0.9, 0.8])
        result = self.validator.validate(info, ocr_results)
        assert result["validated_info"]["raw_text"] == raw
