#!/usr/bin/env python3
"""Collect AMD GPU metrics into the node_exporter textfile collector.

Reads amdgpu sysfs (gpu_busy_percent, mem_info_vram_*, hwmon sensors) and
writes Prometheus text format to
/var/lib/node_exporter/textfile_collector/amdgpu.prom. Invoked every 15s by
gpu-metrics.timer. Every read is individually guarded, so a missing file
(kernel/driver differences) simply omits that metric instead of failing.
"""
import glob
import os
import re

TEXTFILE_DIR = "/var/lib/node_exporter/textfile_collector"
OUT_PATH = os.path.join(TEXTFILE_DIR, "amdgpu.prom")

HEADER = [
    "# HELP amdgpu_gpu_utilization_percent GPU engine utilization (percent).",
    "# TYPE amdgpu_gpu_utilization_percent gauge",
    "# HELP amdgpu_memory_used_bytes VRAM used (bytes).",
    "# TYPE amdgpu_memory_used_bytes gauge",
    "# HELP amdgpu_memory_total_bytes VRAM total (bytes).",
    "# TYPE amdgpu_memory_total_bytes gauge",
    "# HELP amdgpu_temperature_c GPU temperature (celsius).",
    "# TYPE amdgpu_temperature_c gauge",
    "# HELP amdgpu_power_watts GPU power draw (watts).",
    "# TYPE amdgpu_power_watts gauge",
]


def read_int(path):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


def hwmon_dir(device_dir):
    for p in glob.glob(os.path.join(device_dir, "hwmon", "hwmon*")):
        if os.path.isdir(p):
            return p
    return None


def collect_card(card_dir, label):
    lines = []
    dev = os.path.join(card_dir, "device")

    busy = read_int(os.path.join(dev, "gpu_busy_percent"))
    if busy is not None:
        lines.append('amdgpu_gpu_utilization_percent{card="%s"} %d' % (label, busy))

    used = read_int(os.path.join(dev, "mem_info_vram_used"))
    if used is not None:
        lines.append('amdgpu_memory_used_bytes{card="%s"} %d' % (label, used))

    total = read_int(os.path.join(dev, "mem_info_vram_total"))
    if total is not None:
        lines.append('amdgpu_memory_total_bytes{card="%s"} %d' % (label, total))

    hwmon = hwmon_dir(dev)
    if hwmon:
        temp = read_int(os.path.join(hwmon, "temp1_input"))
        if temp is not None:
            lines.append('amdgpu_temperature_c{card="%s"} %.1f' % (label, temp / 1000.0))
        power = read_int(os.path.join(hwmon, "power1_average"))
        if power is not None:
            lines.append('amdgpu_power_watts{card="%s"} %.3f' % (label, power / 1e6))
    return lines


def main():
    lines = list(HEADER)
    # /sys/class/drm also holds connector entries like card3-DP-9 (symlinks
    # into the card's device dir) — match only bare cardN device names
    cards = []
    for c in glob.glob("/sys/class/drm/card*"):
        m = re.fullmatch(r"card(\d+)", os.path.basename(c))
        if m and os.path.isdir(os.path.join(c, "device")):
            cards.append((int(m.group(1)), m.group(1), c))
    for _, label, card_dir in sorted(cards):
        lines.extend(collect_card(card_dir, label))
    lines.append("")

    tmp = OUT_PATH + ".tmp"
    with open(tmp, "w") as f:
        f.write("\n".join(lines))
    os.replace(tmp, OUT_PATH)


if __name__ == "__main__":
    main()
