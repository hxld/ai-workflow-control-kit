"""
scan_inbox.py - 扫描 vault inbox 目录，输出文件列表和元数据。
用法：python scan_inbox.py <vault-path>
"""

import os
import sys
import json
from datetime import datetime

EXT_READABLE = {".md", ".pdf", ".txt"}
EXT_IMAGE = {".jpg", ".jpeg", ".png", ".webp", ".svg", ".gif"}
EXT_NEED_CONVERT = {".docx", ".doc", ".xlsx", ".xls", ".pptx", ".ppt"}


def scan_inbox(vault_path):
    inbox_dir = os.path.join(vault_path, "inbox")
    if not os.path.isdir(inbox_dir):
        print(f"inbox 目录不存在：{inbox_dir}")
        return

    files = []
    for f in os.listdir(inbox_dir):
        fp = os.path.join(inbox_dir, f)
        if not os.path.isfile(fp):
            continue
        ext = os.path.splitext(f)[1].lower()
        stat = os.stat(fp)
        mt = datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M")
        size_kb = round(stat.st_size / 1024, 1)

        if ext in EXT_READABLE:
            status = "readable"
        elif ext in EXT_IMAGE:
            status = "image"
        elif ext in EXT_NEED_CONVERT:
            status = "need-convert"
        else:
            status = "unknown"

        files.append(
            {
                "name": f,
                "ext": ext,
                "size_kb": size_kb,
                "modified": mt,
                "status": status,
            }
        )

    if not files:
        print("inbox 为空，没有待处理文件。")
        return

    print(f"📥 inbox/ 中发现 {len(files)} 个文件：\n")
    print(f"{'文件名':<45} {'格式':<6} {'大小':<10} {'修改时间':<18} {'状态'}")
    print("-" * 90)

    readable = 0
    need_convert = 0
    image = 0

    for f in files:
        print(
            f"{f['name']:<45} {f['ext']:<6} {f['size_kb']:>6}KB  {f['modified']:<18} {f['status']}"
        )
        if f["status"] == "readable":
            readable += 1
        elif f["status"] == "need-convert":
            need_convert += 1
        elif f["status"] == "image":
            image += 1

    print(
        f"\n汇总：可直接处理 {readable} 个 | 需转换 {need_convert} 个 | 图片 {image} 个"
    )


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法：python scan_inbox.py <vault-path>")
        sys.exit(1)
    scan_inbox(sys.argv[1])
