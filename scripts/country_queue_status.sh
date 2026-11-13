#!/usr/bin/env bash
# One-screen status of the 2026-10-10 Morocco/Egypt/Yemen/South Africa run
# (scripts/run_country_queue.sh). Read-only; generalised from scripts/vn_in_status.sh.
#
#   bash scripts/country_queue_status.sh
cd "$(dirname "$0")/.."

# Source macOS compatibility layer
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/macos_compat.sh"

Q=data/country_queue_markers
AOIS="morocco egypt yemen south_africa poland namibia turkiye"
now=$(date +%s)
echo "== $(date '+%F %T')  earthpv Morocco/Egypt/Yemen/South Africa status"

echo "-- units"
if [ "$OS_TYPE" = "linux" ]; then
  systemctl --user list-units --all --no-legend 'earthpv-*' 2>/dev/null \
    | awk '{printf "   %-40s %s/%s\n", $1, $3, $4}'
  for u in $(for a in $AOIS; do echo earthpv-compose-$a earthpv-$a-compute; done) earthpv-india-compute; do
    if systemctl --user is-active --quiet "$u"; then
      mem=$(systemctl --user show -p MemoryCurrent --value "$u" 2>/dev/null | awk '{printf "%.1fG", $1/1e9}')
      echo "   $u mem $mem"
    fi
  done
else
  # macOS: list active processes matching earthpv patterns
  echo "   (macOS: process-based status)"
  for u in $(for a in $AOIS; do echo earthpv-compose-$a earthpv-$a-compute; done) earthpv-india-compute; do
    if unit_active "$u"; then
      echo "   $u (active)"
    fi
  done
fi

echo "-- compose"
for a in $AOIS; do
  log=data/compose_$a.log
  got=$(find -L data/composites/$a/composites -name composite_0.tif 2>/dev/null | wc -l)
  sel=$(grep -aoE "Selected [0-9]+ cells" "$log" 2>/dev/null | tail -1 | grep -oE "[0-9]+")
  lbl=$(grep -aoE "[0-9]+ contain OSM solar labels" "$log" 2>/dev/null | tail -1 | grep -oE "^[0-9]+")
  # cells landed in the last 6 h, from file mtimes (a rate that cannot be fooled by logs)
  r6=$(find -L data/composites/$a/composites -name composite_0.tif -newermt "-6 hours" 2>/dev/null | wc -l)
  rate=$(awk -v n="$r6" 'BEGIN{printf "%.1f", n/6}')
  if [ -n "$sel" ] && [ "$r6" -gt 0 ]; then
    eta=$(awk -v s="$sel" -v g="$got" -v r="$rate" 'BEGIN{printf "%.1f d", (s-g)/r/24}')
  else eta="-"; fi
  echo "   $a: $got/${sel:-?} cells (label cells ${lbl:-?}), last 6 h: $r6 (${rate}/h), ETA $eta"
  echo "      done marker: $(cat $Q/${a}_compose_done 2>/dev/null || echo no)" \
       " | unproductive rounds: $(cat $Q/${a}_unproductive 2>/dev/null || echo 0)"
  hand=$(grep -ac "exceeded" "$log" 2>/dev/null); errs=$(grep -acE "ERROR|Traceback" "$log" 2>/dev/null)
  echo "      log: $(tail -c 300000 "$log" 2>/dev/null | grep -aoE '[0-9]+/[0-9]+ \[[^]]*\]' | tail -1)  PC hand-offs total $hand, errors total $errs"
done

echo "-- compute (markers)"
for a in $AOIS; do
  m=data/${a}_pipeline_markers
  echo "   $a: $(ls $m 2>/dev/null | tr '\n' ' ')"
  [ -f "results/${a}_checkpoint_decision.json" ] && \
    echo "      decision: $(python3 -c "import json;d=json.load(open('results/${a}_checkpoint_decision.json'));print(d['winner'],'|',d['reason'])")"
  tail -1 data/${a}_pipeline.log 2>/dev/null | sed 's/^/      last: /' | cut -c1-200
  [ -f "$Q/${a}_needs_attention" ] && echo "      !!! NEEDS ATTENTION"
done
[ -f data/.gpu.lock ] && echo "   gpu: $(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader 2>/dev/null)"

echo "-- inputs"
for i in MAR EGY YEM ZAF; do 
  if [ -s data/vida/$i.parquet ]; then
    echo "   $i VIDA: ready"
  else
    # Check for part file
    part_count=$(wc -l 2>/dev/null < /home/tobi/earthpv_data/$i.parquet.part.done || echo "0")
    echo "   $i VIDA: downloading ($part_count chunks)"
  fi
done

for a in $AOIS; do
  f=data/labels/${a}_overpass_solar.parquet
  if [ -s "$f" ]; then
    # Get file size cross-platform
    if [ "$OS_TYPE" = "linux" ]; then
      size=$(stat -c %s "$f" 2>/dev/null || echo "?")
    else
      size=$(stat_file_size "$f" 2>/dev/null || echo "?")
    fi
    echo "   $a labels: ready ($size B)"
  else
    tile_count=$(ls data/labels/.overpass_tiles/${a}_*/ 2>/dev/null | wc -l || echo "0")
    echo "   $a labels: pending ($tile_count tiles cached)"
  fi
done

echo "-- disk / memory / link"

# Disk usage - cross-platform
if [ "$OS_TYPE" = "linux" ]; then
  df -h / /run/media/tobi/aidisc 2>/dev/null | awk 'NR>1{printf "   %-28s %s free (%s used)\n", $6, $4, $5}'
else
  # macOS: check common paths
  df -h / 2>/dev/null | awk 'NR>1{printf "   %-28s %s free (%s used)\n", $9, $4, $5}'
  df -h /Volumes/aidisc 2>/dev/null | awk 'NR>1{printf "   %-28s %s free (%s used)\n", $9, $4, $5}'
  df -h /Volumes 2>/dev/null | awk 'NR>1{printf "   %-28s %s free (%s used)\n", $9, $4, $5}'
fi

# Memory usage - cross-platform
if [ "$OS_TYPE" = "linux" ]; then
  free -g | awk '/Mem/{printf "   RAM %sG used of %sG, available %sG\n", $3, $2, $7}'
  
  # Network monitoring - Linux specific
  IF=wlxb44bd62bd203
  if [ -d "/sys/class/net/$IF" ]; then
    r0=$(cat /sys/class/net/$IF/statistics/rx_bytes 2>/dev/null || echo 0)
    sleep 1
    r1=$(cat /sys/class/net/$IF/statistics/rx_bytes 2>/dev/null || echo 0)
    if [ "$r0" != "0" ] && [ "$r1" != "0" ]; then
      echo "   link rx now: $(( (r1 - r0) / 1000 )) kB/s"
    else
      echo "   link: network interface not found or inaccessible"
    fi
  else
    echo "   link: network interface $IF not found"
  fi
else
  # macOS memory
  if command -v vm_stat &>/dev/null; then
    # macOS: use vm_stat for memory info
    total_mem=$(sysctl hw.memsize 2>/dev/null | awk '{print $2 / 1e9}')
    used_mem=$(vm_stat 2>/dev/null | awk '/active/ {print $3}' | head -1)
    echo "   RAM: ${total_mem:-?}G total, macOS memory info available via vm_stat"
  else
    echo "   RAM: vm_stat not available"
  fi
  
  # macOS network
  if command -v networksetup &>/dev/null; then
    echo "   link: Use networksetup or ifconfig for network stats on macOS"
  else
    echo "   link: network tools not available"
  fi
fi

echo "-- queue log (last 10)"
tail -10 data/country_queue.log 2>/dev/null | sed 's/^/   /'
