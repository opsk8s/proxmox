#!/usr/bin/python3
"""node_exporter textfile collector: unbound resolver statistics.

Runs as root (needs /etc/unbound/unbound_control.key) via a systemd timer and
writes cumulative counters to the node_exporter textfile directory; PromQL
applies rate() where needed.

Requires the remote-control block in /etc/unbound/unbound.conf (127.0.0.1 only).
"""

import os
import subprocess

OUT = "/var/lib/node_exporter/textfile_collector/unbound.prom"
UNBOUND_CONTROL = "/usr/sbin/unbound-control"

# key in `unbound-control stats_noreset` -> metric name.
# unbound >= 1.19 reports rcode/type/validation counters WITHOUT the
# total. prefix and only when extended-statistics: yes is set.
COUNTERS = {
    "total.num.queries": "unbound_num_queries_total",
    "total.num.cachehits": "unbound_num_cachehits_total",
    "total.num.cachemiss": "unbound_num_cachemiss_total",
    "num.answer.secure": "unbound_num_answers_secure_total",
    "num.answer.bogus": "unbound_num_answers_bogus_total",
}

GAUGES = {
    "total.recursion.time.avg": "unbound_recursion_time_avg_milliseconds",
    "total.recursion.time.median": "unbound_recursion_time_median_milliseconds",
}

RCODE_PREFIX = "num.answer.rcode."
TYPE_PREFIX = "num.query.type."


def fmt(v):
    f = float(v)
    return str(int(f)) if f.is_integer() else repr(f)


def main():
    stats = subprocess.check_output(
        [UNBOUND_CONTROL, "stats_noreset"], text=True, timeout=30
    )
    values = dict(line.split("=", 1) for line in stats.splitlines() if "=" in line)

    lines = []
    for key, metric in COUNTERS.items():
        if key in values:
            lines.append(f"# TYPE {metric} counter")
            lines.append(f"{metric} {fmt(values[key])}")
    for key, metric in GAUGES.items():
        if key in values:
            lines.append(f"# TYPE {metric} gauge")
            lines.append(f"{metric} {fmt(values[key])}")

    # answer rcode counters, e.g. SERVFAIL when every DoT upstream is down
    rcodes = sorted(
        (k[len(RCODE_PREFIX):], v)
        for k, v in values.items()
        if k.startswith(RCODE_PREFIX) and v != "0"
    )
    if rcodes:
        lines.append("# TYPE unbound_answers_rcode_total counter")
        for name, v in rcodes:
            lines.append(f'unbound_answers_rcode_total{{rcode="{name}"}} {v}')

    # per query-type counters (only types that have been seen)
    types = sorted(
        (k[len(TYPE_PREFIX):], v)
        for k, v in values.items()
        if k.startswith(TYPE_PREFIX) and v != "0"
    )
    if types:
        lines.append("# TYPE unbound_queries_by_type_total counter")
        for name, v in types:
            lines.append(f'unbound_queries_by_type_total{{type="{name}"}} {v}')

    payload = "\n".join(lines) + "\n"

    tmp = OUT + ".tmp"
    with open(tmp, "w", encoding="ascii") as f:
        f.write(payload)
    os.replace(tmp, OUT)


if __name__ == "__main__":
    main()
