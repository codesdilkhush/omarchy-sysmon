# System Monitor for Omarchy

Real-time CPU & GPU thermals, battery, memory, disk, process manager, and network monitor for the Omarchy status bar and popup panel.

![System Monitor Preview](preview.png)

## Features

- **Bar Pill & Live Alerts** — Compact CPU icon in the bar with an optional inline CPU percentage (`Right-click` to toggle), color-highlighted when CPU or GPU usage reaches 85%+, and a rich multi-line hover tooltip.
- **Overview Tab** — Live gauges and readings for CPU load/cores/threads/temperature (°C), GPU utilization/clock/temperature (Intel RC6 + frequency, AMD DRM sysfs, and NVIDIA via `nvidia-smi`), RAM & Swap usage, root filesystem (`/`) usage, and battery percentage/status/wattage (`W`).
- **Processes Tab** — Live top-50 user processes sortable by CPU% or Memory%, instant search filter, and inline Terminate (`SIGTERM`) / Force Kill (`SIGKILL`) actions.
- **Network Tab** — Active interface live download/upload rates and session totals, inbound/outbound/listening socket counts, firewall status (`UFW`, `firewalld`, `nftables`, `iptables`), and per-application connection breakdown.
- **TUI Monitor Launcher** — Detects installed terminal monitors (`btop`, `htop`, `btm`, `top`) and launches or focuses your preferred monitor with one click or middle-click.

## Requirements

- Omarchy 4 (Quattro) or later (`omarchy-shell`)
- Standard Linux utilities included with Omarchy (`bash`, `awk`, `df`, `lspci`, `ip`, `ss`, `ps`, `systemctl`)
- Optional: `nvidia-smi` for NVIDIA GPU metrics; `btop`, `htop`, `btm`, or `top` for launching an external TUI monitor

## Install

```bash
omarchy plugin add https://github.com/codesdilkhush/omarchy-sysmon --enable
```

To move the widget to another bar section:

```bash
omarchy bar move codesdilkhush.sysmon --section center
```

## Uninstall

```bash
omarchy plugin remove codesdilkhush.sysmon
```

## Controls & IPC

| Action | Mouse | IPC Command |
|---|---|---|
| Open / close popup | Left click bar icon | `omarchy-shell codesdilkhush.sysmon toggle` |
| Toggle inline CPU % in bar | Right click bar icon | `omarchy-shell codesdilkhush.sysmon togglePercentage` |
| Launch preferred TUI monitor | Middle click bar icon | `omarchy-shell codesdilkhush.sysmon openSystemMonitor` |
| Switch tab (`0` Overview, `1` Processes, `2` Network) | Click tab header | `omarchy-shell codesdilkhush.sysmon setTab 0` |
| Sort processes (`cpu` / `mem`) | Click column button | `omarchy-shell codesdilkhush.sysmon sortProcesses cpu` |
| Close popup | Click outside / `Esc` | `omarchy-shell codesdilkhush.sysmon close` |

Optional Hyprland keybinding in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + M", "System Monitor", "omarchy-shell codesdilkhush.sysmon toggle")
```

## Privacy & Local Behavior

- All telemetry is collected locally via unprivileged reads in [sysmon-stats.sh](sysmon-stats.sh) (`/proc`, `/sys`, `ss`, `ps`, `df`, `lspci`, and `systemctl is-active`); no network requests are made and no external telemetry is sent.
- Polls every 1s while the popup is open and every 2s when closed so the bar indicator and tooltip stay current.
- Inline bar percentage (`showPercentage`) and default TUI monitor (`defaultTop`) preferences are stored in your existing `~/.config/omarchy/shell.json` widget entry.

## License

[MIT](LICENSE)
