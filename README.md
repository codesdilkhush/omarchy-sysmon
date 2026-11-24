# System Monitor for Omarchy

Real-time CPU & GPU thermals, battery, memory, disk, and network monitoring status bar widget and popup panel for the Omarchy shell.

![System Monitor Preview](preview.png)

## Features

- Real-time CPU & GPU temperature tracking (°C)
- Battery charge status, percentage, and live power draw (W)
- Real-time CPU, GPU (Intel, AMD, NVIDIA), RAM, Swap, and root filesystem usage gauges
- Real-time Network bandwidth monitoring (download/upload transfer rates & totals)
- Native GPU telemetry: Intel RC6 residency & clock frequency, AMD DRM sysfs, and NVIDIA SMI
- Top CPU-consuming processes live view
- Dynamic system monitor launcher: automatically launches `btop`, `htop`, `bottom` (`btm`), or `top` based on what is available
- Clean status bar icon matching Omarchy bar styling
- Right-click status bar toggle for inline percentage

## Installation

```bash
omarchy plugin add https://github.com/codesdilkhush/omarchy-sysmon --enable
```

## Removal

```bash
omarchy plugin remove codesdilkhush.sysmon
```
