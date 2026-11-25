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

# Load average, physical cores, and logical threads
read -r l1 l5 l15 _ < /proc/loadavg
threads=$(nproc)
cores=$(awk -F: '
/^core id/ { cores[$2] = 1 }
/^physical id/ { pkgs[$2] = 1 }
END {
  c = length(cores); p = length(pkgs)
  print (c > 0 && p > 0) ? (c * p) : (c > 0 ? c : 0)
}
' /proc/cpuinfo 2>/dev/null || echo 0)
if (( cores <= 0 )); then
  cores=$threads
fi
printf '"load_1": %.2f, "load_5": %.2f, "load_15": %.2f, "cores": %d, "threads": %d, ' "$l1" "$l5" "$l15" "$cores" "$threads"

# CPU temperature (°C)
cpu_temp=0
for h in /sys/class/hwmon/hwmon*; do
  name=$(cat "$h/name" 2>/dev/null || true)
  if [[ "$name" =~ ^(coretemp|k10temp|zenpower|cpu_thermal)$ ]]; then
    for t in "$h"/temp*_input; do
      if [[ -r "$t" ]]; then
        raw=$(cat "$t" 2>/dev/null || echo 0)
        if (( raw > 0 )); then
          cpu_temp=$(( (raw + 500) / 1000 ))
          break 2
        fi
      fi
    done
  fi
done

if (( cpu_temp == 0 )); then
  for z in /sys/class/thermal/thermal_zone*; do
    ztype=$(cat "$z/type" 2>/dev/null || true)
    if [[ "$ztype" =~ (x86_pkg_temp|TCPU|cpu) ]]; then
      raw=$(cat "$z/temp" 2>/dev/null || echo 0)
      if (( raw > 0 )); then
        cpu_temp=$(( (raw + 500) / 1000 ))
        break
      fi
    fi
  done
fi
printf '"cpu_temp": %d, ' "$cpu_temp"

# Disk /
df -h / | awk 'NR==2 { gsub(/%/, "", $5); printf "\"disk_used\": \"%s\", \"disk_total\": \"%s\", \"disk_pct\": %d, ", $3, $2, $5 }'

# GPU stats (native sysfs, proc, lspci)
gpu_name=""
gpu_pct=0
gpu_clock=""
gpu_temp=0
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

# Apple Silicon (Asahi): agx_stats exposes cumulative busy_ns, power and pstate.
# Panel.qml turns busy_ns deltas into a percentage; power is shown as the "clock".
gpu_busy_ns=0
for f in /sys/class/drm/card*/device/agx_stats; do
  if [[ -r "$f" ]]; then
    gpu_busy_ns=$(awk '$1=="busy_ns" { print $2 }' "$f" 2>/dev/null || echo 0)
    gpu_busy_ns=${gpu_busy_ns:-0}
    agx_power_mw=$(awk '$1=="power_mw" { print $2 }' "$f" 2>/dev/null || echo 0)
    if [[ -n "${agx_power_mw:-}" ]] && (( agx_power_mw > 0 )); then
      gpu_clock=$(awk "BEGIN { printf \"%.1fW\", $agx_power_mw / 1000.0 }")
    fi
    apple_model=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)
    if [[ "$apple_model" =~ \((M[0-9][A-Za-z]*) ]]; then
      gpu_name="Apple ${BASH_REMATCH[1]} GPU"
    else
      gpu_name="Apple GPU"
    fi
    break
  fi
done

for f in /sys/class/drm/card*/device/gpu_busy_percent; do
  if [[ -r "$f" ]]; then
    gpu_pct=$(cat "$f" 2>/dev/null || echo 0)
    break
  fi
done

for t in /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input; do
  if [[ -r "$t" ]]; then
    raw=$(cat "$t" 2>/dev/null || echo 0)
    if (( raw > 0 )); then
      gpu_temp=$(( (raw + 500) / 1000 ))
      break
    fi
  fi
done

if command -v nvidia-smi &>/dev/null; then
  nv_out=$(nvidia-smi --query-gpu=name,utilization.gpu,clocks.current.graphics,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || true)
  if [[ -n "$nv_out" ]]; then
    IFS=',' read -r g_name g_util g_clk g_temp <<< "$nv_out"
    gpu_name="$(echo "$g_name" | xargs)"
    gpu_pct="$(echo "$g_util" | xargs)"
    gpu_clock="$(echo "$g_clk" | xargs)MHz"
    if [[ -n "$g_temp" ]] && [[ "$g_temp" =~ ^[0-9]+$ ]]; then
      gpu_temp="$(echo "$g_temp" | xargs)"
    fi
  fi
fi

# Fallback for integrated GPU on the same silicon package as CPU
if (( gpu_temp == 0 )) && (( cpu_temp > 0 )); then
  if [[ "$gpu_name" =~ (Intel|Iris|UHD|Radeon|Vega|APU) ]]; then
    gpu_temp="$cpu_temp"
  fi
fi

# Clean strings for JSON
gpu_name="${gpu_name//\"/}"
gpu_clock="${gpu_clock//\"/}"
printf '"gpu_name": "%s", "gpu_pct": %d, "gpu_clock": "%s", "gpu_temp": %d, "gpu_rc6_ms": %s, "gpu_busy_ns": %s, "gpu_timestamp_ms": %s, ' \
  "$gpu_name" "$gpu_pct" "$gpu_clock" "$gpu_temp" "${gpu_rc6:-0}" "${gpu_busy_ns:-0}" "$now_ms"

# Network stats
net_iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}' || true)
if [[ -z "$net_iface" ]]; then
  net_iface=$(awk 'NR>2 && $1 !~ /^lo:/ { sub(/:/, "", $1); print $1; exit }' /proc/net/dev || true)
fi

read -r net_rx net_tx < <(awk '
NR > 2 && $1 !~ /^lo:/ {
  rx += $2
  tx += $10
}
END {
  print (rx ? rx : 0), (tx ? tx : 0)
}
' /proc/net/dev)

printf '"net_iface": "%s", "net_rx_bytes": %d, "net_tx_bytes": %d, ' "${net_iface:-}" "${net_rx:-0}" "${net_tx:-0}"

# Battery stats
has_battery="false"
battery_pct=0
battery_status=""
battery_power_w="0.0"

# Match any supply of type Battery (BAT0, macsmc-battery on Apple Silicon, ...).
for b in /sys/class/power_supply/*; do
  if [[ -d "$b" ]] && [[ "$(cat "$b/type" 2>/dev/null || true)" == "Battery" ]] \
     && [[ "$(cat "$b/present" 2>/dev/null || echo 1)" == "1" ]]; then
    has_battery="true"
    battery_pct=$(cat "$b/capacity" 2>/dev/null || echo 0)
    battery_status=$(cat "$b/status" 2>/dev/null || echo "Unknown")
    
    if [[ -r "$b/power_now" ]]; then
      p_raw=$(cat "$b/power_now" 2>/dev/null || echo 0)
      battery_power_w=$(awk "BEGIN { printf \"%.1f\", $p_raw / 1000000.0 }")
    elif [[ -r "$b/current_now" ]] && [[ -r "$b/voltage_now" ]]; then
      c_raw=$(cat "$b/current_now" 2>/dev/null || echo 0)
      v_raw=$(cat "$b/voltage_now" 2>/dev/null || echo 0)
      battery_power_w=$(awk "BEGIN { printf \"%.1f\", ($c_raw * $v_raw) / 1000000000000.0 }")
    fi
    break
  fi
done

printf '"has_battery": %s, "battery_pct": %d, "battery_status": "%s", "battery_power_w": %s, ' \
  "$has_battery" "$battery_pct" "$battery_status" "$battery_power_w"

# Firewall status (unprivileged query)
fw_name="None"
fw_active=false

if systemctl is-active --quiet ufw 2>/dev/null; then
  fw_name="UFW"
  fw_active=true
elif systemctl is-active --quiet firewalld 2>/dev/null; then
  fw_name="firewalld"
  fw_active=true
elif systemctl is-active --quiet nftables 2>/dev/null; then
  fw_name="nftables"
  fw_active=true
elif systemctl is-active --quiet iptables 2>/dev/null; then
  fw_name="iptables"
  fw_active=true
elif [[ -f /etc/ufw/ufw.conf ]] && grep -q '^ENABLED=yes' /etc/ufw/ufw.conf 2>/dev/null; then
  fw_name="UFW"
  fw_active=true
fi

printf '"fw_name": "%s", "fw_active": %s, ' "$fw_name" "$fw_active"

# Network sockets stats and active network applications (unprivileged)
conn_in=0
conn_out=0
listen_count=0
net_procs_json="[]"

if command -v ss &>/dev/null; then
  listen_ports=$(ss -H -t -u -l -n 2>/dev/null | awk '{print $4}' | awk -F: '{print $NF}' | sort -u || true)
  listen_count=$(echo "$listen_ports" | grep -c . || echo 0)

  eval "$(ss -H -t -u -p -n state established 2>/dev/null | awk -v lp="${listen_ports:-}" '
  function friendly_name(pname) {
    if (pname == "agy") return "Antigravity"
    if (pname == "chromium" || pname == "chrome" || pname == "google-chrome") return "Google Chrome"
    if (pname == "firefox") return "Firefox"
    if (pname == "spotify") return "Spotify"
    if (pname == "discord" || pname == "Discord") return "Discord"
    if (pname == "slack") return "Slack"
    if (pname == "telegram-desktop") return "Telegram"
    if (pname == "code" || pname == "codium") return "VS Code"
    if (pname == "zed") return "Zed"
    if (pname == "steam") return "Steam"
    if (pname == "foot") return "Terminal"
    if (pname == "alacritty" || pname == "kitty") return "Terminal"
    if (pname == "superwhisper" || pname == "superwhisper-in" || pname == "asr-worker") return "Superwhisper"
    if (pname == "quickshell") return "Omarchy Shell"
    if (pname == "omadoc") return "Omarchy Docs"
    if (pname == "pipewire" || pname == "pipewire-pulse") return "PipeWire"
    if (pname == "wireplumber") return "WirePlumber"
    if (pname == "systemd-resolved" || pname == "NetworkManager") return "NetworkManager"
    if (pname == "system" || pname == "systemd-oomd") return "System Services"
    return toupper(substr(pname, 1, 1)) substr(pname, 2)
  }
  BEGIN {
    split(lp, ports, RS)
    for (i in ports) if (ports[i] != "") is_listen[ports[i]] = 1
    cin = 0
    cout = 0
  }
  NF >= 4 {
    n = split($4, a, ":")
    local_port = a[n]
    is_in = (local_port in is_listen)
    if (is_in) cin++; else cout++

    pname = ""
    for (i=5; i<=NF; i++) {
      if ($i ~ /users:\(\(/) {
        match($i, /users:\(\("([^"]+)"/, m)
        if (m[1] != "") pname = m[1]
        break
      }
    }
    if (pname != "") {
      fn = friendly_name(pname)
      comm_map[fn] = pname
      tot[fn]++
      if (is_in) in_cnt[fn]++; else out_cnt[fn]++
    }
  }
  END {
    procs = ""
    for (fn in tot) {
      item = sprintf("{\\\"name\\\": \\\"%s\\\", \\\"comm\\\": \\\"%s\\\", \\\"conns\\\": %d, \\\"out\\\": %d, \\\"in\\\": %d}", fn, comm_map[fn], tot[fn], out_cnt[fn], in_cnt[fn])
      procs = (procs == "" ? item : procs ", " item)
    }
    printf "conn_in=%d\nconn_out=%d\nnet_procs_json=\"[%s]\"\n", cin, cout, procs
  }')"
fi

printf '"conn_inbound": %d, "conn_outbound": %d, "conn_total": %d, "listen_count": %d, "net_procs": %s, ' \
  "${conn_in:-0}" "${conn_out:-0}" "$(( ${conn_in:-0} + ${conn_out:-0} ))" "${listen_count:-0}" "${net_procs_json:-[]}"

# Detect installed/available top tools dynamically
available_tops=()
for cmd in btop htop btm top; do
  if command -v "$cmd" &>/dev/null; then
    available_tops+=("\"$cmd\"")
  fi
done
tops_json=$(IFS=, ; echo "[${available_tops[*]}]")
printf '"available_tops": %s, ' "$tops_json"

# Processes: top 3 and all active processes (up to 50 non-kernel processes)
ps -eo pid,ppid,user,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | awk '
function friendly_name(pname) {
  if (pname == "agy") return "Antigravity"
  if (pname == "chromium" || pname == "chrome" || pname == "google-chrome") return "Google Chrome"
  if (pname == "firefox") return "Firefox"
  if (pname == "spotify") return "Spotify"
  if (pname == "discord" || pname == "Discord") return "Discord"
  if (pname == "slack") return "Slack"
  if (pname == "telegram-desktop") return "Telegram"
  if (pname == "code" || pname == "codium") return "VS Code"
  if (pname == "zed") return "Zed"
  if (pname == "steam") return "Steam"
  if (pname == "foot") return "Terminal"
  if (pname == "alacritty" || pname == "kitty") return "Terminal"
  if (pname == "superwhisper" || pname == "superwhisper-in" || pname == "asr-worker") return "Superwhisper"
  if (pname == "quickshell") return "Omarchy Shell"
  if (pname == "omadoc") return "Omarchy Docs"
  if (pname == "pipewire" || pname == "pipewire-pulse") return "PipeWire"
  if (pname == "wireplumber") return "WirePlumber"
  if (pname == "systemd-resolved" || pname == "NetworkManager") return "NetworkManager"
  if (pname == "system" || pname == "systemd-oomd") return "System Services"
  return toupper(substr(pname, 1, 1)) substr(pname, 2)
}
BEGIN {
  top_str = ""
  all_str = ""
  count = 0
}
NR > 1 {
  pid = $1
  ppid = $2
  user = $3
  comm = $4
  cpu = $5
  mem = $6

  # Filter kernel threads
  if (ppid == 2 || pid == 2) next

  fname = friendly_name(comm)
  count++

  item = sprintf("{\"pid\": %s, \"user\": \"%s\", \"comm\": \"%s\", \"name\": \"%s\", \"cpu\": %.1f, \"mem\": %.1f}", pid, user, comm, fname, cpu, mem)
  if (count <= 3) {
    top_str = (top_str == "" ? item : top_str ", " item)
  }
  if (count <= 50) {
    all_str = (all_str == "" ? item : all_str ", " item)
  }
}
END {
  printf "\"top_procs\": [%s], \"all_procs\": [%s]}\n", top_str, all_str
}
'
