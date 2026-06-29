import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from src.feedback.feedback_collector import FeedbackCollector


def print_help():
    print("用法: python tools/view_feedback.py [选项]")
    print()
    print("选项:")
    print("  --list          列出所有反馈（默认行为）")
    print("  --type TYPE     按类型过滤（detection_error / ocr_error）")
    print("  --date DATE     按日期过滤（YYYY-MM-DD）")
    print("  --show ID       显示某条反馈的详细信息")
    print("  --clear         清空所有反馈（需要确认）")
    print("  --count         显示反馈总数")
    print("  --help          显示帮助信息")


def format_datetime(ts):
    if not ts:
        return ""
    if "T" in ts:
        return ts.replace("T", " ")
    return ts


def format_context(context, indent=2):
    indent_str = " " * indent
    if isinstance(context, dict):
        lines = []
        for k, v in context.items():
            if isinstance(v, (dict, list)):
                lines.append(f"{indent_str}{k}:")
                lines.append(format_context(v, indent + 2))
            else:
                lines.append(f"{indent_str}{k}: {v}")
        return "\n".join(lines)
    elif isinstance(context, list):
        lines = []
        for i, item in enumerate(context):
            if isinstance(item, (dict, list)):
                lines.append(f"{indent_str}[{i}]:")
                lines.append(format_context(item, indent + 2))
            else:
                lines.append(f"{indent_str}[{i}]: {item}")
        return "\n".join(lines)
    else:
        return f"{indent_str}{context}"


def cmd_list(collector, feedback_type=None, date=None):
    feedbacks = collector.get_feedback_list(date=date, feedback_type=feedback_type)
    if not feedbacks:
        print("暂无反馈数据")
        return
    print(f"{'ID':<14} {'类型':<18} {'日期时间'}")
    print("-" * 60)
    for fb in feedbacks:
        dt = format_datetime(fb.get("timestamp", ""))
        print(f"{fb['id']:<14} {fb.get('type', ''):<18} {dt}")


def cmd_show(collector, fid):
    fb = collector.get_feedback_by_id(fid)
    if not fb:
        print(f"未找到反馈: {fid}")
        return
    print(f"反馈ID: {fb['id']}")
    print(f"类型: {fb.get('type', '')}")
    print(f"时间: {format_datetime(fb.get('timestamp', ''))}")
    print(f"图片: {fb.get('image_path', '无')}")
    print("上下文:")
    if fb.get("context"):
        print(format_context(fb["context"], indent=2))
    else:
        print("  (无)")


def cmd_count(collector, feedback_type=None, date=None):
    count = collector.get_feedback_count(date=date, feedback_type=feedback_type)
    filter_desc = []
    if feedback_type:
        filter_desc.append(f"类型={feedback_type}")
    if date:
        filter_desc.append(f"日期={date}")
    if filter_desc:
        print(f"反馈总数 ({', '.join(filter_desc)}): {count}")
    else:
        print(f"反馈总数: {count}")


def cmd_clear(collector):
    count = collector.get_feedback_count()
    if count == 0:
        print("当前没有反馈数据")
        return
    print(f"确定要清空所有 {count} 条反馈吗？此操作不可恢复！")
    answer = input("请输入 'yes' 确认: ").strip().lower()
    if answer == "yes":
        collector.clear_feedback()
        print("已清空所有反馈")
    else:
        print("操作已取消")


def main():
    args = sys.argv[1:]

    if not args or "--help" in args or "-h" in args:
        if "--help" in args or "-h" in args:
            print_help()
            return
        args = ["--list"]

    collector = FeedbackCollector()

    feedback_type = None
    date = None
    show_id = None

    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--list":
            pass
        elif arg == "--type":
            if i + 1 < len(args):
                feedback_type = args[i + 1]
                i += 1
            else:
                print("错误: --type 需要参数")
                sys.exit(1)
        elif arg == "--date":
            if i + 1 < len(args):
                date = args[i + 1]
                i += 1
            else:
                print("错误: --date 需要参数")
                sys.exit(1)
        elif arg == "--show":
            if i + 1 < len(args):
                show_id = args[i + 1]
                i += 1
            else:
                print("错误: --show 需要参数")
                sys.exit(1)
        elif arg == "--clear":
            cmd_clear(collector)
            return
        elif arg == "--count":
            cmd_count(collector, feedback_type=feedback_type, date=date)
            return
        elif arg == "--help" or arg == "-h":
            print_help()
            return
        else:
            print(f"未知选项: {arg}")
            print_help()
            sys.exit(1)
        i += 1

    if show_id:
        cmd_show(collector, show_id)
    else:
        cmd_list(collector, feedback_type=feedback_type, date=date)


if __name__ == "__main__":
    main()
