# -*- coding: utf-8 -*-
"""
生成一份示例 data.js，用于在本机预览页面（不需要 Kindle）

    python tools/sample_data.py
    # 然后用浏览器打开 device/www/index.html

设备上 data.js 由 device/frame.sh 每 20 秒重写一次；这里造一份假的给你看效果。
注意：msgs 必须按时间**升序**排列（ntfy 就是这个顺序），页面渲染时倒序显示。
"""
import io
import json
import os
import time
import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "device", "www", "data.js")

now = datetime.datetime.now().replace(minute=0, second=0, microsecond=0)
hours = [now + datetime.timedelta(hours=i) for i in range(24)]
ht = [h.strftime("%Y-%m-%dT%H:00") for h in hours]

# 一天的曲线：傍晚 18° 一路降到清晨 10°，再回升
temps = [18.4, 18.0, 17.2, 16.1, 15.0, 14.0, 13.1, 12.4, 11.8, 11.3, 10.9, 10.6,
         10.4, 10.6, 11.4, 12.8, 14.6, 16.2, 17.4, 18.1, 18.4, 18.0, 17.4, 16.8]
prec = [0, 0, 0, 10, 20, 30, 30, 20, 10, 0, 0, 0, 0, 0, 5, 10, 10, 5, 0, 0, 0, 0, 0, 0]

day0 = datetime.date.today()
dt_ = [(day0 + datetime.timedelta(days=i)).isoformat() for i in range(4)]

weather = {
    "current": {
        "time": now.strftime("%Y-%m-%dT%H:00"),
        "temperature_2m": 18.4,
        "relative_humidity_2m": 57,
        "apparent_temperature": 16.1,
        "weather_code": 2,
        "wind_speed_10m": 12.6,
        "wind_direction_10m": 135,
    },
    "hourly": {"time": ht, "temperature_2m": temps, "precipitation_probability": prec},
    "daily": {
        "time": dt_,
        "weather_code": [2, 61, 0, 3],
        "temperature_2m_max": [19.2, 17.4, 21.0, 20.1],
        "temperature_2m_min": [8.1, 9.6, 7.2, 10.3],
        "sunrise": [dt_[0] + "T06:41"] * 4,
        "sunset": [dt_[0] + "T17:46"] * 4,
        "precipitation_probability_max": [20, 80, 0, 30],
    },
}

air = {"current": {"time": now.strftime("%Y-%m-%dT%H:00"), "us_aqi": 42, "pm2_5": 12.5}}

t0 = int(time.time())
msgs = [  # 升序
    {"id": "a5", "time": t0 - 97200, "event": "message", "message": "周末带孩子去博物馆，早点起"},
    {"id": "a4", "time": t0 - 32400, "event": "message", "message": "水费单在鞋柜上，月底前交掉"},
    {"id": "a3", "time": t0 - 10800, "event": "message", "message": "阳台的花浇过了，出门把窗户关上"},
    {"id": "a2", "time": t0 - 5400, "event": "message", "message": "明天上午 9 点社区体检，记得空腹"},
    {"id": "a1", "time": t0 - 600, "event": "message", "message": "下班买点排骨回来，顺便拿下快递"},
]

data = {
    "ts": t0,
    "bat": "87",
    "bright": 40,
    "place": "中国 · 某某省某某市",
    "weather": weather,
    "air": air,
    "msgs": msgs,
}

js = "window.DATA=" + json.dumps(data, ensure_ascii=False) + ";\n"
io.open(OUT, "w", encoding="utf-8", newline="\n").write(js)
print("written %s (%d bytes)" % (OUT, len(js.encode("utf-8"))))
