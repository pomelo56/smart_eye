import os
import re

os.environ.setdefault("PADDLE_PDX_CACHE_HOME", os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    ".paddlex_cache"
))


class OCREngine:

    def __init__(self):
        self._ocr = None
        self._initialized = False

    def _ensure_initialized(self):
        if not self._initialized:
            from paddleocr import PaddleOCR
            from src.config import PADDLEOCR_LANG, PADDLEOCR_USE_ANGLE_CLS
            self._ocr = PaddleOCR(
                use_angle_cls=PADDLEOCR_USE_ANGLE_CLS,
                lang=PADDLEOCR_LANG,
            )
            self._initialized = True

    def recognize(self, image):
        self._ensure_initialized()
        result = self._ocr.predict(image)
        if not result:
            return []
        ocr_result = result[0]
        rec_texts = ocr_result.get("rec_texts", [])
        rec_scores = ocr_result.get("rec_scores", [])
        rec_boxes = ocr_result.get("rec_boxes", [])
        ocr_results = []
        for i, text in enumerate(rec_texts):
            confidence = rec_scores[i] if i < len(rec_scores) else 0.0
            box = rec_boxes[i] if i < len(rec_boxes) else []
            ocr_results.append({
                "text": text,
                "confidence": float(confidence),
                "box": box,
            })
        return ocr_results

    def extract_takeout_info(self, ocr_results):
        info = {
            "customer_name": None,
            "pickup_code": None,
            "phone_tail": None,
            "merchant": None,
            "raw_text": "",
        }

        if not ocr_results:
            return info

        raw_texts = []
        for item in ocr_results:
            text = item.get("text", "")
            raw_texts.append(text)

        info["raw_text"] = "\n".join(raw_texts)

        customer_keywords = ["取餐人", "收件人", "顾客", "姓名"]
        pickup_keywords = ["取餐码", "取餐号", "订单号", "取餐编号"]
        phone_keywords = ["手机尾号", "尾号", "手机号"]
        merchant_keywords = ["商家", "店铺"]

        merchant_candidates = []

        for item in ocr_results:
            text = item.get("text", "")
            matched_other = False

            if info["customer_name"] is None:
                for kw in customer_keywords:
                    pattern = rf"{kw}\s*[：:]\s*(.+)"
                    match = re.search(pattern, text)
                    if match:
                        info["customer_name"] = match.group(1).strip()
                        matched_other = True
                        break

            if info["pickup_code"] is None:
                for kw in pickup_keywords:
                    pattern = rf"{kw}\s*[：:]\s*(.+)"
                    match = re.search(pattern, text)
                    if match:
                        info["pickup_code"] = match.group(1).strip()
                        matched_other = True
                        break

            phone_found = False
            if info["phone_tail"] is None:
                for kw in phone_keywords:
                    pattern = rf"{kw}\s*[：:]\s*(.+)"
                    match = re.search(pattern, text)
                    if match:
                        value = match.group(1).strip()
                        tail_match = re.search(r"\d{4}$", value)
                        if tail_match:
                            info["phone_tail"] = tail_match.group()
                        matched_other = True
                        phone_found = True
                        break

                if not phone_found and info["phone_tail"] is None:
                    asterisk_match = re.search(r"\d{3}\*+\d{4}", text)
                    if asterisk_match:
                        info["phone_tail"] = text[-4:]
                        matched_other = True
                        phone_found = True

            if info["merchant"] is None:
                for kw in merchant_keywords:
                    pattern = rf"{kw}\s*[：:]\s*(.+)"
                    match = re.search(pattern, text)
                    if match:
                        info["merchant"] = match.group(1).strip()
                        matched_other = True
                        break

            if not matched_other:
                has_colon = re.search(r"[：:]", text) is not None
                is_phone = re.search(r"\d{3}\*+\d{4}", text) is not None
                if not has_colon and not is_phone and text.strip():
                    merchant_candidates.append(text.strip())

        if info["merchant"] is None and len(merchant_candidates) == 1:
            info["merchant"] = merchant_candidates[0]

        return info

    def format_speech(self, info):
        parts = []

        customer_name = info.get("customer_name")
        if customer_name:
            parts.append(f"取餐人{customer_name}")

        pickup_code = info.get("pickup_code")
        if pickup_code:
            parts.append(f"取餐码{pickup_code}")

        phone_tail = info.get("phone_tail")
        if phone_tail:
            parts.append(f"手机尾号{phone_tail}")

        merchant = info.get("merchant")
        if merchant:
            parts.append(f"商家{merchant}")

        if not parts:
            return "未识别到有效信息"

        return "，".join(parts)
