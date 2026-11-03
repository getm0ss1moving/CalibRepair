#!/usr/bin/env python3
"""Parse EQR arm logs: one row per arm, intermediate (placement-parasitic) numbers.

Usage: parse_eqr.py <logs_dir>

Each eqr.tcl arm writes a block

    ===== EQR_STAGE <label> =====
    tns max <f>
    wns max <f>
    --- slew ---
    report_check_types -max_slew -violators
    ... (section header "max slew" then a "Pin ..." table, rows flagged (VIOLATED))
    ===== EQR_END <label> =====

Violation sums use the contest's own rule: over = value - limit, summed only over rows
flagged "(VIOLATED)".  These are PLACEMENT-parasitic numbers; the official
post-global-route numbers come from scripts/evaluation.tcl and live in *_metrics.csv.
"""
import os
import re
import sys

FLOAT = r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?"


def over_sum(block, section):
    m = re.search(r"^max " + section + r"\s*$(.*?)(?=^max |\Z)",
                  block, re.M | re.S)
    if not m:
        return 0.0, 0
    total, n = 0.0, 0
    for line in m.group(1).splitlines():
        if "(VIOLATED)" not in line:
            continue
        vals = re.findall(FLOAT, line)
        if len(vals) >= 3:
            over = float(vals[-2]) - float(vals[-3])
            if over > 0:
                total += over
                n += 1
    return total, n


def main():
    logs = sys.argv[1]
    rows = []
    for name in sorted(os.listdir(logs)):
        if not (name.startswith("eqr_") and name.endswith(".log")):
            continue
        label = name[:-4]
        text = open(os.path.join(logs, name), encoding="utf-8", errors="ignore").read()
        m = re.search(r"===== EQR_STAGE " + re.escape(label) + r" =====(.*?)===== EQR_END",
                      text, re.S)
        if not m:
            rows.append((label, None, None, None, None, None))
            continue
        b = m.group(1)
        tns = re.search(r"^tns max (" + FLOAT + r")", b, re.M)
        wns = re.search(r"^wns max (" + FLOAT + r")", b, re.M)
        rows.append((label,
                     float(tns.group(1)) if tns else None,
                     float(wns.group(1)) if wns else None,
                     over_sum(b, "slew"),
                     over_sum(b, "capacitance"),
                     over_sum(b, "fanout")))
    hdr = "%-30s %14s %10s %18s %16s %12s" % (
        "arm", "TNS(ns)", "WNS(ns)", "slew over(cnt)", "cap over(cnt)", "fanout")
    print(hdr)
    print("-" * len(hdr))
    for label, tns, wns, sl, cp, fn in rows:
        t = "%14.2f" % tns if tns is not None else "%14s" % "-"
        w = "%10.4f" % wns if wns is not None else "%10s" % "-"
        s = "%10.2f(%5d)" % sl if sl else "%18s" % "-"
        c = "%8.3f(%4d)" % cp if cp else "%16s" % "-"
        f = "%7.2f(%3d)" % fn if fn else "%12s" % "-"
        print("%-30s %s %s %s %s %s" % (label, t, w, s, c, f))


if __name__ == "__main__":
    main()
