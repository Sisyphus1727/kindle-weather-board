# 排查手册

这里记的都是实机踩过的坑，按"现象 → 原因 → 怎么办"排。

---

## 现象：插上数据线后设备"死机"，屏幕上什么都不动

**不是死机，是 USBMS。** Kindle 插上数据线后会把存储区挂给电脑，整个系统（包括正在跑的脚本和浏览器）全部冻结。所有日志的时间都会停在插线那一刻。

**怎么办**：接受它。调试节奏只能是

```
拔线 → 等它跑一会儿 → 插线（此时系统冻结）→ 拷日志出来 → 拔线 → 重启
```

要看日志就在拔线前把关键信息写进 `/mnt/us/frame/*.log`，插线后一次性拷走。

---

## 现象：插拔一次之后，脚本行为变得很怪，日志里一堆 `Stale NFS file handle`

**原因**：`/mnt/us` 是 **`fuse.fsp`**（不是裸 vfat）。插拔一次 = 底层 inode 全换，**已经运行的进程持有的文件句柄全部失效**。于是 `[ -f /mnt/us/frame/cmd.sh ]` 恒假、`cat` 报错、重定向失败。

**怎么办**：**每次插拔后重启**。

```sh
reboot
```

不要指望在插拔之后再往 `cmd.sh` 里丢指令 —— 那个文件旧进程已经看不见了。

---

## 现象：想在 Kindle 上起个本地 Web 服务，怎么都起不来

**原因**：这台机器的 busybox **没有 `httpd`**，`nc` 是 BusyBox v1.17.1 的极简版：

```
Usage: nc [IPADDR PORT]
```

**没有 `-l` 监听参数**，只能当客户端。也没有 `lighttpd` / `python` / `java` 可用。

**怎么办**：换思路 —— 不启服务，页面直接 `file:///mnt/us/frame/www/index.html` 打开，数据靠 shell 写文件。

这也是为什么用 `<script src="data.js">` 而不是 `fetch()`：QtWebKit 打开 `file://` 时禁止 XHR 跨到远程 http，但同目录的 script 标签是允许的。

---

## 现象：浏览器不断弹「应用程序出错 / 无法启动选定的应用程序」

按可能性从高到低排：

**1. lipc 命令写法错了**

`lipc-set-prop` 不是 busybox applet，不能 `$BB lipc-set-prop`：

```sh
$BB lipc-set-prop ...      # ✗ applet not found
/usr/bin/lipc-set-prop ... # ✓ 直接调
```

**2. 开机太早就拉浏览器**

系统还没就绪、WiFi 还没连上就去 `app://com.lab126.browser/?view=...`，浏览器拿到一个还解析不了的地址，直接崩。

需要按顺序等：`/mnt/us` 挂载 → `lipc-get-prop com.lab126.appmgrd activeApp` 非空 → 再等 ~12 秒 → WiFi 起来（`ifconfig wlan0 | grep "inet addr:192"`）。

`frame.sh` 里的日志长这样才算正常：

```
system ready after 13x4s (active=[com.lab126.booklet.home])
wifi up after 0x2s
launch try=1 rc=0
browser OK (try=1)
```

**3. 改坏了 `config.xml` 或 `chrome.js`**

见下一条。用备份还原。

---

## 现象：改了 `/var/local/mesquite/browser/config.xml` 重启后又变回去了

**原因**：这个文件**每次开机由模板重新生成**，模板在 `/opt/var/local/mesquite/browser/config.xml`。改 `/var/local` 那份没有任何用。

**怎么办**：改模板。

```sh
mntroot rw
sed -i 's/viewmodes="application"/viewmodes="fullscreen"/' /opt/var/local/mesquite/browser/config.xml
cp /opt/var/local/mesquite/browser/config.xml /var/local/mesquite/browser/config.xml
mntroot ro
```

> 5.4.4.2 实测认 `fullscreen`。如果你的机型不认（开机就弹"应用程序出错"），把模板里的值改回 `application` 即可，只是会保留地址栏。

---

## 现象：想通过改 `chrome.js` 去掉外壳，改完应用起不来了

**原因**：`chrome.js` 里的 `pillow.configure(browserAppId, profileName)` **不能跳过**。跳过它，窗口/按键/标题栏全都没有初始化，应用直接拒绝启动。

如果确实要改，正确姿势是：

- 保留 `pillow.configure(...)`
- 把 `titleBar` / `progress` / `search` 这些调用**包在 try/catch 里**（去掉外观，但出错不崩）
- 改完**必须重启**，运行中的 mesquite 不会重新加载 JS

**更安全的做法是不改 JS**，只改 `config.xml` 的 `viewmodes`（见上一条），效果一样。

---

## 现象：判断浏览器"有没有起来"，脚本老是判错自动回滚

**原因**：网页应用的**进程名是 `mesquite`，不是 `browser`**。

```sh
ps w | grep -ci browser     # ✗ 永远是 0
ps w | grep -c mesquite     # ✓
lipc-get-prop com.lab126.appmgrd activeApp   # ✓ 更可靠
```

---

## 现象：每次调亮度，整页都重新加载 / 闪一下

**原因**：早期版本把电量、亮度也算进了"数据是否变化"的签名里，于是调一次背光就触发一次页面重载。而重载时会先以 1.0 倍画一帧再缩放到 0.961，看起来就是"闪一下变大"。

**当前版本已修**：

- 只在 天气/空气/留言 内容变化时才重新拉页面
- `#wrap` 默认 `visibility:hidden`，`fit()` 算好缩放后才显示
- 页面状态写进 URL hash（`#memo`），重载后不会跳回天气页

---

## 现象：背光滑杆只能点中间一段，左右两边没反应

**原因**：坐标系搞错了。页面里的滑杆在**逻辑坐标** `y 798~884`，而触摸面板报的是**屏幕像素**，两者差一个缩放（`sc=0.961`）和一个偏移（`dy=9`）：

```
屏幕 y = 逻辑 y × 0.961 + 9
```

逻辑 798~884 对应屏幕 **776~859**。

**当前版本已修**：`touchd.sh` 判定 `py 770~880`、`x 100~640`，留了余量。

---

## 现象：发了 `#clear` 之后，新推的消息也不显示

**原因**：ntfy 会把 `#clear` 这条消息保留 12 小时，每轮拉取都能看到它。如果把"清除时间点"记成"执行清除的时刻"，之后的新消息就全被判成过期。

**修法**（已在代码里）：

- 记录的是**那条 `#clear` 消息自带的时间戳**，而不是执行时刻
- 只有出现"更新的一条 `#clear`"才更新这个时间点
- `#clear` 消息本身不显示在留言页

---

## 现象：日志里每秒刷 `sleep: invalid number '0.3'`

busybox 的 `sleep` **只吃整数**。要等待请用 `sleep 1`，或用 `usleep`（如果没有，就别做亚秒轮询）。

顺带：`grep -E` 不支持，只有 `grep -i -v -q -r -F -e` 这些。

---

## 现象：逐时温度折线是空的

**原因**：`drawChart()` 需要「从当前整点开始、每 2 小时」的 8 个点，也就是需要 **24 小时的逐时数据**才凑得齐。只给 8 条数据只能凑出 4 个点，函数会直接 `return`，留下空白。

**怎么办**：确认 Open-Meteo 请求里带 `hourly=temperature_2m,precipitation_probability`，并且返回的 `hourly.time` 覆盖未来 24 小时（默认就是 7 天）。

---

## 现象：`未来 3 天` 全是同一天 / 显示 `周undefined`

- **全是同一天**：`daily.time` 的日期没有递增（伪造数据时最容易犯）
- **`周undefined`**：老 WebKit（QtWebKit 4.8）**不认** `new Date("2026-10-24T12:00:00")` 这种 ISO 字符串，`getDay()` 返回 `NaN`。必须手动拆：

  ```js
  var p = s.split("-");
  new Date(+p[0], +p[1]-1, +p[2], 12, 0, 0)
  ```

---

## 现象：图片推送到屏幕上，只显示「【图片】1 张」

这是设计如此 —— 电子墨水屏看图体验很差，所以图片只在留言列表里留一个占位提示，正文照常显示。图片本体不会被下载。

---

## 已经完全正常的日志长这样

```
=== frame.sh boot (pid 1737) mounted_after=0x2s ===
system ready after 13x4s (active=[com.lab126.booklet.home])
wifi up after 0x2s
first data built (bat=82 bright=53)
touchd launched
launch try=1 rc=0
browser OK (try=1)
msgs n=3
data changed -> touch reload
```

如果 `browser OK` 每隔十几秒就出现一次，说明有东西在让它不断重启 —— 查 `frame.log` 里触发重载的那一行（通常是数据一直在变，比如配置里 `PLACE_SUB` 每次都被重新生成、或温度取了随机值）。
