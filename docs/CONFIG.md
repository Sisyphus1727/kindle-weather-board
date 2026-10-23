# 配置指南

所有可调的东西都在 **`device/config.sh`** 一个文件里。

改完之后的生效方式：

| 改了 | 怎么生效 |
|---|---|
| `LAT` / `LON` / `PLACE_SUB` / `REFRESH_*` / `BRIGHT_MAX` | 把 `config.sh` 拷回 `/mnt/us/frame/`，**重启设备**（或拔插数据线后等 20 秒，看门狗会重启页面） |
| `TOPIC` | 除了拷 `config.sh`，还要**重新构建页面**：`python tools/build.py`，再把新的 `device/www/index.html` 拷过去（因为二维码是构建时画的） |

---

## 1. 改位置

### 1.1 查经纬度

Open-Meteo 有地理编码接口，用名字直接查（返回里就有 `latitude` / `longitude` / `timezone`）：

```
http://geocoding-api.open-meteo.com/v1/search?name=杭州&count=3&language=zh
```

浏览器打开就能看到：

```json
{"results":[{"name":"杭州","latitude":30.29365,"longitude":120.16142,"timezone":"Asia/Shanghai", ...}]}
```

也可以直接在 <https://open-meteo.com/en/docs> 页面右上角的地图/搜索框选点，它会把经纬度填进示例 URL。

### 1.2 写进配置

```sh
LAT="30.29365"          # 北纬为正
LON="120.16142"         # 东经为正
TZ_ARG="Asia%2FShanghai"  # 时区，注意斜杠要编码成 %2F
PLACE_SUB="中国 · 浙江省杭州市"
```

- `LAT/LON` 只影响天气和空气质量请求
- `PLACE_SUB` **纯粹是显示用**的文字，写什么都行（写"家里"也可以），不影响任何数据
- 时区决定"今天是哪天"、"几点"的算法，写错会导致逐时曲线对不上

> 精度提示：Open-Meteo 会把坐标吸附到最近的网格点（几公里一个格），所以填到小数点后 4 位就足够，不用纠结。

---

## 2. 改推送主题

推送用的是 [ntfy.sh](https://ntfy.sh) 的公共实例：**主题名就是密码**，谁知道了主题名就能往你的屏幕上推东西。

### 2.1 生成一个随机主题

```bash
python -c "import secrets; print(secrets.token_hex(10))"
```

得到类似 `a3f9c1e8b74d2065aa11`，填进 `config.sh`：

```sh
TOPIC="a3f9c1e8b74d2065aa11"
```

### 2.2 重新构建页面（二维码会变）

```bash
python tools/build.py
# 把新的 device/www/index.html 拷到 /mnt/us/frame/www/index.html
```

### 2.3 手机端怎么发

三种都行：

1. **扫码**：Kindle 留言页上的二维码直接指向 `https://ntfy.sh/<你的主题>` 的网页发布页
2. **装 App**：ntfy 官方 App（Android / iOS），订阅同一个主题即可推送
3. **命令行**：
   ```bash
   curl -d "下班买点排骨回来" http://ntfy.sh/a3f9c1e8b74d2065aa11
   ```

### 2.4 推送指令

| 发什么 | 效果 |
|---|---|
| 任意文字 | 出现在留言页，新的在最上面 |
| 图片 | 留言页显示「【图片】xxx」 |
| `#clear` | **清空全部留言**（之后的新消息不受影响） |
| 什么都不发 | 超过 **48 小时**的留言自动消失 |

最多同时显示最近 8 条。

> 注意：`#clear` 这个消息本身也会在 ntfy 里留 12 小时，程序会按"这条消息的时间点"来清空，所以清完之后再推的消息能正常显示，不会被反复清掉。

---

## 3. 改刷新节奏

```sh
REFRESH_WEATHER=300   # 天气多久抓一次（秒）。天气接口按小时更新，300 完全够
REFRESH_MSGS=20       # 留言多久拉一次（秒）。想更快就调到 10，但会更费电
```

耗电参考：PW1 在 20 秒轮询 + 常显（关背光）下，一天大约掉 8~10%。

---

## 4. 改背光档位

```sh
BRIGHT_MAX=24
```

PW1 实测 24 档。查自己机型的档位：

```sh
lipc-set-prop com.lab126.powerd flIntensity 12   # 试一个中间值
lipc-set-prop com.lab126.powerd flIntensity 30   # 超范围会不会报错
```

没有背光的机型（Kindle 4 / 5）把 `touchd.sh` 里 `lipc-set-prop ... flIntensity` 那两行删掉即可，滑杆会变成纯装饰。

滑杆的映射是线性的：点最左 = 0（关），点最右 = `BRIGHT_MAX`。

---

## 5. 改显示内容

页面坐标是硬编码的绝对定位（`src/dashboard.html`，画布 768×1024）。想加减内容就改这个文件，然后 `python tools/build.py`。

几个常用位置：

| 元素 | id / 函数 | 位置 |
|---|---|---|
| 大时钟 | `#clock` | `top:92px`，字号自适应（宽度上限 340） |
| 温度 | `renderWeather()` | 温度 78px，天气图标 38px |
| 逐时曲线 | `drawChart()` | 取「现在起每 2 小时」共 8 点 |
| 未来 3 天 | `drawDays()` | 右下 `x 536~732` |
| 黄历宜忌 | `updateJieqi()` | 今日区块 |

改完在电脑上先看：

```bash
python tools/sample_data.py
# 浏览器打开 device/www/index.html（后面加 #memo 看留言页）
```
