# Kindle Weather & Memo Board

[中文说明](README.md) · **English**

Turn an idle Kindle e-ink reader into an **always-on weather display with a family memo board**. During the day it sits on a desk showing the weather; anyone in the house can scan a QR code and push text messages onto the screen from their phone.

Everything runs **on the Kindle itself** — no always-on PC, no Raspberry Pi, no server.

![Weather page](docs/images/page-weather.png)

![Memo page](docs/images/page-memo.png)

## What it shows

**Page 1 · Weather**
- Large clock, date / weekday / place name
- Moon phase disc, vertical lunar date, sexagenary day
- Current temperature, weather icon, feels-like, today's high/low
- 24-hour temperature curve (one point every 2 hours) + precipitation bars
- Humidity / wind / sunset / air quality / rain probability
- Chinese almanac ("dos and don'ts"), days until New Year and Spring Festival, 3-day forecast
- Year progress bar split into 12 months, with sub-progress for the current month

**Page 2 · Memo** (tap the screen to switch)
- Text / image notifications pushed from a phone, latest 8, newest on top
- QR code — scan it to open the push page on your phone
- Front-light slider at the bottom: 0 (off) to 100%

## Features

- **No external dependencies**: weather from Open-Meteo (no API key), push via the public ntfy.sh instance — both over plain HTTP
- **Fully local rendering**: the page and the 417 KB lunar library are inlined into a single HTML file, opened via `file://`, no local web server required
- **20-second push latency**: memos are polled every 20 s; the page updates in place — no flicker, no page jumps
- **Real fullscreen**: browser chrome (address bar, toolbar) removed, so it looks like a native app
- **Hardware backlight control**: the slider calls `lipc-set-prop` directly, it dims the panel light, not the pixels
- **Reversible**: back up the device first, restore whenever you want

## How it works

```
┌─────────────┐   HTTP (wget)   ┌──────────────┐
│ Open-Meteo  │◄────────────────│              │
│  ntfy.sh    │                 │   frame.sh   │  every 20 s:
└─────────────┘                 │  (on-device) │  fetch → write www/data.js
                                └──────┬───────┘
                                       │ write file
                                ┌──────▼───────┐
                                │ www/data.js  │
                                └──────┬───────┘
                                       │ <script src="data.js">
                                ┌──────▼───────┐
                                │  index.html  │  re-reads it every 20 s,
                                │ (QtWebKit)   │  repaints only what changed
                                └──────┬───────┘
                                       │
                                ┌──────▼───────┐
                                │ touchd.sh    │  reads /dev/input/event0
                                │              │  → backlight via lipc
                                └──────────────┘
```

Why a browser + local files, and not something fancier:

- A jailbroken Kindle gives you a **QtWebKit 4.8 browser** and a stripped-down busybox. There is **no `httpd`, no `nc -l`, no python** — you simply cannot run a local web server on it
- When QtWebKit opens a `file://` page it **blocks XHR to remote http** endpoints, so the page cannot fetch the APIs itself
- But a `<script src="data.js">` from the same directory *is* allowed — so a shell script wraps the JSON as `window.DATA = {...}` into `data.js`, and the page re-inserts that `<script>` every 20 seconds to swap data in place without reloading

## Quick start

Full steps in **[docs/INSTALL.md](docs/INSTALL.md)** (Chinese), configuration in **[docs/CONFIG.md](docs/CONFIG.md)**, pitfalls in **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**.

Short version:

```bash
# 1. edit the only config file (location + push topic)
vi device/config.sh

# 2. build the page (inlines the lunar library, renders the QR code)
python -m pip install qrcode pillow
python tools/build.py

# 3. copy 4 files to the Kindle
#    device/config.sh      -> /mnt/us/frame/config.sh
#    device/frame.sh       -> /mnt/us/frame/frame.sh
#    device/touchd.sh      -> /mnt/us/frame/touchd.sh
#    device/www/index.html -> /mnt/us/frame/www/index.html

# 4. install the boot script (jailbreak required)
mntroot rw
cp device/S99frame /etc/rcS.d/S99frame
chmod +x /etc/rcS.d/S99frame
mntroot ro

# 5. unplug and reboot
```

Want to preview it on your computer first (no Kindle needed):

```bash
python tools/sample_data.py
# then open device/www/index.html in a browser
```

## Repo layout

```
device/
  config.sh          the only file you need to edit (location / topic / intervals / backlight steps)
  frame.sh           on-device daemon: fetch data, build data.js, watchdog, relaunch page
  touchd.sh          touch daemon: read event0 → set backlight
  S99frame           boot script
  www/index.html     build output (this is what goes to the device)
src/
  dashboard.html     page source (with __LUNAR__ / __QR__ / __TOPIC__ placeholders)
tools/
  build.py           build: inline lunar.js + render QR → device/www/index.html
  sample_data.py     generate fake data for local preview
  vendor/lunar.js    lunar-javascript 1.6.12
docs/
  INSTALL.md         deployment (including jailbreaking)
  CONFIG.md          location / push topic / refresh intervals
  TROUBLESHOOTING.md known pitfalls
.github/workflows/
  build.yml          rebuilds index.html on push and commits it back
```

## Model compatibility

Fully tested on a **Kindle Paperwhite 1 (2012, firmware 5.4.4.2)**.

Other 5.x devices (PW2 / Kindle Touch / K5) should work with three adjustments:

| What to check | How |
|---|---|
| Screen resolution | `cat /sys/class/graphics/fb0/virtual_size`, then change the 768×1024 absolute coordinates in `src/dashboard.html` |
| Backlight step count | try `lipc-set-prop com.lab126.powerd flIntensity <N>`, set `BRIGHT_MAX` in `config.sh` |
| Fullscreen config | check whether `/opt/var/local/mesquite/browser/config.xml` exists (PW1 has it) |

On devices without a front light (K4/K5), remove the `lipc-set-prop` backlight calls from `touchd.sh`.

## Known limitations

- **Plugging in USB freezes the device.** USB mass-storage mode suspends the whole system, so debugging is: unplug → let it run → plug in (system frozen) → pull logs → unplug → reboot
- **Reboot after every plug/unplug.** `/mnt/us` is `fuse.fsp`; after one re-mount every open file handle in running processes goes stale
- It **needs network** for weather (the almanac is computed offline, the forecast is not). Without WiFi it keeps showing the last known data
- Charts are redrawn with e-ink refreshes, so there is mild ghosting after many updates

## Credits

- [Open-Meteo](https://open-meteo.com/) — key-free weather / air-quality API that also speaks plain HTTP
- [ntfy.sh](https://ntfy.sh/) — registration-free push service with phone apps and a web composer
- [lunar-javascript](https://github.com/6tail/lunar-javascript) (MIT) — lunar calendar, solar terms, almanac
- [kylemccreery/kindle-dash](https://github.com/kylemccreery/kindle-dash) — kiosk setup on the same PW1 hardware, where the fullscreen trick comes from
- [kindlemodding.org](https://kindlemodding.org/) — jailbreak instructions

## License

MIT, see [LICENSE](LICENSE).
