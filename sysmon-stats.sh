#!/bin/bash
set -euo pipefail

# CPU stats (idle & total jiffies)
awk '
NR==1 {
  idle = $5
  total = 0
  for (i=2; i<=NF; i++) total += $i
  printf "{\"cpu_idle\": %d, \"cpu_total\": %d, ", idle, total
}
' /proc/stat

# Memory and Swap
awk '
/^MemTotal:/ { total = $2 }
/^MemAvailable:/ { avail = $2 }
/^SwapTotal:/ { stotal = $2 }
/^SwapFree:/ { sfree = $2 }
END {
  used = total - avail
  sused = stotal - sfree
  printf "\"mem_used_mb\": %d, \"mem_total_mb\": %d, \"mem_pct\": %.1f, ", used/1024, total/1024, (used/total)*100
  if (stotal > 0) {
    printf "\"swap_used_mb\": %d, \"swap_total_mb\": %d, \"swap_pct\": %.1f, ", sused/1024, stotal/1024, (sused/stotal)*100
  } else {
    printf "\"swap_used_mb\": 0, \"swap_total_mb\": 0, \"swap_pct\": 0.0, "
  }
}
' /proc/meminfo

# Load average and cores
read -r l1 l5 l15 _ < /proc/loadavg
cores=$(nproc)
printf '"load_1": %.2f, "load_5": %.2f, "load_15": %.2f, "cores": %d, ' "$l1" "$l5" "$l15" "$cores"

# Disk /
df -h / | awk 'NR==2 { gsub(/%/, "", $5); printf "\"disk_used\": \"%s\", \"disk_total\": \"%s\", \"disk_pct\": %d, ", $3, $2, $5 }'

# GPU stats (native sysfs, proc, lspci)
gpu_name=""
gpu_pct=0
gpu_clock=""
gpu_rc6=0
now_ms=$(date +%s%3N)

gpu_name=$(lspci -d ::0300 2>/dev/null | sed -E 's/.*: //; s/ \[....:....\]//; s/ \(rev .*\)//' | head -1)
if [[ -z "$gpu_name" ]]; then
  gpu_name="GPU"
fi

for f in /sys/class/drm/card*/gt/gt0/rc6_residency_ms /sys/class/drm/card*/gt_rc6_residency_ms; do
  if [[ -r "$f" ]]; then
    gpu_rc6=$(cat "$f" 2>/dev/null || echo 0)
    break
  fi
done

for f in /sys/class/drm/card*/gt_act_freq_mhz /sys/class/drm/card*/gt/gt0/rps_act_freq_mhz; do
  if [[ -r "$f" ]]; then
    clk=$(cat "$f" 2>/dev/null || echo 0)
    if [[ -n "$clk" ]] && (( clk > 0 )); then
      gpu_clock="${clk}MHz"
      break
    fi
  fi
done

if [[ -z "$gpu_clock" ]]; then
  for f in /sys/class/drm/card*/gt_cur_freq_mhz /sys/class/drm/card*/gt/gt0/rps_cur_freq_mhz; do
    if [[ -r "$f" ]]; then
      clk=$(cat "$f" 2>/dev/null || echo 0)
      if [[ -n "$clk" ]] && (( clk > 0 )); then
        gpu_clock="${clk}MHz"
        break
      fi
    fi
  done
fi

for f in /sys/class/drm/card*/device/gpu_busy_percent; do
  if [[ -r "$f" ]]; then
    gpu_pct=$(cat "$f" 2>/dev/null || echo 0)
    break
  fi
done

if command -v nvidia-smi &>/dev/null; then
  nv_out=$(nvidia-smi --query-gpu=name,utilization.gpu,clocks.current.graphics --format=csv,noheader,nounits 2>/dev/null | head -1 || true)
  if [[ -n "$nv_out" ]]; then
    IFS=',' read -r g_name g_util g_clk <<< "$nv_out"
    gpu_name="$(echo "$g_name" | xargs)"
    gpu_pct="$(echo "$g_util" | xargs)"
    gpu_clock="$(echo "$g_clk" | xargs)MHz"
  fi
fi

# Clean strings for JSON
gpu_name="${gpu_name//\"/}"
gpu_clock="${gpu_clock//\"/}"
printf '"gpu_name": "%s", "gpu_pct": %d, "gpu_clock": "%s", "gpu_rc6_ms": %s, "gpu_timestamp_ms": %s, ' \
  "$gpu_name" "$gpu_pct" "$gpu_clock" "${gpu_rc6:-0}" "$now_ms"

# Detect installed/available top tools dynamically
available_tops=()
for cmd in btop htop btm top; do
  if command -v "$cmd" &>/dev/null; then
    available_tops+=("\"$cmd\"")
  fi
done
tops_json=$(IFS=, ; echo "[${available_tops[*]}]")
printf '"available_tops": %s, ' "$tops_json"

# Top 3 processes by CPU
echo -n '"top_procs": ['
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | awk '
NR>1 && NR<=4 {
  if (NR>2) printf ", "
  printf "{\"pid\": %s, \"name\": \"%s\", \"cpu\": %.1f, \"mem\": %.1f}", $1, $2, $3, $4
}
'
echo ']}'
