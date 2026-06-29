import re


class OCRValidator:

    def __init__(self, min_confidence=0.6, max_pickup_code_len=20, max_name_len=20):
        self.min_confidence = min_confidence
        self.max_pickup_code_len = max_pickup_code_len
        self.max_name_len = max_name_len

    def validate(self, takeout_info, ocr_results=None):
        result = {
            "validated_info": {},
            "overall_valid": False,
            "confidence_score": 0.0,
            "field_validity": {},
        }

        customer_name = takeout_info.get("customer_name")
        pickup_code = takeout_info.get("pickup_code")
        phone_tail = takeout_info.get("phone_tail")
        merchant = takeout_info.get("merchant")
        raw_text = takeout_info.get("raw_text", "")

        name_valid = self.validate_customer_name(customer_name)
        code_valid = self.validate_pickup_code(pickup_code)
        tail_valid = self.validate_phone_tail(phone_tail)
        merchant_valid = self.validate_merchant(merchant)

        result["field_validity"] = {
            "customer_name": name_valid if name_valid is not None else False,
            "pickup_code": code_valid if code_valid is not None else False,
            "phone_tail": tail_valid if tail_valid is not None else False,
            "merchant": merchant_valid if merchant_valid is not None else False,
        }

        result["validated_info"] = {
            "customer_name": customer_name if name_valid else None,
            "pickup_code": pickup_code if code_valid else None,
            "phone_tail": phone_tail if tail_valid else None,
            "merchant": merchant if merchant_valid else None,
            "raw_text": raw_text,
        }

        if ocr_results:
            avg_confidence = self._calculate_avg_confidence(ocr_results)
            result["confidence_score"] = avg_confidence
        else:
            valid_fields = sum(1 for v in result["field_validity"].values() if v)
            total_fields = len(result["field_validity"])
            result["confidence_score"] = valid_fields / total_fields if total_fields > 0 else 0.0

        has_valid_field = any(result["field_validity"].values())

        if ocr_results:
            overall_confidence_ok = self.validate_overall_confidence(ocr_results)
            result["overall_valid"] = has_valid_field and overall_confidence_ok
        else:
            result["overall_valid"] = has_valid_field

        return result

    def validate_overall_confidence(self, ocr_results):
        if not ocr_results:
            return False
        avg_confidence = self._calculate_avg_confidence(ocr_results)
        return avg_confidence >= self.min_confidence

    def validate_pickup_code(self, code):
        if code is None:
            return None
        if len(code) < 1 or len(code) > self.max_pickup_code_len:
            return False
        if re.search(r"[\u4e00-\u9fff]", code):
            return False
        if not re.fullmatch(r"[a-zA-Z0-9]+", code):
            return False
        if len(code) < 1:
            return False
        return True

    def validate_phone_tail(self, tail):
        if tail is None:
            return None
        if len(tail) != 4:
            return False
        if not re.fullmatch(r"\d{4}", tail):
            return False
        return True

    def validate_customer_name(self, name):
        if name is None:
            return None
        if not name or not name.strip():
            return False
        if len(name) > self.max_name_len:
            return False
        if re.fullmatch(r"[\d\W_]+", name):
            return False
        if re.search(r"[a-zA-Z\u4e00-\u9fff]", name):
            return True
        return False

    def validate_merchant(self, merchant):
        if merchant is None:
            return None
        if not merchant or not merchant.strip():
            return False
        if re.fullmatch(r"[\W_]+", merchant):
            return False
        return self.is_text_meaningful(merchant)

    def is_text_meaningful(self, text):
        if not text or not text.strip():
            return False
        if re.search(r"[a-zA-Z0-9\u4e00-\u9fff]", text):
            return True
        return False

    def _calculate_avg_confidence(self, ocr_results):
        if not ocr_results:
            return 0.0
        total = 0.0
        count = 0
        for item in ocr_results:
            conf = item.get("confidence", 0.0)
            total += conf
            count += 1
        return total / count if count > 0 else 0.0
