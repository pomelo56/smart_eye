#!/usr/bin/env python3
"""
BlindFind Web Demo - Gradio + ngrok 演示版本
用于通过手机浏览器访问和体验 BlindFind 功能
"""

import io
import os
import sys
import traceback
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# 添加项目根目录到路径
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.detector import ObjectDetector
from src.ocr_engine import OCREngine
from src.ai_guard.detection_validator import DetectionValidator
from src.ai_guard.ocr_validator import OCRValidator
from src.config import (
    YOLO_MODEL, YOLO_CONFIDENCE_THRESHOLD, YOLO_IOU_THRESHOLD,
    OCR_MIN_CONFIDENCE, OCR_MAX_PICKUP_CODE_LEN, OCR_MAX_NAME_LEN,
    DETECTION_MIN_CONFIDENCE, DETECTION_MIN_BBOX_SIZE,
    DETECTION_MAX_BBOX_RATIO, DETECTION_MIN_STABLE_FRAMES,
    DETECTION_CLASS_CONFIDENCE_OVERRIDES,
)


def draw_detections(image, detections):
    """在图像上绘制检测框"""
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/PingFang.ttc", 24)
    except:
        font = ImageFont.load_default()

    for det in detections:
        x1, y1, x2, y2 = det["bbox"]
        label = f"{det['class_name']} {det['confidence']:.2f}"
        color = "red"

        draw.rectangle([x1, y1, x2, y2], outline=color, width=3)
        draw.text((x1, y1 - 30), label, fill=color, font=font)

    return image


def format_detection_results(detections):
    """格式化检测结果为语音文本"""
    if not detections:
        return "未检测到目标"

    # 按置信度排序
    sorted_dets = sorted(detections, key=lambda x: x["confidence"], reverse=True)

    # 只取前5个
    top_dets = sorted_dets[:5]

    parts = []
    for det in top_dets:
        class_name = det["class_name"]
        confidence = det["confidence"]
        parts.append(f"{class_name}，置信度{int(confidence * 100)}%")

    return "检测到：" + "；".join(parts)


class BlindFindDemo:
    """BlindFind 演示类"""

    def __init__(self):
        print("初始化 BlindFind Demo...")
        print("  - 加载目标检测模型...")
        self.detector = ObjectDetector()
        self.detection_validator = DetectionValidator(
            min_confidence=DETECTION_MIN_CONFIDENCE,
            min_bbox_size=DETECTION_MIN_BBOX_SIZE,
            max_bbox_ratio=DETECTION_MAX_BBOX_RATIO,
            min_stable_frames=DETECTION_MIN_STABLE_FRAMES,
            class_confidence_overrides=DETECTION_CLASS_CONFIDENCE_OVERRIDES,
        )

        print("  - 加载 OCR 模型...")
        self.ocr_engine = OCREngine()
        self.ocr_validator = OCRValidator(
            min_confidence=OCR_MIN_CONFIDENCE,
            max_pickup_code_len=OCR_MAX_PICKUP_CODE_LEN,
            max_name_len=OCR_MAX_NAME_LEN,
        )

        print("初始化完成！")

    def detect_objects(self, image):
        """目标检测"""
        try:
            # 转换为RGB（如果是RGBA）
            if image.mode == 'RGBA':
                image = image.convert('RGB')

            # 转换为numpy数组
            frame = np.array(image)

            # 执行检测
            raw_detections = self.detector.detect(frame)

            # 验证检测结果
            validated_detections = self.detection_validator.validate(raw_detections)

            # 绘制检测框
            result_image = image.copy()
            if validated_detections:
                result_image = draw_detections(result_image, validated_detections)

            # 格式化结果
            result_text = format_detection_results(validated_detections)

            return result_image, result_text

        except Exception as e:
            traceback.print_exc()
            return image, f"检测出错：{str(e)}"

    def recognize_text(self, image):
        """OCR 文字识别"""
        try:
            if image.mode == 'RGBA':
                image = image.convert('RGB')

            frame = np.array(image)

            ocr_results = self.ocr_engine.recognize(frame)

            if not ocr_results:
                return (
                    image,
                    "未识别到任何文字",
                    "无",
                    "N/A",
                    "未识别到文字"
                )

            raw_texts = [f"{item['text']} ({item['confidence']:.2f})"
                         for item in ocr_results]
            raw_text_display = "\n".join(raw_texts)

            info = self.ocr_engine.extract_takeout_info(ocr_results)

            info_display = (
                f"取餐人：{info.get('customer_name') or '未识别'}\n"
                f"取餐码：{info.get('pickup_code') or '未识别'}\n"
                f"手机尾号：{info.get('phone_tail') or '未识别'}\n"
                f"商家：{info.get('merchant') or '未识别'}"
            )

            validation = self.ocr_validator.validate(info, ocr_results)

            if validation["overall_valid"]:
                valid_text = "通过 ✓"
                speech_text = self.ocr_engine.format_speech(validation["validated_info"])
            else:
                reasons = validation.get("failed_reasons", [])
                if reasons:
                    valid_text = "未通过 ✗\n原因：" + "；".join(reasons[:3])
                else:
                    valid_text = "未通过 ✗"
                speech_text = "识别结果不确定，请调整角度或距离后重试"

            return image, raw_text_display, info_display, valid_text, speech_text

        except Exception as e:
            traceback.print_exc()
            return image, f"错误：{str(e)}", "N/A", "N/A", f"OCR 出错：{str(e)}"


def create_gradio_app():
    """创建 Gradio 应用"""
    import gradio as gr

    demo = BlindFindDemo()

    with gr.Blocks(title="盲寻 BlindFind 演示") as app:
        gr.Markdown("# 盲寻 BlindFind 演示\n上传图片体验目标检测和文字识别功能")

        with gr.Row():
            with gr.Column():
                image_input = gr.Image(
                    label="上传图片",
                    type="pil",
                    height=350,
                )
                with gr.Row():
                    detect_btn = gr.Button("目标检测", variant="primary")
                    ocr_btn = gr.Button("文字识别", variant="secondary")

            with gr.Column():
                image_output = gr.Image(
                    label="结果图像",
                    type="pil",
                    height=350,
                )
                speech_output = gr.Textbox(
                    label="语音播报（最终输出）",
                    lines=2,
                    show_label=True,
                )

        with gr.Accordion("查看详细识别过程", open=False):
            with gr.Row():
                with gr.Column():
                    raw_ocr_output = gr.Textbox(
                        label="1. 原始OCR识别文字（含置信度）",
                        lines=8,
                        show_label=True,
                    )
                with gr.Column():
                    info_output = gr.Textbox(
                        label="2. 提取的外卖信息",
                        lines=5,
                        show_label=True,
                    )
            validation_output = gr.Textbox(
                label="3. AI验证层结果",
                lines=2,
                show_label=True,
            )

        gr.Markdown("---")
        gr.Markdown("### 使用说明")
        gr.Markdown("""
        1. **目标检测**：上传图片后点击「目标检测」，系统会识别图片中的物体
        2. **文字识别**：上传图片后点击「文字识别」，系统会提取图片中的文字信息

        适用于识别外卖包装、快递包裹等场景。
        """)

        # 绑定事件
        detect_btn.click(
            fn=demo.detect_objects,
            inputs=image_input,
            outputs=[image_output, speech_output],
        )

        ocr_btn.click(
            fn=demo.recognize_text,
            inputs=image_input,
            outputs=[image_output, raw_ocr_output, info_output, validation_output, speech_output],
        )

    return app


def get_ngrok_url(api_key=None):
    """获取 ngrok 公网 URL"""
    try:
        import pyngrok.ngrok as ngrok

        if api_key:
            ngrok.set_auth_token(api_key)

        tunnel = ngrok.connect(7860, "gradio")
        public_url = tunnel.public_url
        print(f"\n{'='*60}")
        print(f"公网访问地址: {public_url}")
        print("在安卓手机浏览器中打开上述地址即可体验")
        print(f"{'='*60}\n")
        return public_url

    except ImportError:
        print("提示: 安装 pyngrok 以启用公网访问: pip install pyngrok")
        return None
    except Exception as e:
        print(f"ngrok 连接失败: {e}")
        return None


def main():
    """主函数"""
    import argparse
    from pathlib import Path

    parser = argparse.ArgumentParser(description="BlindFind Web Demo")
    parser.add_argument("--https", action="store_true",
                        help="启用HTTPS（自签名证书，可使用摄像头）")
    parser.add_argument("--share", action="store_true",
                        help="启用 Gradio 公网分享（HTTPS，可使用摄像头）")
    parser.add_argument("--ngrok-api-key", type=str, help="ngrok API Key")
    parser.add_argument("--port", type=int, default=7860, help="端口号")
    args = parser.parse_args()

    print("\n" + "="*60)
    print("BlindFind Web Demo 启动中...")
    print("="*60)

    # 创建 Gradio 应用
    app = create_gradio_app()

    if args.ngrok_api_key:
        url = get_ngrok_url(args.ngrok_api_key)
        if url:
            print(f"Gradio 本地地址: http://127.0.0.1:{args.port}")
            print(f"ngrok 公网地址: {url}\n")

    # 构建启动参数
    launch_kwargs = {
        "server_name": "0.0.0.0",
        "server_port": args.port,
        "share": args.share,
        "inbrowser": False,
    }

    # HTTPS 模式（自签名证书，用于启用摄像头）
    if args.https:
        cert_dir = Path(__file__).parent.parent / "data" / "certs"
        cert_file = cert_dir / "cert.pem"
        key_file = cert_dir / "key.pem"
        if cert_file.exists() and key_file.exists():
            launch_kwargs["ssl_certfile"] = str(cert_file)
            launch_kwargs["ssl_keyfile"] = str(key_file)
            launch_kwargs["ssl_verify"] = False
            protocol = "https"
        else:
            print("警告: 未找到证书文件，将使用HTTP模式")
            protocol = "http"
    else:
        protocol = "http"

    print(f"\n访问地址: {protocol}://127.0.0.1:{args.port}")
    if protocol == "https":
        print("（首次访问时浏览器会提示不安全，点击'继续前往'即可）")
    print()

    app.launch(**launch_kwargs)


if __name__ == "__main__":
    main()
