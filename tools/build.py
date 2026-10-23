# -*- coding: utf-8 -*-
"""
构建脚本：把 src/dashboard.html 变成设备上要用的 index.html

做三件事：
  1. 把 tools/vendor/lunar.js（农历库，417 KB）整段内联进页面
     —— 设备是 QtWebKit 4.8，不能用 <script src> 加载本地以外的东西，
        但同目录的 src 其实可以；内联只是为了让页面只有一个文件，拷贝更省事。
  2. 按 device/config.sh 里的 TOPIC 生成二维码（PNG data URI，1-bit，整数模块不糊）
  3. 把 __TOPIC__ 占位符替换成主题名

用法：
    python tools/build.py
输出：
    device/www/index.html
"""
import io
import os
import re
import sys
import base64

try:
    import qrcode
except ImportError:
    sys.exit("需要 qrcode 库： python -m pip install qrcode pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "device", "config.sh")
SRC = os.path.join(ROOT, "src", "dashboard.html")
LUNAR = os.path.join(ROOT, "tools", "vendor", "lunar.js")
OUT = os.path.join(ROOT, "device", "www", "index.html")


def read_config(path):
    """把 config.sh 里的 KEY="value" 解析成 dict"""
    cfg = {}
    with io.open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r'^([A-Z_]+)="?(.*?)"?$', line)
            if m:
                cfg[m.group(1)] = m.group(2)
    return cfg


def main():
    cfg = read_config(CONFIG)
    topic = cfg.get("TOPIC", "").strip()
    if not topic or topic.startswith("CHANGE-ME"):
        print("提示：device/config.sh 里的 TOPIC 还是占位值，二维码会指向一个无效主题。")
        print("      生成示例： python -c \"import secrets;print(secrets.token_hex(10))\"")
    url = "https://ntfy.sh/" + (topic or "placeholder")

    html = io.open(SRC, encoding="utf-8", newline="").read()
    lunar = io.open(LUNAR, encoding="utf-8", newline="").read()

    # --- 二维码 ---
    qr = qrcode.QRCode(border=2, box_size=3, error_correction=qrcode.constants.ERROR_CORRECT_M)
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white").convert("1")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    uri = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()

    html = html.replace("__LUNAR__", lunar)
    html = html.replace("__QR__", uri)
    html = html.replace("__TOPIC__", topic or "placeholder")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    io.open(OUT, "w", encoding="utf-8", newline="\n").write(html)
    print("qr modules %d, png %d B" % (qr.modules_count, len(buf.getvalue())))
    print("written %s  (%d bytes)" % (OUT, len(html.encode("utf-8"))))


if __name__ == "__main__":
    main()
