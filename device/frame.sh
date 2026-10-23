#!/bin/sh
# Kindle 天气留言板 - frame daemon
# 目标: Kindle Paperwhite 1 / FW 5.4.4.2 (其他 5.x 机型基本通用)
# 教训:
#  1) 开机时 /mnt/us 可能还没挂载, 此时重定向日志会直接失败 -> 脚本静默死掉. 必须先等挂载.
#  2) 开机时 appmgrd 可能还没就绪, 太早启动浏览器会弹 "应用程序出错". 要等 system ready 再拉.
#  3) 浏览器进程名是 mesquite; 判断在前台用 lipc activeApp.
#  4) 通过 USB 改过文件后必须重启设备 (fuse 句柄失效).

BASE=/mnt/us/frame

# ---- 等待 /mnt/us 挂载 ----
i=0
while [ ! -d "$BASE" ] && [ $i -lt 90 ]; do
  sleep 2
  i=$((i+1))
done

[ -d "$BASE" ] || exit 1

W=$BASE/www
LOG=$BASE/frame.log
BB=/bin/busybox
URL="file:///mnt/us/frame/www/index.html"
mkdir -p "$W"
exec >>"$LOG" 2>&1

log(){ echo "[$(date '+%m-%d %H:%M:%S')] $*"; }

OLD=$(cat "$BASE/frame.pid" 2>/dev/null)
if [ -n "$OLD" ] && [ -d "/proc/$OLD" ] && grep -q "frame.sh" "/proc/$OLD/cmdline" 2>/dev/null; then
  log "already running pid=$OLD, exit"
  exit 0
fi
echo $$ > "$BASE/frame.pid"
log "=== frame.sh v11 boot (pid $$) mounted_after=${i}x2s ==="

# ---------------- 抓取 ----------------
fetch(){
  U=$1; F=$2
  if $BB wget -q -O "$F.tmp" "$U"; then
    [ -s "$F.tmp" ] && mv -f "$F.tmp" "$F" || rm -f "$F.tmp"
  else
    rm -f "$F.tmp"; log "wget fail $U"
  fi
}

# ---- 用户配置 ----
. "$BASE/config.sh"

FC_URL="http://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m&hourly=temperature_2m,precipitation_probability&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max&timezone=$TZ_ARG&forecast_days=4&wind_speed_unit=kmh"
AQ_URL="http://air-quality-api.open-meteo.com/v1/air-quality?latitude=$LAT&longitude=$LON&current=us_aqi,pm2_5&timezone=$TZ_ARG"
MS_URL="http://ntfy.sh/$TOPIC/json?poll=1&since="

get_weather(){ fetch "$FC_URL" "$BASE/weather.json"; }
get_air(){ fetch "$AQ_URL" "$BASE/air.json"; }
get_msgs(){
  SINCE=$(( $($BB date +%s) - 172800 ))
  fetch "$MS_URL$SINCE" "$BASE/msgs.ndjson"
  [ -s "$BASE/msgs.ndjson" ] || return 0
  CT=$($BB awk '/"message":"#clear/{ if (match($0, /"time":[0-9]+/)) { v=substr($0,RSTART+7,RLENGTH-7)+0; if (v>m) m=v } } END{ print m+0 }' "$BASE/msgs.ndjson")
  C=$($BB cat "$BASE/cleared" 2>/dev/null)
  [ -z "$C" ] && C=0
  if [ "$CT" -gt "$C" ]; then
    echo "$CT" > "$BASE/cleared"
    C=$CT
    log "CLEAR requested (msg t=$CT, keep newer)"
  fi
  NOWT=$($BB date +%s)
  CUT=$((NOWT - 172800))
  [ "$C" -gt "$CUT" ] && CUT=$C
  $BB awk -v cut="$CUT" 'NF{ if ($0 ~ /"message":"#clear/) next; if (match($0, /"time":[0-9]+/)) { v=substr($0,RSTART+7,RLENGTH-7)+0; if (v > cut) print } }' "$BASE/msgs.ndjson" > "$BASE/msgs.f"
  $BB tail -n 8 "$BASE/msgs.f" > "$BASE/msgs.n"
  mv -f "$BASE/msgs.n" "$BASE/msgs.ndjson"
  rm -f "$BASE/msgs.f"
  log "msgs n=$($BB wc -l < "$BASE/msgs.ndjson") cut=$CUT"
}

build_data(){
  BAT=$(lipc-get-prop com.lab126.powerd battLevel 2>/dev/null)
  BR=$(cat "$BASE/bright" 2>/dev/null)
  [ -z "$BR" ] && BR=40
  NOW=$($BB date +%s)
  OUT="$W/data.js.tmp"
  printf 'window.DATA={"ts":%s,"bat":"%s","bright":%s,"place":"%s","weather":' "$NOW" "$BAT" "$BR" "$PLACE_SUB" > "$OUT"
  if [ -s "$BASE/weather.json" ]; then cat "$BASE/weather.json" >> "$OUT"; else printf 'null' >> "$OUT"; fi
  printf ',"air":' >> "$OUT"
  if [ -s "$BASE/air.json" ]; then cat "$BASE/air.json" >> "$OUT"; else printf 'null' >> "$OUT"; fi
  printf ',"msgs":[' >> "$OUT"
  if [ -s "$BASE/msgs.ndjson" ]; then
    $BB awk 'NF{ if(n++) printf ","; printf "%s", $0 }' "$BASE/msgs.ndjson" >> "$OUT"
  fi
  printf ']}' >> "$OUT"
  TAIL=$($BB tail -c 2 "$OUT")
  if [ "$TAIL" = "]}" ]; then mv -f "$OUT" "$W/data.js"; else log "data.js bad tail [$TAIL]"; rm -f "$OUT"; fi
}

# ---------------- 触摸守护 ----------------
start_touchd(){
  if [ -f "$BASE/touchd.pid" ] && kill -0 "$(cat "$BASE/touchd.pid" 2>/dev/null)" 2>/dev/null; then
    return 0
  fi
  ( sh "$BASE/touchd.sh" & )
  log "touchd launched"
}

# ---------------- 浏览器 ----------------
browser_ok(){
  A=$(lipc-get-prop com.lab126.appmgrd activeApp 2>/dev/null)
  case "$A" in *lab126.browser*) return 0;; esac
  return 1
}
system_ready(){
  A=$(lipc-get-prop com.lab126.appmgrd activeApp 2>/dev/null)
  [ -n "$A" ]
}
start_browser(){
  n=0
  while [ $n -lt 4 ]; do
    n=$((n+1))
    lipc-set-prop com.lab126.appmgrd start "app://com.lab126.browser/?view=$URL"
    log "launch try=$n rc=$?"
    sleep 12
    if browser_ok; then log "browser OK (try=$n)"; return 0; fi
    log "browser not active after try=$n"
    sleep 8
  done
  return 1
}

# ---------------- 命令行通道 ----------------
run_cmd(){
  if [ -f "$BASE/cmd.sh" ]; then
    log "RUN cmd.sh"
    ( cd "$BASE"; sh "$BASE/cmd.sh" ) > "$BASE/cmd.out" 2>&1
    echo "--- exit=$? at $(date) ---" >> "$BASE/cmd.out"
    mv -f "$BASE/cmd.sh" "$BASE/cmd.last" 2>/dev/null
    log "cmd.sh done"
  fi
}

# ---------------- 等系统就绪 ----------------
n=0
while ! system_ready; do
  n=$((n+1))
  [ $n -gt 45 ] && break
  sleep 4
done
log "system ready after ${n}x4s (active=[$(lipc-get-prop com.lab126.appmgrd activeApp 2>/dev/null)])"
sleep 12

# ---------------- 等 WiFi ----------------
wait_wifi(){
  n=0
  while [ $n -lt 40 ]; do
    if ifconfig wlan0 2>/dev/null | grep -q "inet addr:192"; then
      log "wifi up after ${n}x2s"
      return 0
    fi
    n=$((n+1))
    sleep 2
  done
  log "wifi timeout after ${n}x2s"
  return 1
}
wait_wifi

# ---------------- 主流程 ----------------
lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1

get_weather; get_air; get_msgs
build_data
log "first data built (bat=$BAT bright=$BR)"

start_touchd
start_browser

LAUNCH_AT=$($BB date +%s)
LASTW=0
LASTM=0
LASTSIG=""
N=0
while true; do
  run_cmd
  lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1
  NOW=$($BB date +%s)
  if [ $((NOW - LASTM)) -ge $REFRESH_WEATHER ]; then
    get_weather; get_air; LASTM=$NOW
  fi
  if [ $((NOW - LASTW)) -ge $REFRESH_MSGS ]; then
    get_msgs; LASTW=$NOW
  fi
  build_data
  if [ -f "$BASE/reload" ]; then
    rm -f "$BASE/reload"; start_browser; LAUNCH_AT=$NOW
  fi
  if [ $((NOW - LAUNCH_AT)) -ge 600 ]; then
    if browser_ok; then log "browser alive"; else log "browser gone -> relaunch"; start_browser; fi
    LAUNCH_AT=$NOW
  fi
  start_touchd
  N=$((N+1))
  [ $((N % 15)) -eq 0 ] && log "alive n=$N"
  sleep 20
done
