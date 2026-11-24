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

# Top 3 processes by CPU
echo -n '"top_procs": ['
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | awk '
NR>1 && NR<=4 {
  if (NR>2) printf ", "
  printf "{\"pid\": %s, \"name\": \"%s\", \"cpu\": %.1f, \"mem\": %.1f}", $1, $2, $3, $4
}
'
echo ']}'
