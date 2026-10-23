#!/bin/sh
# touchd v4 - brightness slider (screen-space coords)
BASE=/mnt/us/frame
BB=/bin/busybox
LOG=$BASE/bright.log
HX=$BASE/tmp.hx
MAXB=${BRIGHT_MAX:-24}
echo "=== touchd start $(date) pid=$$ ===" >> $LOG
echo $$ > $BASE/touchd.pid
N=0
while true; do
  $BB dd if=/dev/input/event0 bs=16 count=32 2>/dev/null | $BB hexdump -Cv > $HX
  [ -s $HX ] || continue
  N=$((N+1))
  if [ $((N % 25)) -eq 1 ]; then
    echo "--- hex sample $N ---" >> $LOG
    $BB head -n 4 $HX >> $LOG
  fi
  $BB awk '
    function h1(c){ k=index("0123456789abcdef", c); return (k>0)?k-1:0 }
    function hb(s){ return h1(substr(s,1,1))*16 + h1(substr(s,2,1)) }
    function dc(a,b,c,d){ return hb(a) + hb(b)*256 + hb(c)*65536 + hb(d)*16777216 }
    NF>=17 {
      ty = $10+0;
      if (ty==3 && $12=="35") { X=dc($14,$15,$16,$17); hx=1 }
      else if (ty==3 && $12=="36") { Y=dc($14,$15,$16,$17); hy=1 }
      else if ($10=="00" && $12=="00") { if(hx==1 && hy==1) print X, Y; hx=0; hy=0 }
    }
  ' $HX | while read px py; do
    LASTF=$($BB cat $BASE/lastfrac 2>/dev/null)
    if [ "$py" -ge 770 ] && [ "$py" -le 880 ]; then
      f=$(( (px - 100) * 100 / 530 ))
      [ "$f" -lt 0 ] && f=0
      [ "$f" -gt 100 ] && f=100
      n=$(( (f * MAXB + 50) / 100 ))
      if [ "$f" != "$LASTF" ]; then
        lipc-set-prop com.lab126.powerd flIntensity "$n"
        echo "$f" > $BASE/bright
        echo "$f" > $BASE/lastfrac
        echo "$(date +%H:%M:%S) SLIDER x=$px y=$py f=$f n=$n rc=$?" >> $LOG
      fi
    else
      echo "$(date +%H:%M:%S) tap x=$px y=$py" >> $LOG
    fi
  done
done
